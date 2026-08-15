using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;
using RailAngyerApi.Endpoints;
using RailAngyerApi.Storage;

var builder = WebApplication.CreateBuilder(args);

// 接続文字列はリポジトリに置かない。
// ローカルは user-secrets、App Service ではアプリケーション設定から読む。
var connectionString = builder.Configuration.GetConnectionString("RailAngyer");
var storageConnectionString = builder.Configuration.GetConnectionString("Storage");

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

// 写真の保管先。設定が無くても起動はする（写真のエンドポイントだけ 503 になる）
builder.Services.AddSingleton<IPhotoStorage>(_ =>
    string.IsNullOrWhiteSpace(storageConnectionString)
        ? new UnconfiguredPhotoStorage()
        : new BlobPhotoStorage(storageConnectionString,
                               builder.Configuration["Storage:PhotoContainer"] ?? "photos"));

var app = builder.Build();

// 例外がそのまま500になると、本文が空でクライアントが理由を出し分けられない。
// とくに存在しない駅IDなどのFK違反はクライアントの誤りなので 400 に落とす（§6）
app.UseExceptionHandler(handler => handler.Run(async context =>
{
    var ex = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    var (status, error, message) = ex is DbUpdateException
        ? (StatusCodes.Status400BadRequest, "invalid_reference", "存在しないデータを参照しています")
        : (StatusCodes.Status500InternalServerError, "server_error", "サーバー側で問題が起きました");

    context.Response.StatusCode = status;
    await context.Response.WriteAsJsonAsync(new ApiError(error, message));
}));

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
app.MapMemberEndpoints();
app.MapMissionEndpoints();
app.MapProgressEndpoints();
app.MapPhotoEndpoints();
app.MapScheduleEndpoints();

app.Run();

/// <summary>テストから参照するため</summary>
public partial class Program;
