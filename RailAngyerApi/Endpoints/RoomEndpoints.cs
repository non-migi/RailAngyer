using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;

namespace RailAngyerApi.Endpoints;

public static class RoomEndpoints
{
    public static void MapRoomEndpoints(this IEndpointRouteBuilder app)
    {
        // --- マスタ（認証不要） -------------------------------------------------

        app.MapGet("/courses", async (RailAngyerDbContext db, CancellationToken ct) =>
        {
            var courses = await db.Courses
                .AsNoTracking()
                .Select(c => new CourseDto(
                    c.CourseId, c.Name, c.LineColor,
                    c.Stations.OrderBy(s => s.OrderNo)
                        .Select(s => new StationDto(s.StationId, s.Name, s.OrderNo, s.Latitude, s.Longitude))
                        .ToList()))
                .ToListAsync(ct);
            return Results.Ok(courses);
        });

        // --- ルーム作成 ---------------------------------------------------------

        app.MapPost("/rooms", async (CreateRoomRequest req, RailAngyerDbContext db, CancellationToken ct) =>
        {
            if (req.StartStationId == req.GoalStationId)
            {
                return ApiResults.BadRequest("invalid_range", "スタートとゴールは別の駅にしてください");
            }
            if (req.DiceMax is < 1 or > 9)
            {
                return ApiResults.BadRequest("invalid_dice_max", "最大出目は1〜9です");
            }

            // 区間の駅が、指定したコースのものか確かめる（DBのCHECKでは表現できない）
            var stationCourseIds = await db.Stations
                .Where(s => s.StationId == req.StartStationId || s.StationId == req.GoalStationId)
                .Select(s => s.CourseId)
                .ToListAsync(ct);
            if (stationCourseIds.Count != 2 || stationCourseIds.Any(id => id != req.CourseId))
            {
                return ApiResults.BadRequest("invalid_range", "区間の駅がコースと一致しません");
            }

            var now = DateTime.UtcNow;
            var room = new MissionSet
            {
                MissionSetId = Guid.NewGuid(),
                CourseId = req.CourseId,
                Name = req.Name,
                InviteCode = await GenerateUniqueInviteCodeAsync(db, ct),
                StartStationId = req.StartStationId,
                GoalStationId = req.GoalStationId,
                DiceMax = (byte)req.DiceMax,
                CreatedAt = now
            };
            db.MissionSets.Add(room);

            var token = MemberTokens.Generate();
            var member = new Member
            {
                MemberId = Guid.NewGuid(),
                MissionSetId = room.MissionSetId,
                DisplayName = req.DisplayName,
                JoinedAt = now,
                TokenHash = MemberTokens.Hash(token)
            };

            // ⚠️ MissionSet.CreatedBy → Member、Member.MissionSetId → MissionSet と参照が循環している。
            // 3つを一度に SaveChanges すると、どちらのINSERTが先でも相手がまだ無く、
            // SQL Server が FK 違反（547）を返す。作成者の紐付けだけ後回しにして3段階で書く
            await db.SaveChangesAsync(ct);          // ① ルーム（作成者は未設定）
            db.Members.Add(member);
            await db.SaveChangesAsync(ct);          // ② 作成者
            room.CreatedBy = member.MemberId;
            await db.SaveChangesAsync(ct);          // ③ 紐付け

            return Results.Created($"/rooms/{room.MissionSetId}",
                new JoinedRoomDto(room.MissionSetId, room.InviteCode, member.MemberId, token));
        });

        // --- 参加 ---------------------------------------------------------------

        app.MapPost("/rooms/join", async (JoinRoomRequest req, RailAngyerDbContext db, CancellationToken ct) =>
        {
            var room = await db.MissionSets
                .FirstOrDefaultAsync(r => r.InviteCode == req.InviteCode, ct);
            if (room is null)
            {
                return ApiResults.NotFound("invalid_invite_code", "招待コードが違います");
            }

            var taken = await db.Members.AnyAsync(
                m => m.MissionSetId == room.MissionSetId && m.DisplayName == req.DisplayName, ct);
            if (taken)
            {
                return ApiResults.Conflict("display_name_taken", "その名前はすでに使われています");
            }

            var token = MemberTokens.Generate();
            var member = new Member
            {
                MemberId = Guid.NewGuid(),
                MissionSetId = room.MissionSetId,
                DisplayName = req.DisplayName,
                JoinedAt = DateTime.UtcNow,
                TokenHash = MemberTokens.Hash(token)
            };
            db.Members.Add(member);
            await db.SaveChangesAsync(ct);

            return Results.Ok(new JoinedRoomDto(room.MissionSetId, room.InviteCode, member.MemberId, token));
        });

        // --- ルームの取得（認証が要る） -----------------------------------------

        var authed = app.MapGroup("/rooms/{roomId:guid}")
                        .AddEndpointFilter<RequireMemberFilter>();

        authed.MapGet("", async (Guid roomId, HttpContext http, RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var room = await db.MissionSets.AsNoTracking()
                .FirstOrDefaultAsync(r => r.MissionSetId == roomId, ct);
            if (room is null) return Results.NotFound();

            var members = await db.Members.AsNoTracking()
                .Where(m => m.MissionSetId == roomId)
                .OrderBy(m => m.JoinedAt)
                .Select(m => new MemberDto(m.MemberId, m.DisplayName, m.JoinedAt))
                .ToListAsync(ct);

            return Results.Ok(new RoomDto(room.MissionSetId, room.Name, room.CourseId,
                                          room.StartStationId, room.GoalStationId, room.DiceMax,
                                          room.InviteCode, members, room.MissionVisibility));
        });

        // --- 設定の変更 ---------------------------------------------------------

        authed.MapPatch("", async (Guid roomId, UpdateRoomRequest req, HttpContext http,
                                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var room = await db.MissionSets.FirstOrDefaultAsync(r => r.MissionSetId == roomId, ct);
            if (room is null) return Results.NotFound();

            // お題の見え方だけは、いつでも切り替えられる。
            // 区間や出目と違って、すでにある記録の整合を壊さないため
            if (req.MissionVisibility is { } visibility)
            {
                if (visibility is < 0 or > 1)
                {
                    return ApiResults.BadRequest("invalid_visibility", "お題の見え方の値が不正です");
                }
                room.MissionVisibility = (byte)visibility;
                await db.SaveChangesAsync(ct);
            }

            // 区間と出目はプレイ開始後は変えられない（T-06）。
            // 区間外を指す効果や訪問記録が残って整合しなくなる
            if (req.StartStationId is null && req.GoalStationId is null && req.DiceMax is null)
            {
                return Results.NoContent();
            }
            if (await db.Turns.AnyAsync(t => t.MissionSetId == roomId, ct))
            {
                return ApiResults.Conflict("rules_locked", "プレイ中は区間と最大出目を変更できません");
            }

            if (req.DiceMax is { } dice)
            {
                if (dice is < 1 or > 9)
                {
                    return ApiResults.BadRequest("invalid_dice_max", "最大出目は1〜9です");
                }
                room.DiceMax = (byte)dice;
            }
            if (req.StartStationId is { } start) room.StartStationId = start;
            if (req.GoalStationId is { } goal) room.GoalStationId = goal;

            if (room.StartStationId == room.GoalStationId)
            {
                return ApiResults.BadRequest("invalid_range", "スタートとゴールは別の駅にしてください");
            }

            // POST /rooms と同じ検査。変えた駅だけ見ればよい
            var changedStationIds = new List<int>();
            if (req.StartStationId is { } newStart) changedStationIds.Add(newStart);
            if (req.GoalStationId is { } newGoal) changedStationIds.Add(newGoal);
            if (changedStationIds.Count > 0)
            {
                var stationCourseIds = await db.Stations
                    .Where(s => changedStationIds.Contains(s.StationId))
                    .Select(s => s.CourseId)
                    .ToListAsync(ct);
                if (stationCourseIds.Count != changedStationIds.Count
                    || stationCourseIds.Any(id => id != room.CourseId))
                {
                    return ApiResults.BadRequest("invalid_range", "区間の駅がコースと一致しません");
                }
            }

            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        });
    }

    private static async Task<string> GenerateUniqueInviteCodeAsync(RailAngyerDbContext db, CancellationToken ct)
    {
        for (var attempt = 0; attempt < 10; attempt++)
        {
            var code = MemberTokens.GenerateInviteCode();
            if (!await db.MissionSets.AnyAsync(r => r.InviteCode == code, ct)) return code;
        }
        throw new InvalidOperationException("招待コードを発行できませんでした");
    }
}

// --- 受け渡しの形 -----------------------------------------------------------

public record CreateRoomRequest(int CourseId, string Name, int StartStationId, int GoalStationId,
                                int DiceMax, string DisplayName);
public record JoinRoomRequest(string InviteCode, string DisplayName);
public record UpdateRoomRequest(int? StartStationId, int? GoalStationId, int? DiceMax,
                                int? MissionVisibility = null);

public record JoinedRoomDto(Guid RoomId, string InviteCode, Guid MemberId, string Token);
public record MemberDto(Guid MemberId, string DisplayName, DateTime JoinedAt);
public record RoomDto(Guid RoomId, string Name, int CourseId, int StartStationId, int GoalStationId,
                      byte DiceMax, string InviteCode, List<MemberDto> Members,
                      byte MissionVisibility = 0);
public record CourseDto(int CourseId, string Name, string? LineColor, List<StationDto> Stations);
public record StationDto(int StationId, string Name, int OrderNo, double Latitude, double Longitude);
