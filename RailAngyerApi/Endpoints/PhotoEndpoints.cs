using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;
using RailAngyerApi.Storage;

namespace RailAngyerApi.Endpoints;

/// <summary>
/// 写真（11_API設計.md §5 / G-6）。
///
/// <para><b>実体はAPIを通らない。</b>手順は
/// ①SASをもらう → ②端末がBlobへ直接PUT → ③メタを登録、の3段。
/// ②で終わってしまうと<b>Blobだけが残る</b>ので、掃除の対象になる。</para>
/// </summary>
public static class PhotoEndpoints
{
    /// <summary>アップロード用SASの寿命。撮って上げるだけなので短くてよい</summary>
    private static readonly TimeSpan UploadLifetime = TimeSpan.FromMinutes(15);

    /// <summary>表示用SASの寿命。一覧を開いている間もつ長さがあればよい</summary>
    private static readonly TimeSpan ReadLifetime = TimeSpan.FromHours(1);

    public static void MapPhotoEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/rooms/{roomId:guid}")
                       .AddEndpointFilter<RequireMemberFilter>();

        // --- アップロード用SASの発行 --------------------------------------------

        group.MapPost("/photos/upload-url",
            async (Guid roomId, UploadUrlRequest req, HttpContext http,
                   RailAngyerDbContext db, IPhotoStorage storage, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();
            if (!storage.IsConfigured) return ApiResults.StorageUnavailable();

            if (req.PhotoId == Guid.Empty || req.VisitId == Guid.Empty)
            {
                return ApiResults.BadRequest("invalid_id", "写真IDと訪問IDが必要です");
            }

            // 他ルームの訪問に写真をぶら下げられないよう、訪問の所属を確かめる
            var visitExists = await db.Visits.AnyAsync(
                v => v.VisitId == req.VisitId && v.MissionSetId == roomId, ct);
            if (!visitExists)
            {
                return ApiResults.NotFound("visit_not_found", "その訪問記録がありません");
            }

            // 他人の写真を差し替えるSASを配らない
            var owner = await db.Photos.AsNoTracking()
                .Where(p => p.PhotoId == req.PhotoId)
                .Select(p => (Guid?)p.MemberId)
                .FirstOrDefaultAsync(ct);
            if (owner is { } existingOwner && existingOwner != me.MemberId)
            {
                return ApiResults.Forbidden("not_photographer", "他の人の写真は差し替えられません");
            }

            var path = IPhotoStorage.BlobPath(roomId, req.VisitId, req.PhotoId);
            var url = storage.CreateUploadUrl(path, UploadLifetime);

            return Results.Ok(new UploadUrlDto(req.PhotoId, path, url.ToString(),
                                               DateTime.UtcNow.Add(UploadLifetime)));
        });

        // --- メタの登録（アップロード完了後） -----------------------------------

        group.MapPut("/photos/{photoId:guid}",
            async (Guid roomId, Guid photoId, SavePhotoRequest req, HttpContext http,
                   RailAngyerDbContext db, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var visitExists = await db.Visits.AnyAsync(
                v => v.VisitId == req.VisitId && v.MissionSetId == roomId, ct);
            if (!visitExists)
            {
                return ApiResults.NotFound("visit_not_found", "その訪問記録がありません");
            }

            var photo = await db.Photos.FirstOrDefaultAsync(p => p.PhotoId == photoId, ct);
            if (photo is not null && photo.MemberId != me.MemberId)
            {
                return ApiResults.Forbidden("not_photographer", "他の人の写真は変更できません");
            }

            if (photo is null)
            {
                db.Photos.Add(new Photo
                {
                    PhotoId = photoId,            // 冪等にするためクライアント生成のIDを使う
                    VisitId = req.VisitId,
                    MemberId = me.MemberId,
                    // 保存するのは<b>コンテナ内のパス</b>。SASは都度発行するので、
                    // ここに署名付きURLを入れてはいけない（期限が切れて使えなくなる）
                    BlobUrl = IPhotoStorage.BlobPath(roomId, req.VisitId, photoId),
                    TakenAt = req.TakenAt ?? DateTime.UtcNow
                });
                await db.SaveChangesAsync(ct);
            }
            // 既にあれば何もしない。再送で撮影時刻が動かないようにする

            return Results.NoContent();
        });

        // --- 一覧（読み取り用SAS付き） ------------------------------------------

        group.MapGet("/photos", async (Guid roomId, Guid? visitId, HttpContext http,
                                       RailAngyerDbContext db, IPhotoStorage storage,
                                       CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();
            if (!storage.IsConfigured) return ApiResults.StorageUnavailable();

            var rows = await db.Photos.AsNoTracking()
                .Where(p => p.Visit!.MissionSetId == roomId)
                .Where(p => visitId == null || p.VisitId == visitId)
                .OrderBy(p => p.TakenAt)
                .Select(p => new
                {
                    p.PhotoId, p.VisitId, p.MemberId, p.BlobUrl, p.TakenAt,
                    p.Visit!.StationId,
                    TakenByName = p.Member!.DisplayName
                })
                .ToListAsync(ct);

            // 写真そのものはチームで共有する（撮影者以外にも見せる）
            var photos = rows.Select(p => new PhotoDto(
                p.PhotoId, p.VisitId, p.StationId, p.MemberId, p.TakenByName, p.TakenAt,
                storage.CreateReadUrl(p.BlobUrl, ReadLifetime).ToString(),
                DateTime.UtcNow.Add(ReadLifetime))).ToList();

            return Results.Ok(photos);
        });

        // --- 削除（撮影者本人のみ） ----------------------------------------------

        group.MapDelete("/photos/{photoId:guid}",
            async (Guid roomId, Guid photoId, HttpContext http,
                   RailAngyerDbContext db, IPhotoStorage storage, CancellationToken ct) =>
        {
            var me = http.Member();
            if (me.MissionSetId != roomId) return ApiResults.Forbidden();

            var photo = await db.Photos.Include(p => p.Visit)
                .FirstOrDefaultAsync(p => p.PhotoId == photoId, ct);
            if (photo is null) return Results.NoContent();                 // 冪等
            if (photo.Visit!.MissionSetId != roomId) return ApiResults.Forbidden();
            if (photo.MemberId != me.MemberId)
            {
                return ApiResults.Forbidden("not_photographer", "自分が撮った写真だけ消せます");
            }

            // 先にBlobを消す。ここで失敗したら行を残す方がよい
            // （行が無いBlobは孤児になって誰も掃除できないが、逆は次の削除でやり直せる）
            if (storage.IsConfigured) await storage.DeleteAsync(photo.BlobUrl, ct);

            db.Photos.Remove(photo);
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        });
    }
}

public record UploadUrlRequest(Guid PhotoId, Guid VisitId);
public record SavePhotoRequest(Guid VisitId, DateTime? TakenAt);

public record UploadUrlDto(Guid PhotoId, string BlobPath, string UploadUrl, DateTime ExpiresAt);
public record PhotoDto(Guid PhotoId, Guid VisitId, int StationId, Guid TakenBy, string TakenByName,
                       DateTime TakenAt, string Url, DateTime UrlExpiresAt);
