using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using RailAngyerApi.Auth;
using RailAngyerApi.Endpoints;

namespace RailAngyerApi.Tests;

/// <summary>
/// ミッションと進行。とくに <b>冪等性</b>（G-7）と <b>お題が漏れないこと</b>。
/// </summary>
public class ProgressEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    // MARK: - ミッション

    [Fact]
    public async Task ミッションを作って読み直せる()
    {
        var (client, room) = await SetUpAsync("のん");
        var missionId = Guid.NewGuid();

        var save = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{missionId}",
            new SaveMissionRequest(4, "駅名標を撮る", 0, null, null));
        Assert.Equal(HttpStatusCode.NoContent, save.StatusCode);

        var missions = await client.GetFromJsonAsync<List<MissionDto>>($"/rooms/{room.RoomId}/missions");
        var mission = Assert.Single(missions!);
        Assert.Equal("駅名標を撮る", mission.Content);
        Assert.Equal(4, mission.StationId);
    }

    [Fact]
    public async Task 同じIDへ二度送っても増えない()
    {
        var (client, room) = await SetUpAsync("のん");
        var missionId = Guid.NewGuid();
        var body = new SaveMissionRequest(4, "駅名標を撮る", 0, null, null);

        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{missionId}", body);
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{missionId}", body);

        var missions = await client.GetFromJsonAsync<List<MissionDto>>($"/rooms/{room.RoomId}/missions");
        Assert.Single(missions!);
    }

    [Fact]
    public async Task 同じ駅に2個目のミッションは作れない()
    {
        var (client, room) = await SetUpAsync("のん");
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "ひとつめ", 0, null, null));

        var second = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "ふたつめ", 0, null, null));

        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Theory]
    [InlineData(0, 3, null)]      // 効果なしなのに駅数がある
    [InlineData(1, null, null)]   // 進むなのに駅数がない
    [InlineData(4, null, null)]   // ジャンプなのに移動先がない
    [InlineData(2, 99, null)]     // 駅数が範囲外
    public async Task 効果の組み合わせが不正なら拒否される(int effectType, int? value, int? stationId)
    {
        var (client, room) = await SetUpAsync("のん");

        var response = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "お題", effectType, value, stationId));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task 他人のお題も既定では一覧に出る()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "のんのお題", 0, null, null));

        var seen = await guestClient.GetFromJsonAsync<List<MissionDto>>($"/rooms/{room.RoomId}/missions");

        var mission = Assert.Single(seen!);
        Assert.Equal("のんのお題", mission.Content);
        Assert.Equal("のん", mission.CreatedByName);
    }

    [Fact]
    public async Task 伏せる設定なら自分のお題しか一覧に出ない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "のんのお題", 0, null, null));

        var seen = await guestClient.GetFromJsonAsync<List<MissionDto>>(
            $"/rooms/{room.RoomId}/missions?includeOthers=false");

        Assert.Empty(seen!);
    }

    [Fact]
    public async Task 準備状況は既定で中身も返し_伏せる設定なら件数だけになる()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "のんのお題", 0, null, null));

        var shared = await guestClient.GetFromJsonAsync<List<MissionSummaryDto>>(
            $"/rooms/{room.RoomId}/missions/summary");
        var row = Assert.Single(shared!);
        Assert.Equal(1, row.Count);
        Assert.Equal("のんのお題", Assert.Single(row.Missions).Content);

        var hidden = await guestClient.GetFromJsonAsync<List<MissionSummaryDto>>(
            $"/rooms/{room.RoomId}/missions/summary?includeContent=false");
        Assert.Equal(1, Assert.Single(hidden!).Count);
        Assert.Empty(Assert.Single(hidden!).Missions);
    }

    [Fact]
    public async Task 着地していない駅のお題は覗けない()
    {
        var (client, room) = await SetUpAsync("のん");
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "秘密のお題", 0, null, null));

        var response = await client.GetAsync($"/rooms/{room.RoomId}/stations/4/missions");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task 着地したらその駅のお題を引ける()
    {
        var (client, room) = await SetUpAsync("のん");
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "秘密のお題", 0, null, null));

        // 1 → 4 へ進み、着地した
        var turnId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, null, DateTime.UtcNow, null, null, null, null, null));

        var missions = await client.GetFromJsonAsync<List<MissionDto>>(
            $"/rooms/{room.RoomId}/stations/4/missions");

        var mission = Assert.Single(missions!);
        Assert.Equal("秘密のお題", mission.Content);
        Assert.Equal("のん", mission.CreatedByName);
    }

    // MARK: - 進行

    [Fact]
    public async Task 初期状態はスタート駅にいる()
    {
        var (client, room) = await SetUpAsync("のん");

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");

        Assert.NotNull(state);
        Assert.Equal(1, state.CurrentStationId);
        Assert.False(state.IsCleared);
        Assert.Null(state.ActiveTurn);
    }

    [Fact]
    public async Task ターンを作るとサーバーが連番を振る()
    {
        var (client, room) = await SetUpAsync("のん");

        var response = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{Guid.NewGuid()}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));

        var saved = await response.Content.ReadFromJsonAsync<SavedTurnDto>();
        Assert.Equal(1, saved!.TurnNo);
    }

    [Fact]
    public async Task 進行中のターンがあるうちは次のターンを作れない()
    {
        var (client, room) = await SetUpAsync("のん");
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{Guid.NewGuid()}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));

        var second = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{Guid.NewGuid()}",
            new SaveTurnRequest(1, 2, 3, DateTime.UtcNow, null, null, null, null, null, null));

        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task 同じターンへ再送しても二重にならない()
    {
        var (client, room) = await SetUpAsync("のん");
        var turnId = Guid.NewGuid();
        var body = new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null);

        var first = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}", body);
        var again = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}", body);

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");
        Assert.NotNull(state!.ActiveTurn);   // 進行中は1つのまま
        Assert.Equal(1, state.ActiveTurn!.TurnNo);
    }

    [Fact]
    public async Task ターンを完了すると現在位置が動く()
    {
        var (client, room) = await SetUpAsync("のん");
        var turnId = Guid.NewGuid();

        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, null, DateTime.UtcNow, null, true, 0, 4, DateTime.UtcNow));

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");

        Assert.Equal(4, state!.CurrentStationId);
        Assert.Null(state.ActiveTurn);
        Assert.Equal(1, state.CompletedTurnCount);
    }

    [Fact]
    public async Task 効果で戻ると現在位置も戻る()
    {
        var (client, room) = await SetUpAsync("のん");
        var turnId = Guid.NewGuid();

        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));
        // 着地は4だが、戻る効果で2で終わる
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, null, DateTime.UtcNow, null, true, 2, 2, DateTime.UtcNow));

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");

        Assert.Equal(2, state!.CurrentStationId);
    }

    [Fact]
    public async Task ゴールに着くとクリアになる()
    {
        var (client, room) = await SetUpAsync("のん");
        var turnId = Guid.NewGuid();

        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 6, 16, DateTime.UtcNow, null, null, null, null, null, null));
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 6, 16, null, DateTime.UtcNow, null, true, 0, 16, DateTime.UtcNow));

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");

        Assert.True(state!.IsCleared);
    }

    [Fact]
    public async Task 同じ駅を再訪しても記録できる()
    {
        var (client, room) = await SetUpAsync("のん");
        var turnId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));

        foreach (var kind in new[] { 1, 3 })
        {
            await client.PutAsJsonAsync($"/rooms/{room.RoomId}/visits/{Guid.NewGuid()}",
                new SaveVisitRequest(turnId, 3, DateTime.UtcNow, kind));
        }

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");
        Assert.Equal(2, state!.Visits.Count(v => v.StationId == 3));
    }

    [Fact]
    public async Task 始点以外の訪問はターンに紐づけないと拒否される()
    {
        var (client, room) = await SetUpAsync("のん");

        var response = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/visits/{Guid.NewGuid()}",
            new SaveVisitRequest(null, 3, DateTime.UtcNow, 1));   // 通り道なのに TurnId が無い

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task 他ルームのターンは更新できない()
    {
        var (client, room) = await SetUpAsync("のん");
        var (otherClient, otherRoom) = await SetUpAsync("ケンタ");
        var turnId = Guid.NewGuid();
        await otherClient.PutAsJsonAsync($"/rooms/{otherRoom.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));

        // 自分のルーム宛てだが、ターンのIDは隣のルームのもの
        var response = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, null, DateTime.UtcNow, null, true, 0, 16, DateTime.UtcNow));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);

        var state = await otherClient.GetFromJsonAsync<StateDto>($"/rooms/{otherRoom.RoomId}/state");
        Assert.NotNull(state!.ActiveTurn);          // 勝手に完了させられていない
        Assert.Equal(1, state.CurrentStationId);
    }

    [Fact]
    public async Task 他ルームのターンを指す訪問は作れない()
    {
        var (client, room) = await SetUpAsync("のん");
        var (otherClient, otherRoom) = await SetUpAsync("ケンタ");
        var otherTurnId = Guid.NewGuid();
        await otherClient.PutAsJsonAsync($"/rooms/{otherRoom.RoomId}/turns/{otherTurnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));

        var response = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/visits/{Guid.NewGuid()}",
            new SaveVisitRequest(otherTurnId, 3, DateTime.UtcNow, 1));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");
        Assert.Empty(state!.Visits);
    }

    [Fact]
    public async Task 存在しない駅を指すターンは400で返る()
    {
        var (client, room) = await SetUpAsync("のん");

        var response = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{Guid.NewGuid()}",
            new SaveTurnRequest(1, 3, 999, DateTime.UtcNow, null, null, null, null, null, null));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ApiError>();
        Assert.Equal("invalid_reference", error!.Error);
    }

    [Fact]
    public async Task 記録をリセットすると進行が消えてミッションは残る()
    {
        var (client, room) = await SetUpAsync("のん");
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(4, "残るお題", 0, null, null));
        var turnId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/visits/{Guid.NewGuid()}",
            new SaveVisitRequest(turnId, 2, DateTime.UtcNow, 1));

        var reset = await client.DeleteAsync($"/rooms/{room.RoomId}/progress");
        Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);

        var state = await client.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");
        Assert.Equal(1, state!.CurrentStationId);
        Assert.Empty(state.Visits);
        Assert.Null(state.ActiveTurn);

        var missions = await client.GetFromJsonAsync<List<MissionDto>>($"/rooms/{room.RoomId}/missions");
        Assert.Single(missions!);
    }

    // MARK: - 補助

    private HttpClient Authorized(string token)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    /// <summary>新しいルームを作り、認証済みのクライアントを返す</summary>
    private async Task<(HttpClient Client, JoinedRoomDto Room)> SetUpAsync(string displayName)
    {
        var response = await factory.CreateClient().PostAsJsonAsync("/rooms",
            new CreateRoomRequest(1, $"ツアー {Guid.NewGuid():N}", 1, 16, 6, displayName));
        response.EnsureSuccessStatusCode();
        var room = (await response.Content.ReadFromJsonAsync<JoinedRoomDto>())!;
        return (Authorized(room.Token), room);
    }

    private async Task<JoinedRoomDto> JoinAsync(string inviteCode, string displayName)
    {
        var response = await factory.CreateClient().PostAsJsonAsync("/rooms/join",
            new JoinRoomRequest(inviteCode, displayName));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JoinedRoomDto>())!;
    }
}
