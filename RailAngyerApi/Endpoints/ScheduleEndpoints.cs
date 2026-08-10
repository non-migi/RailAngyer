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
                    s.ScheduleId, s.Title, s.StartAt, s.MeetPlace,
                    s.CourseId, s.CourseName, s.StartOrder, s.GoalOrder, s.DiceMax, s.CreatedBy,
                    s.IsLap, s.LoopDirection, s.UsesDice, s.UsesMissions,
                    s.MissionVisibility, s.ArrivalRadius, s.IsShared, s.TimeZoneId,
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
            if (req.CourseName is { Length: > 50 })
            {
                return ApiResults.BadRequest("course_name_too_long", "コース名は50文字までです");
            }
            // 一周する予定は、出発した駅へ戻ってくるのが正しい。ここだけ同じ駅を許す
            if (req.IsLap != true
                && req.StartOrder is { } start && req.GoalOrder is { } goal && start == goal)
            {
                return ApiResults.BadRequest("same_start_goal", "スタートとゴールは別の駅にしてください");
            }
            if (req.DiceMax is < 1 or > 9)
            {
                return ApiResults.BadRequest("invalid_dice", "サイコロの最大出目は1〜9です");
            }
            if (req.LoopDirection is not (null or 1 or -1))
            {
                return ApiResults.BadRequest("invalid_loop_direction", "まわる向きの値が不正です");
            }
            if (req.MissionVisibility is < 0 or > 1)
            {
                return ApiResults.BadRequest("invalid_visibility", "お題の見え方の値が不正です");
            }
            if (req.ArrivalRadius is { } radius && (radius < 50 || radius > 320))
            {
                return ApiResults.BadRequest("invalid_radius", "到着判定の半径は50〜320mです");
            }
            if (req.TimeZoneId is { Length: > 64 })
            {
                return ApiResults.BadRequest("time_zone_too_long", "タイムゾーン名が長すぎます");
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
            schedule.CourseId = req.CourseId;
            schedule.CourseName = req.CourseName;
            schedule.StartOrder = req.StartOrder;
            schedule.GoalOrder = req.GoalOrder;
            schedule.DiceMax = req.DiceMax is { } dice ? (byte)dice : null;
            schedule.IsLap = req.IsLap;
            schedule.LoopDirection = req.LoopDirection is { } dir ? (short)dir : null;
            schedule.UsesDice = req.UsesDice;
            schedule.UsesMissions = req.UsesMissions;
            schedule.MissionVisibility =
                req.MissionVisibility is { } visibility ? (byte)visibility : null;
            schedule.ArrivalRadius = req.ArrivalRadius;
            schedule.IsShared = req.IsShared;
            schedule.TimeZoneId = req.TimeZoneId;

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

/// <summary>
/// 予定の保存。<b>詳細設定はすべて省略できる</b>ので、
/// 旧アプリからのリクエストもそのまま受け取れる（NULL = これまで通りの遊び方）。
/// </summary>
public record SaveScheduleRequest(string Title, DateTime StartAt, string? MeetPlace,
                                  int? CourseId = null, string? CourseName = null,
                                  int? StartOrder = null, int? GoalOrder = null,
                                  int? DiceMax = null,
                                  bool? IsLap = null, int? LoopDirection = null,
                                  bool? UsesDice = null, bool? UsesMissions = null,
                                  int? MissionVisibility = null, double? ArrivalRadius = null,
                                  bool? IsShared = null, string? TimeZoneId = null);
public record SaveAttendanceRequest(int Status);

public record ScheduleDto(Guid ScheduleId, string Title, DateTime StartAt, string? MeetPlace,
                          int? CourseId, string? CourseName, int? StartOrder, int? GoalOrder,
                          byte? DiceMax, Guid? CreatedBy,
                          bool? IsLap, short? LoopDirection, bool? UsesDice, bool? UsesMissions,
                          byte? MissionVisibility, double? ArrivalRadius, bool? IsShared,
                          string? TimeZoneId,
                          List<AttendeeDto> Attendees);
public record AttendeeDto(Guid MemberId, string DisplayName, byte Status);
