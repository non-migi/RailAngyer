using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;

namespace RailAngyerApi.Storage;

/// <summary>
/// Azure Blob Storage の実装。
///
/// <para>SASは<b>1つのBlobだけ・短命・必要な権限だけ</b>で発行する。
/// コンテナ単位や長期のSASを配ると、1枚の写真を上げる権限が
/// 「ルーム全体を読み書きできる鍵」になってしまう。</para>
/// </summary>
public sealed class BlobPhotoStorage : IPhotoStorage
{
    private readonly BlobContainerClient _container;

    public BlobPhotoStorage(string connectionString, string containerName)
    {
        _container = new BlobContainerClient(connectionString, containerName);
    }

    public bool IsConfigured => true;

    public Uri CreateUploadUrl(string blobPath, TimeSpan lifetime) =>
        // Create だけでは上書き時に足りず、Write だけでは新規作成ができない
        Sas(blobPath, BlobSasPermissions.Create | BlobSasPermissions.Write, lifetime);

    public Uri CreateReadUrl(string blobPath, TimeSpan lifetime) =>
        Sas(blobPath, BlobSasPermissions.Read, lifetime);

    public async Task DeleteAsync(string blobPath, CancellationToken ct) =>
        await _container.GetBlobClient(blobPath).DeleteIfExistsAsync(cancellationToken: ct);

    public async Task DeletePrefixAsync(string prefix, CancellationToken ct)
    {
        await foreach (var blob in _container.GetBlobsAsync(
                           BlobTraits.None, BlobStates.None, prefix, ct))
        {
            await _container.GetBlobClient(blob.Name).DeleteIfExistsAsync(cancellationToken: ct);
        }
    }

    private Uri Sas(string blobPath, BlobSasPermissions permissions, TimeSpan lifetime)
    {
        var blob = _container.GetBlobClient(blobPath);

        // アカウントキーでの署名が使えない構成（マネージドID運用に切り替えた後）では
        // ユーザー委任SASが要る。切り替えるときはここを直す
        if (!blob.CanGenerateSasUri)
        {
            throw new InvalidOperationException(
                "SASを発行できません（アカウントキーを持たない接続です）");
        }

        var builder = new BlobSasBuilder
        {
            BlobContainerName = _container.Name,
            BlobName = blobPath,
            Resource = "b",                                  // 単一Blob限定
            // 端末の時計が少し進んでいても弾かれないよう、開始を5分さかのぼらせる
            StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
            ExpiresOn = DateTimeOffset.UtcNow.Add(lifetime)
        };
        builder.SetPermissions(permissions);

        return blob.GenerateSasUri(builder);
    }
}
