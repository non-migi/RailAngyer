using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;
using RailAngyerApi.Storage;

namespace RailAngyerApi.Endpoints;

/// <summary>
/// 進行（ターンと訪問）。
///
/// <para><b>書き込みはすべて冪等な PUT。</b>主キーはクライアントが生成した UUID なので、
/// オフラインで溜めた要求を素朴に再送しても二重にならない（11_API設計.md §4 / G-7）。</para>
/// </summary>
public static class ProgressEndpoints
{
    public static void MapProgressEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/rooms/{roomId:guid}")
                       .AddEndpointFilter<RequireMemberFilter>();

        // --- 現在の状態 ---------------------------------------------------------

        group.MapGet("/state", async (Guid roomId, HttpContext http,
                                      RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var room = await db.MissionSets.AsNoTracking()
                .FirstOrDefaultAsync(r => r.MissionSetId == roomId, ct);
            if (room is null) return ApiResults.NotFound("room_not_found", "ルームが見つかりません");

            var currentStationId = await CurrentStationIdAsync(db, room, ct);

            var active = await db.Turns.AsNoTracking()
                .Where(t => t.MissionSetId == roomId && t.EndStationId == null)
                .OrderByDescending(t => t.RolledAt)
                .Select(t => new ActiveTurnDto(t.TurnId, t.TurnNo, t.DiceValue,
                                               t.FromStationId, t.LandingStationId,
                                               t.RolledAt, t.ArrivedAt,
                                               t.SelectedMissionId, t.MissionDone,
                                               t.AppliedEffectType))
                .FirstOrDefaultAsync(ct);

            var visited = await db.Visits.AsNoTracking()
                .Where(v => v.MissionSetId == roomId)
                .Select(v => new VisitDto(v.VisitId, v.TurnId, v.StationId, v.ArrivedAt, v.VisitKind))
                .ToListAsync(ct);

            var turnCount = await db.Turns.CountAsync(t => t.MissionSetId == roomId && t.CompletedAt != null, ct);

            return Results.Ok(new StateDto(currentStationId,
                                           currentStationId == room.GoalStationId,
                                           active, visited, turnCount));
        });

        // --- ターン -------------------------------------------------------------

        group.MapPut("/turns/{turnId:guid}",
            async (Guid roomId, Guid turnId, SaveTurnRequest req, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var turn = await db.Turns.FirstOrDefaultAsync(t => t.TurnId == turnId, ct);

            if (turn is null)
            {
                if (req.DiceValue is not (>= 1 and <= 9))
                {
                    return ApiResults.BadRequest("invalid_dice", "出目が不正です");
                }

                // 進行中のターンは1つまで。2人目は 409 で弾く（E-10）
                var inProgress = await db.Turns
                    .FirstOrDefaultAsync(t => t.MissionSetId == roomId && t.EndStationId == null, ct);
                if (inProgress is not null)
                {
                    return ApiResults.Conflict("turn_in_progress",
                                               "他の端末がサイコロを振っている最中です",
                                               new { turnId = inProgress.TurnId });
                }

                // 表示用の連番はサーバーが振る。順序の判定には使わない（RolledAt を使う）
                var nextNo = await db.Turns.Where(t => t.MissionSetId == roomId)
                                           .MaxAsync(t => (int?)t.TurnNo, ct) ?? 0;

                turn = new Turn
                {
                    TurnId = turnId,
                    MissionSetId = roomId,
                    TurnNo = nextNo + 1,
                    FromStationId = req.FromStationId,
                    DiceValue = (byte)req.DiceValue,
                    LandingStationId = req.LandingStationId,
                    RolledAt = req.RolledAt ?? DateTime.UtcNow
                };
                db.Turns.Add(turn);
            }

            // 差分だけを送ってこられるようにする（着地 → ミッション → 効果 と何度も PUT される）
            if (req.ArrivedAt is { } arrived) turn.ArrivedAt = arrived;
            if (req.SelectedMissionId is { } missionId) turn.SelectedMissionId = missionId;
            if (req.MissionDone is { } done) turn.MissionDone = done;
            if (req.AppliedEffectType is { } effect) turn.AppliedEffectType = (byte)effect;
            if (req.EndStationId is { } end)
            {
                turn.EndStationId = end;
                turn.CompletedAt = req.CompletedAt ?? DateTime.UtcNow;
            }

            await db.SaveChangesAsync(ct);
            return Results.Ok(new SavedTurnDto(turn.TurnId, turn.TurnNo));
        });

        // --- 訪問 ---------------------------------------------------------------

        group.MapPut("/visits/{visitId:guid}",
            async (Guid roomId, Guid visitId, SaveVisitRequest req, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            if (req.VisitKind is < 0 or > 4)
            {
                return ApiResults.BadRequest("invalid_visit_kind", "訪問の種別が不正です");
            }
            // 始点だけがターンに属さない（CK-11）
            if (req.VisitKind == 0 != (req.TurnId is null))
            {
                return ApiResults.BadRequest("invalid_visit_link",
                                             "始点以外の訪問はターンに紐づける必要があります");
            }

            var visit = await db.Visits.FirstOrDefaultAsync(v => v.VisitId == visitId, ct);
            if (visit is null)
            {
                db.Visits.Add(new Visit
                {
                    VisitId = visitId,
                    MissionSetId = roomId,
                    TurnId = req.TurnId,
                    StationId = req.StationId,
                    ArrivedAt = req.ArrivedAt ?? DateTime.UtcNow,
                    VisitKind = (byte)req.VisitKind
                });
                await db.SaveChangesAsync(ct);
            }
            // 既にあれば何もしない。訪問は一度書いたら書き換えない

            return Results.NoContent();
        });

        // --- 記録リセット -------------------------------------------------------

        group.MapDelete("/progress", async (Guid roomId, HttpContext http,
                                            RailAngyerDbContext db, IPhotoStorage storage,
                                            CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            // 写真の行は Visit の CASCADE で消えるが、<b>Blobの実体は消えない</b>。
            // 先に実体を落としておかないと、誰も辿れない孤児だけが残る（§5「孤児Blobの掃除」）
            if (storage.IsConfigured)
            {
                await storage.DeletePrefixAsync(IPhotoStorage.RoomPrefix(roomId), ct);
            }

            // Visit が Turn を参照するので Visit が先
            await db.Visits.Where(v => v.MissionSetId == roomId).ExecuteDeleteAsync(ct);
            await db.Turns.Where(t => t.MissionSetId == roomId).ExecuteDeleteAsync(ct);
            return Results.NoContent();
        });
    }

    /// <summary>
    /// 現在位置。<b>最後に完了したターンの終了位置</b>。完了ターンが無ければスタート駅。
    /// 「最後」は TurnNo ではなく RolledAt で決める（オフラインの採番衝突を実害にしないため）。
    /// </summary>
    private static async Task<int> CurrentStationIdAsync(RailAngyerDbContext db, MissionSet room,
                                                         CancellationToken ct)
    {
        var last = await db.Turns.AsNoTracking()
            .Where(t => t.MissionSetId == room.MissionSetId && t.EndStationId != null)
            .OrderByDescending(t => t.RolledAt)
            .Select(t => t.EndStationId)
            .FirstOrDefaultAsync(ct);
        return last ?? room.StartStationId;
    }
}

public record SaveTurnRequest(int FromStationId, int DiceValue, int LandingStationId,
                              DateTime? RolledAt, DateTime? ArrivedAt,
                              Guid? SelectedMissionId, bool? MissionDone,
                              int? AppliedEffectType, int? EndStationId, DateTime? CompletedAt);
public record SaveVisitRequest(Guid? TurnId, int StationId, DateTime? ArrivedAt, int VisitKind);

public record SavedTurnDto(Guid TurnId, int TurnNo);
public record ActiveTurnDto(Guid TurnId, int TurnNo, byte DiceValue, int FromStationId,
                            int LandingStationId, DateTime RolledAt, DateTime? ArrivedAt,
                            Guid? SelectedMissionId, bool MissionDone, byte? AppliedEffectType);
public record VisitDto(Guid VisitId, Guid? TurnId, int StationId, DateTime ArrivedAt, byte VisitKind);
public record StateDto(int CurrentStationId, bool IsCleared, ActiveTurnDto? ActiveTurn,
                       List<VisitDto> Visits, int CompletedTurnCount);
