using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;

namespace RailAngyerApi.Endpoints;

public static class MissionEndpoints
{
    public static void MapMissionEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/rooms/{roomId:guid}")
                       .AddEndpointFilter<RequireMemberFilter>();

        // --- ミッションの一覧 ---------------------------------------------------

        // お題は**既定でみんなに見える**。当日まで伏せたいときだけ
        // `includeOthers=false` を付けて、自分が書いたぶんだけを取る
        group.MapGet("/missions", async (Guid roomId, HttpContext http,
                                         RailAngyerDbContext db, CancellationToken ct,
                                         bool includeOthers = true) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var missions = await db.Missions.AsNoTracking()
                .Where(m => m.MissionSetId == roomId
                         && (includeOthers || m.MemberId == me.MemberId))
                .OrderBy(m => m.Station!.OrderNo)
                .Select(m => new MissionDto(m.MissionId, m.StationId, m.Content,
                                            m.EffectType, m.EffectValue, m.EffectStationId,
                                            m.MemberId, m.Member!.DisplayName))
                .ToListAsync(ct);
            return Results.Ok(missions);
        });

        group.MapPut("/missions/{missionId:guid}",
            async (Guid roomId, Guid missionId, SaveMissionRequest req, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            if (Validate(req) is { } error) return error;

            var existing = await db.Missions
                .FirstOrDefaultAsync(m => m.MissionId == missionId, ct);

            // 他人のお題を上書きさせない
            if (existing is not null && existing.MemberId != me.MemberId) return ApiResults.Forbidden();

            // 同じ駅に2個目は作れない（UQ-05）。差し替えは同じ MissionId へ PUT する
            var duplicate = await db.Missions.AnyAsync(
                m => m.MissionSetId == roomId && m.MemberId == me.MemberId
                  && m.StationId == req.StationId && m.MissionId != missionId, ct);
            if (duplicate)
            {
                return ApiResults.Conflict("mission_exists", "この駅にはすでにあなたのミッションがあります");
            }

            if (existing is null)
            {
                db.Missions.Add(new Mission
                {
                    MissionId = missionId,          // 冪等にするためクライアント生成のIDを使う
                    MissionSetId = roomId,
                    MemberId = me.MemberId,
                    StationId = req.StationId,
                    Content = req.Content,
                    EffectType = (byte)req.EffectType,
                    EffectValue = (byte?)req.EffectValue,
                    EffectStationId = req.EffectStationId,
                    CreatedAt = DateTime.UtcNow
                });
            }
            else
            {
                existing.StationId = req.StationId;
                existing.Content = req.Content;
                existing.EffectType = (byte)req.EffectType;
                existing.EffectValue = (byte?)req.EffectValue;
                existing.EffectStationId = req.EffectStationId;
            }

            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        });

        group.MapDelete("/missions/{missionId:guid}",
            async (Guid roomId, Guid missionId, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var mission = await db.Missions.FirstOrDefaultAsync(m => m.MissionId == missionId, ct);
            if (mission is null) return Results.NoContent();          // 冪等
            if (mission.MemberId != me.MemberId) return ApiResults.Forbidden();

            db.Missions.Remove(mission);
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        });

        // --- 準備状況 -----------------------------------------------------------

        // 駅ごとの件数と、**既定では中身も**返す。
        // 当日まで伏せる予定では `includeContent=false` を付ける。
        // そのときは中身を端末へ送らない（画面で隠すだけでは覗けてしまう）
        group.MapGet("/missions/summary", async (Guid roomId, HttpContext http,
                                                 RailAngyerDbContext db, CancellationToken ct,
                                                 bool includeContent = true) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var missions = await db.Missions.AsNoTracking()
                .Where(m => m.MissionSetId == roomId)
                .OrderBy(m => m.Station!.OrderNo)
                .Select(m => new
                {
                    m.MissionId,
                    m.StationId,
                    m.MemberId,
                    m.Content,
                    m.EffectType,
                    DisplayName = m.Member!.DisplayName
                })
                .ToListAsync(ct);

            // ルーム1件ぶんの件数なので、まとめはメモリ上で組み立てて構わない
            var rows = missions
                .GroupBy(m => m.StationId)
                .Select(g => new MissionSummaryDto(
                    g.Key,
                    g.Count(),
                    g.Count(m => m.EffectType != 0),
                    g.Count(m => m.EffectType == 2),   // 戻るが多いと進まなくなる（E-08）
                    includeContent
                        ? g.Select(m => new MissionBriefDto(m.MissionId, m.MemberId,
                                                            m.Content, m.DisplayName)).ToList()
                        : []))
                .ToList();
            return Results.Ok(rows);
        });

        // --- 着地した駅のミッション ---------------------------------------------

        group.MapGet("/stations/{stationId:int}/missions",
            async (Guid roomId, int stationId, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            // 先読みで全ミッションを覗けないよう、いまその駅に着地しているかを確かめる
            var landed = await db.Turns.AnyAsync(
                t => t.MissionSetId == roomId
                  && t.EndStationId == null
                  && t.ArrivedAt != null
                  && t.LandingStationId == stationId, ct);
            if (!landed)
            {
                return ApiResults.Forbidden("not_landed", "その駅に着地していません");
            }

            // 既に引いたお題は候補から外す（R-14）
            var used = db.Turns.Where(t => t.MissionSetId == roomId && t.SelectedMissionId != null)
                               .Select(t => t.SelectedMissionId!.Value);

            var missions = await db.Missions.AsNoTracking()
                .Where(m => m.MissionSetId == roomId && m.StationId == stationId && !used.Contains(m.MissionId))
                .Select(m => new MissionDto(m.MissionId, m.StationId, m.Content,
                                            m.EffectType, m.EffectValue, m.EffectStationId,
                                            m.MemberId, m.Member!.DisplayName))
                .ToListAsync(ct);
            return Results.Ok(missions);
        });
    }

    /// <summary>DBのCHECK制約（CK-06 / CK-07）に相当する検証。例外より先に400で返す</summary>
    private static IResult? Validate(SaveMissionRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Content))
        {
            return ApiResults.BadRequest("empty_content", "お題を入力してください");
        }
        if (req.Content.Length > 300)
        {
            return ApiResults.BadRequest("content_too_long", "お題は300文字までです");
        }
        if (req.EffectType is < 0 or > 4)
        {
            return ApiResults.BadRequest("invalid_effect", "効果の種類が不正です");
        }

        var needsValue = req.EffectType is 1 or 2;
        if (needsValue && req.EffectValue is not (>= 1 and <= 9))
        {
            return ApiResults.BadRequest("invalid_effect_value", "駅数は1〜9で指定してください");
        }
        if (!needsValue && req.EffectValue is not null)
        {
            return ApiResults.BadRequest("invalid_effect_value", "この効果では駅数を指定できません");
        }

        var needsStation = req.EffectType == 4;
        if (needsStation && req.EffectStationId is null)
        {
            return ApiResults.BadRequest("invalid_effect_station", "移動先の駅を選んでください");
        }
        if (!needsStation && req.EffectStationId is not null)
        {
            return ApiResults.BadRequest("invalid_effect_station", "この効果では移動先を指定できません");
        }
        return null;
    }
}

public record SaveMissionRequest(int StationId, string Content, int EffectType,
                                 int? EffectValue, int? EffectStationId);
public record MissionDto(Guid MissionId, int StationId, string Content,
                         byte EffectType, byte? EffectValue, int? EffectStationId,
                         Guid MemberId, string CreatedByName);
/// <summary>準備状況に添える1件ぶん。伏せる設定のときは空になる</summary>
public record MissionBriefDto(Guid MissionId, Guid MemberId, string Content, string CreatedByName);
public record MissionSummaryDto(int StationId, int Count, int EffectCount, int BackEffectCount,
                                IReadOnlyList<MissionBriefDto> Missions);
