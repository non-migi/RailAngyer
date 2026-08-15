using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;
using RailAngyerApi.Storage;

namespace RailAngyerApi.Endpoints;

/// <summary>
/// メンバーの離脱と除名。
///
/// <para><b>消すのは本人のデータだけ。</b>写真・お題・出欠と Member 行を消し、
/// ターン・訪問はルーム共有の進行記録なので残す（消すお題を指しているターンは参照だけ外す）。
/// Member 行が消えると TokenHash も消えるので、発行済みトークンはそこで使えなくなる。</para>
/// </summary>
public static class MemberEndpoints
{
    public static void MapMemberEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/rooms/{roomId:guid}")
                       .AddEndpointFilter<RequireMemberFilter>();

        // --- 退室（自分のデータを消して抜ける） ---------------------------------

        group.MapDelete("/members/me", async (Guid roomId, HttpContext http,
                                              RailAngyerDbContext db, IPhotoStorage storage,
                                              CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            await RemoveMemberDataAsync(roomId, me.MemberId, db, storage, ct);
            return Results.NoContent();
        });

        // --- 除名（ルーム作成者のみ） -------------------------------------------

        group.MapDelete("/members/{memberId:guid}",
            async (Guid roomId, Guid memberId, HttpContext http,
                   RailAngyerDbContext db, IPhotoStorage storage, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            // 自分自身を指定したら「me」と同じ扱い。作成者でなくても自分は消せる
            if (memberId == me.MemberId)
            {
                await RemoveMemberDataAsync(roomId, memberId, db, storage, ct);
                return Results.NoContent();
            }

            var room = await db.MissionSets.AsNoTracking()
                .FirstOrDefaultAsync(r => r.MissionSetId == roomId, ct);
            if (room is null) return Results.NotFound();
            if (room.CreatedBy != me.MemberId)
            {
                return ApiResults.Forbidden("not_owner", "ルームを作った人だけがメンバーを外せます");
            }

            var exists = await db.Members.AnyAsync(
                m => m.MemberId == memberId && m.MissionSetId == roomId, ct);
            if (!exists)
            {
                return ApiResults.NotFound("member_not_found", "そのメンバーはいません");
            }

            await RemoveMemberDataAsync(roomId, memberId, db, storage, ct);
            return Results.NoContent();
        });
    }

    /// <summary>
    /// メンバー1人ぶんのデータを消す。
    /// MissionSet 側に CASCADE を張れないため、06_schema.sql §11 と同じく順序を決めて消す。
    /// 途中で失敗しても各段の後は整合が保たれていて、もう一度呼べば続きから消せる。
    ///
    /// <para><b>②〜⑤はひとつのトランザクションにまとめ、そのなかでは ct を使わない。</b>
    /// ここでの ct は Minimal API のバインドにより HttpContext.RequestAborted で、
    /// アプリ側は90秒で諦める（ApiClient.swift の coldStartTimeout）。
    /// 電波の悪い場所で退室するとふつうに接続が切れ、そのたびに削除が途中で止まってしまう。
    /// 後戻りできない点を過ぎたら、クライアントが待つのをやめても最後までやり切る。</para>
    ///
    /// <para>①（Blob削除）だけはトランザクションの外に置く。Blob は消したら戻せないので、
    /// DB をロールバックしても写真は帰ってこないため。おかげで残りうる中間状態は
    /// 「写真だけ消えて、お題・出欠・メンバー行は無傷」の1種類だけになり、もう一度呼べば続きから消せる。</para>
    /// </summary>
    private static async Task RemoveMemberDataAsync(Guid roomId, Guid memberId,
                                                    RailAngyerDbContext db, IPhotoStorage storage,
                                                    CancellationToken ct)
    {
        // ① 写真。先にBlobを消す。ここで失敗したら行を残す方がよい
        //   （行が無いBlobは孤児になって誰も掃除できないが、逆は次の削除でやり直せる）
        var photos = await db.Photos
            .Where(p => p.MemberId == memberId && p.Visit!.MissionSetId == roomId)
            .ToListAsync(ct);
        foreach (var photo in photos)
        {
            if (storage.IsConfigured) await storage.DeleteAsync(photo.BlobUrl, ct);
        }
        db.Photos.RemoveRange(photos);
        await db.SaveChangesAsync(ct);

        // ここから先は中断させない。ct は渡さず CancellationToken.None で通す
        // （②〜⑤の途中で切れると、お題だけ消えて本人が残るような半端な状態になるため）。
        // 再試行ストラテジ（Program.cs の EnableRetryOnFailure）を有効にしたままでは
        // BeginTransaction が例外になるので、ストラテジ自身に実行してもらう
        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(CancellationToken.None);

            // ② 消すお題を引いているターンは、参照だけ外す（FK: Turn.SelectedMissionId）。
            //    ターン・訪問そのものはルーム共有の進行記録なので消さない
            var turns = await db.Turns
                .Where(t => t.MissionSetId == roomId && t.SelectedMission!.MemberId == memberId)
                .ToListAsync(CancellationToken.None);
            foreach (var turn in turns) turn.SelectedMissionId = null;
            await db.SaveChangesAsync(CancellationToken.None);

            // ③ お題（FK: FK_Mission_Member）
            var missions = await db.Missions
                .Where(m => m.MissionSetId == roomId && m.MemberId == memberId)
                .ToListAsync(CancellationToken.None);
            db.Missions.RemoveRange(missions);
            await db.SaveChangesAsync(CancellationToken.None);

            // ④ 出欠と「作成者」参照。予定とルームは共有物なので残し、作成者だけ付け替える
            //    （FK: FK_Attendee_Member / FK_Schedule_Creator / FK_MissionSet_Creator）
            var attendances = await db.ScheduleAttendees
                .Where(a => a.MemberId == memberId)
                .ToListAsync(CancellationToken.None);
            db.ScheduleAttendees.RemoveRange(attendances);

            // 抜けたあとに残る人のうち最古参へ引き継ぐ。null のままにすると、
            //   ・ルーム: 除名は CreatedBy == 自分 でしか通らないので、作った人が抜けた時点で
            //     誰も迷惑ユーザーを外せなくなる（App Store ガイドライン 1.2 が求める手段が消える）
            //   ・予定: 所有者チェックにより PUT も DELETE も全員 403 になり、
            //     直すことも消すこともできない予定が残り続ける
            // 同じ JoinedAt が並んだときのために MemberId でも並べて、引き継ぎ先を一意に決める
            var successorId = await db.Members
                .Where(m => m.MissionSetId == roomId && m.MemberId != memberId)
                .OrderBy(m => m.JoinedAt).ThenBy(m => m.MemberId)
                .Select(m => (Guid?)m.MemberId)
                .FirstOrDefaultAsync(CancellationToken.None);

            var schedules = await db.Schedules
                .Where(s => s.MissionSetId == roomId && s.CreatedBy == memberId)
                .ToListAsync(CancellationToken.None);
            foreach (var schedule in schedules) schedule.CreatedBy = successorId;

            var room = await db.MissionSets
                .FirstOrDefaultAsync(r => r.MissionSetId == roomId, CancellationToken.None);
            // 残りが誰もいなければ null。空のルームに誰かが招待コードで入り直したときは
            // POST /rooms/join がその人を作成者にする
            if (room is not null && room.CreatedBy == memberId) room.CreatedBy = successorId;
            await db.SaveChangesAsync(CancellationToken.None);

            // ⑤ 最後に本人。TokenHash ごと消えるので、発行済みトークンはここで無効になる
            var member = await db.Members.FirstOrDefaultAsync(m => m.MemberId == memberId,
                                                              CancellationToken.None);
            if (member is not null)
            {
                db.Members.Remove(member);
                await db.SaveChangesAsync(CancellationToken.None);
            }

            await tx.CommitAsync(CancellationToken.None);
        });
    }
}
