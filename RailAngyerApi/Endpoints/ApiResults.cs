using RailAngyerApi.Auth;

namespace RailAngyerApi.Endpoints;

/// <summary>エラー応答の形を1か所にまとめる（11_API設計.md §6）</summary>
public static class ApiResults
{
    public static IResult BadRequest(string error, string message, object? detail = null) =>
        Results.Json(new ApiError(error, message, detail), statusCode: StatusCodes.Status400BadRequest);

    public static IResult Forbidden(string error = "forbidden",
                                    string message = "このルームにはアクセスできません") =>
        Results.Json(new ApiError(error, message), statusCode: StatusCodes.Status403Forbidden);

    public static IResult Conflict(string error, string message, object? detail = null) =>
        Results.Json(new ApiError(error, message, detail), statusCode: StatusCodes.Status409Conflict);

    public static IResult NotFound(string error, string message) =>
        Results.Json(new ApiError(error, message), statusCode: StatusCodes.Status404NotFound);

    /// <summary>Blobの接続設定が無い状態。設定ミスであり、クライアントの誤りではない</summary>
    public static IResult StorageUnavailable() =>
        Results.Json(new ApiError("storage_unavailable", "写真の保管先が設定されていません"),
                     statusCode: StatusCodes.Status503ServiceUnavailable);
}
