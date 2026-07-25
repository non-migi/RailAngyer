using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Data;

namespace RailAngyerApi.Auth;

/// <summary>
/// メンバートークンの発行と検証（11_API設計.md §2）。
///
/// <para><b>リクエストに書かれた MemberId は信用しない。</b>
/// 招待コードを知っているだけでは他人になりすませないよう、
/// 参加時に発行したトークンから本人を引く。</para>
/// </summary>
public static class MemberTokens
{
    /// <summary>32バイトの乱数を Base64URL で表す（43文字）</summary>
    public static string Generate()
    {
        Span<byte> bytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(bytes);
        return Base64UrlEncode(bytes);
    }

    /// <summary>平文は保存しない。ハッシュだけをDBに置く</summary>
    public static byte[] Hash(string token) =>
        SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token));

    /// <summary>紛らわしい文字（0/O、1/I/L）を避けた招待コード</summary>
    public static string GenerateInviteCode(int length = 6)
    {
        const string alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
        Span<char> chars = stackalloc char[length];
        for (var i = 0; i < length; i++)
        {
            chars[i] = alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
        }
        return new string(chars);
    }

    private static string Base64UrlEncode(ReadOnlySpan<byte> bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}

/// <summary>認証済みの呼び出し元</summary>
public record CurrentMember(Guid MemberId, Guid MissionSetId, string DisplayName);

public class MemberAuthenticator(RailAngyerDbContext db)
{
    /// <summary>
    /// Authorization ヘッダからメンバーを引く。見つからなければ null。
    /// </summary>
    public async Task<CurrentMember?> ResolveAsync(HttpContext context, CancellationToken ct = default)
    {
        var header = context.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) return null;

        var token = header["Bearer ".Length..].Trim();
        if (token.Length == 0) return null;

        var hash = MemberTokens.Hash(token);
        var member = await db.Members
            .AsNoTracking()
            .FirstOrDefaultAsync(m => m.TokenHash == hash, ct);

        return member is null
            ? null
            : new CurrentMember(member.MemberId, member.MissionSetId, member.DisplayName);
    }
}

/// <summary>
/// 認証が要るエンドポイントに付けるフィルタ。
/// 通れば <see cref="CurrentMember"/> を引数として受け取れる。
/// </summary>
public class RequireMemberFilter(MemberAuthenticator authenticator) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context,
                                                EndpointFilterDelegate next)
    {
        var member = await authenticator.ResolveAsync(context.HttpContext);
        if (member is null)
        {
            return Results.Json(
                new ApiError("unauthorized", "参加し直してください"),
                statusCode: StatusCodes.Status401Unauthorized);
        }
        context.HttpContext.Items[nameof(CurrentMember)] = member;
        return await next(context);
    }
}

public static class HttpContextExtensions
{
    public static CurrentMember Member(this HttpContext context) =>
        (CurrentMember)context.Items[nameof(CurrentMember)]!;
}

/// <summary>エラーの形（11_API設計.md §6）</summary>
public record ApiError(string Error, string Message, object? Detail = null);
