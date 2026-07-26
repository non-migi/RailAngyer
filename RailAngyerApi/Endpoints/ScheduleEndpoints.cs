using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;

namespace RailAngyerApi.Endpoints;

/// <summary>
/// 予定と出欠（フェーズ3 / 11_API設計.md §3.4）。
///
/// <para>作った人だけが直せる。出欠は<b>自分のぶんだけ</b>変えられる。
/// 身内向けでも「誰が参加と答えたか」は本人にしか動かせないようにしておく（G-5）。</para>
/// </summary>
public static class ScheduleEndpoints
{
    public static void MapScheduleEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/rooms/{roomId:guid}")
                       .AddEndpointFilter<RequireMemberFilter>();

        // --- 一覧 ---------------------------------------------------------------

        group.MapGet("/schedules", async (Guid roomId, HttpContext http,
                                          RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var schedules = await db.Schedules.AsNoTracking()
                .Where(s => s.MissionSetId == roomId)
                .OrderBy(s => s.StartAt)
                .Select(s => new ScheduleDto(
                    s.ScheduleId, s.Title, s.StartAt, s.MeetPlace, s.CreatedBy,
                    s.Attendees.Select(a => new AttendeeDto(a.MemberId, a.Member!.DisplayName, a.Status))
                               .ToList()))
                .ToListAsync(ct);

            return Results.Ok(schedules);
        });

        // --- 作成・更新（冪等） -------------------------------------------------

        group.MapPut("/schedules/{scheduleId:guid}",
            async (Guid roomId, Guid scheduleId, SaveScheduleRequest req, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            if (string.IsNullOrWhiteSpace(req.Title))
            {
                return ApiResults.BadRequest("empty_title", "予定の名前を入力してください");
            }
            if (req.Title.Length > 100)
            {
                return ApiResults.BadRequest("title_too_long", "予定の名前は100文字までです");
            }
            if (req.MeetPlace is { Length: > 100 })
            {
                return ApiResults.BadRequest("meet_place_too_long", "集合場所は100文字までです");
            }

            var schedule = await db.Schedules
                .FirstOrDefaultAsync(s => s.ScheduleId == scheduleId, ct);

            if (schedule is not null)
            {
                if (schedule.MissionSetId != roomId) return ApiResults.Forbidden();
                // 予定は全員で共有するものなので、直せるのは立てた人だけにする
                if (schedule.CreatedBy != me.MemberId)
                {
                    return ApiResults.Forbidden("not_owner", "予定を立てた人だけが変更できます");
                }
            }
            else
            {
                schedule = new Schedule
                {
                    ScheduleId = scheduleId,        // 冪等にするためクライアント生成のIDを使う
                    MissionSetId = roomId,
                    CreatedBy = me.MemberId
                };
                db.Schedules.Add(schedule);
            }

            schedule.Title = req.Title;
            schedule.StartAt = req.StartAt;
            schedule.MeetPlace = req.MeetPlace;

            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        });

        group.MapDelete("/schedules/{scheduleId:guid}",
            async (Guid roomId, Guid scheduleId, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var schedule = await db.Schedules
                .FirstOrDefaultAsync(s => s.ScheduleId == scheduleId, ct);
            if (schedule is null) return Results.NoContent();            // 冪等
            if (schedule.MissionSetId != roomId) return ApiResults.Forbidden();
            if (schedule.CreatedBy != me.MemberId)
            {
                return ApiResults.Forbidden("not_owner", "予定を立てた人だけが削除できます");
            }

            db.Schedules.Remove(schedule);       // 出欠は CASCADE で消える
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        });

        // --- 出欠（自分のぶんだけ） ---------------------------------------------

        group.MapPut("/schedules/{scheduleId:guid}/attendance",
            async (Guid roomId, Guid scheduleId, SaveAttendanceRequest req, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            if (req.Status is < 0 or > 2)
            {
                return ApiResults.BadRequest("invalid_status", "出欠の値が不正です");
            }

            var schedule = await db.Schedules.AsNoTracking()
                .FirstOrDefaultAsync(s => s.ScheduleId == scheduleId, ct);
            if (schedule is null)
            {
                return ApiResults.NotFound("schedule_not_found", "その予定はありません");
            }
            if (schedule.MissionSetId != roomId) return ApiResults.Forbidden();

            // 誰の出欠かはトークンから決める。リクエストの MemberId は受け取らない（AP-05）
            var attendee = await db.ScheduleAttendees
                .FirstOrDefaultAsync(a => a.ScheduleId == scheduleId && a.MemberId == me.MemberId, ct);

            if (attendee is null)
            {
                db.ScheduleAttendees.Add(new ScheduleAttendee
                {
                    ScheduleId = scheduleId,
                    MemberId = me.MemberId,
                    Status = (byte)req.Status
                });
            }
            else
            {
                attendee.Status = (byte)req.Status;
            }

            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        });
    }
}

public record SaveScheduleRequest(string Title, DateTime StartAt, string? MeetPlace);
public record SaveAttendanceRequest(int Status);

public record ScheduleDto(Guid ScheduleId, string Title, DateTime StartAt, string? MeetPlace,
                          Guid? CreatedBy, List<AttendeeDto> Attendees);
public record AttendeeDto(Guid MemberId, string DisplayName, byte Status);
