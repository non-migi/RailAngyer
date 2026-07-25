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
}
