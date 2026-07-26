namespace RailAngyerApi.Storage;

/// <summary>
/// 写真のBlob操作。
///
/// <para><b>写真の実体はAPIを通さない</b>（AP-04 / G-6）。
/// F1 の帯域とCPUを転送に使うと無料枠をすぐ食うため、
/// APIは<b>期限付きのSAS URLを発行するだけ</b>にして、端末とBlobを直接つなぐ。</para>
///
/// <para>テストではこれを差し替えるので、Azureに触らずに検証できる。</para>
/// </summary>
public interface IPhotoStorage
{
    /// <summary>設定が無ければ false。写真関連のエンドポイントは 503 を返す</summary>
    bool IsConfigured { get; }

    /// <summary><c>{roomId}/{visitId}/{photoId}.jpg</c>（11_API設計.md §5 のコンテナ構成）</summary>
    static string BlobPath(Guid roomId, Guid visitId, Guid photoId) =>
        $"{roomId}/{visitId}/{photoId}.jpg";

    /// <summary>ルーム単位のプレフィックス。ルームごと消すときに使う</summary>
    static string RoomPrefix(Guid roomId) => $"{roomId}/";

    /// <summary>書き込み専用・単一Blob限定のSAS</summary>
    Uri CreateUploadUrl(string blobPath, TimeSpan lifetime);

    /// <summary>読み取り専用のSAS。URLが漏れても期限で切れる</summary>
    Uri CreateReadUrl(string blobPath, TimeSpan lifetime);

    Task DeleteAsync(string blobPath, CancellationToken ct);

    /// <summary>プレフィックス配下をまとめて消す</summary>
    Task DeletePrefixAsync(string prefix, CancellationToken ct);
}

/// <summary>接続文字列が無いときの実装。起動は妨げず、使われた時点で分かるようにする</summary>
public sealed class UnconfiguredPhotoStorage : IPhotoStorage
{
    public bool IsConfigured => false;

    public Uri CreateUploadUrl(string blobPath, TimeSpan lifetime) => throw NotConfigured();
    public Uri CreateReadUrl(string blobPath, TimeSpan lifetime) => throw NotConfigured();
    public Task DeleteAsync(string blobPath, CancellationToken ct) => throw NotConfigured();
    public Task DeletePrefixAsync(string prefix, CancellationToken ct) => throw NotConfigured();

    private static InvalidOperationException NotConfigured() =>
        new("ConnectionStrings:Storage が設定されていません");
}
