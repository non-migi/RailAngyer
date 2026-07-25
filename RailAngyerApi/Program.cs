using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;
using RailAngyerApi.Endpoints;

var builder = WebApplication.CreateBuilder(args);

// 接続文字列はリポジトリに置かない。
// ローカルは user-secrets、App Service ではアプリケーション設定から読む。
var connectionString = builder.Configuration.GetConnectionString("RailAngyer");

builder.Services.AddDbContext<RailAngyerDbContext>(options =>
{
    // 接続先が無くても起動はする（/health だけ応答する）
    if (string.IsNullOrWhiteSpace(connectionString)) return;

    options.UseSqlServer(connectionString, sql =>
    {
        // サーバーレスDBは自動一時停止から復帰するまで応答しない。
        // 最初の1回で諦めず、少し待って再試行する（11_API設計.md §1）
        sql.EnableRetryOnFailure(maxRetryCount: 5,
                                 maxRetryDelay: TimeSpan.FromSeconds(20),
                                 errorNumbersToAdd: null);
        sql.CommandTimeout(60);
    });
});

builder.Services.AddScoped<MemberAuthenticator>();
builder.Services.AddScoped<RequireMemberFilter>();

var app = builder.Build();

// アプリとDBを起こすためだけの応答。
// 両方が寝ていると最初のリクエストに1分近くかかるため、クライアントは起動時にこれを投げておく
app.MapGet("/health", () => Results.Ok(new { status = "ok", at = DateTime.UtcNow }));

app.MapGet("/health/db", async (RailAngyerDbContext db, CancellationToken ct) =>
{
    try
    {
        var stations = await db.Stations.CountAsync(ct);
        return Results.Ok(new { status = "ok", stations });
    }
    catch (Exception ex)
    {
        // 復帰中は失敗する。クライアントはこれを見て待てばよい
        return Results.Json(new ApiError("db_unavailable", ex.Message),
                            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

app.MapRoomEndpoints();

app.Run();

/// <summary>テストから参照するため</summary>
public partial class Program;
