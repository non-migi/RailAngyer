using RailAngyerApi.Storage;

namespace RailAngyerApi.Tests;

/// <summary>
/// Blob の代わり。<b>Azureに触らずに写真の流れを検証する</b>ため、
/// 「SASを出したパス＝端末が上げ終えたBlob」と見なして集合で持つ。
///
/// <para>SASの署名そのものは Azure SDK の責務なので、ここでは検証しない。
/// APIの責務は<b>正しいパスに、正しい権限と期限で出すこと</b>と、
/// <b>消すときに実体も落とすこと</b>で、それはこの偽物でも確かめられる。</para>
/// </summary>
public sealed class FakePhotoStorage : IPhotoStorage
{
    private readonly Lock _gate = new();
    private readonly HashSet<string> _blobs = [];

    public bool IsConfigured => true;

    /// <summary>いま「存在している」Blobのパス</summary>
    public IReadOnlyCollection<string> Blobs
    {
        get { lock (_gate) return [.. _blobs]; }
    }

    public Uri CreateUploadUrl(string blobPath, TimeSpan lifetime)
    {
        lock (_gate) _blobs.Add(blobPath);
        return new Uri($"https://fake.local/photos/{blobPath}?sig=write&ttl={lifetime.TotalMinutes}");
    }

    public Uri CreateReadUrl(string blobPath, TimeSpan lifetime) =>
        new($"https://fake.local/photos/{blobPath}?sig=read&ttl={lifetime.TotalMinutes}");

    public Task DeleteAsync(string blobPath, CancellationToken ct)
    {
        lock (_gate) _blobs.Remove(blobPath);
        return Task.CompletedTask;
    }

    public Task DeletePrefixAsync(string prefix, CancellationToken ct)
    {
        lock (_gate) _blobs.RemoveWhere(b => b.StartsWith(prefix, StringComparison.Ordinal));
        return Task.CompletedTask;
    }
}
