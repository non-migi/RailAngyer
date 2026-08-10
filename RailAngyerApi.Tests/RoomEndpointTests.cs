using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using RailAngyerApi.Auth;
using RailAngyerApi.Endpoints;

namespace RailAngyerApi.Tests;

/// <summary>
/// 参加まわりの検証。とくに <b>なりすましを防げているか</b>（11_API設計.md §2 / G-5）。
/// </summary>
public class RoomEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    private HttpClient Client => factory.CreateClient();

    // MARK: - マスタ

    [Fact]
    public async Task 駅マスタを取得できる()
    {
        var courses = await Client.GetFromJsonAsync<List<CourseDto>>("/courses");

        Assert.NotNull(courses);
        var nanboku = Assert.Single(courses);
        Assert.Equal("南北線", nanboku.Name);
        Assert.Equal(16, nanboku.Stations.Count);
        Assert.Equal("麻生", nanboku.Stations.First().Name);
        Assert.Equal("真駒内", nanboku.Stations.Last().Name);
    }

    [Fact]
    public async Task ヘルスチェックは認証なしで応答する()
    {
        var response = await Client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // MARK: - ルーム作成と参加

    [Fact]
    public async Task ルームを作るとトークンと招待コードが返る()
    {
        var created = await CreateRoomAsync("夏の南北線ツアー", "のん");

        Assert.NotEqual(Guid.Empty, created.RoomId);
        Assert.NotEmpty(created.InviteCode);
        Assert.NotEmpty(created.Token);
        Assert.True(created.Token.Length >= 40, "トークンが短すぎる");
    }

    [Fact]
    public async Task 招待コードで参加できる()
    {
        var host = await CreateRoomAsync("ツアー", "のん");

        var joined = await JoinAsync(host.InviteCode, "ケンタ");

        Assert.Equal(host.RoomId, joined.RoomId);
        Assert.NotEqual(host.MemberId, joined.MemberId);
        Assert.NotEqual(host.Token, joined.Token);
    }

    [Fact]
    public async Task 同じ表示名では参加できない()
    {
        var host = await CreateRoomAsync("ツアー", "のん");

        var response = await Client.PostAsJsonAsync("/rooms/join",
            new JoinRoomRequest(host.InviteCode, "のん"));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task 招待コードが違えば参加できない()
    {
        var response = await Client.PostAsJsonAsync("/rooms/join",
            new JoinRoomRequest("ZZZZZZ", "だれか"));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // MARK: - 認証（G-5 なりすまし対策）

    [Fact]
    public async Task トークンが無ければルームを読めない()
    {
        var host = await CreateRoomAsync("ツアー", "のん");

        var response = await Client.GetAsync($"/rooms/{host.RoomId}");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task 出鱈目なトークンでは読めない()
    {
        var host = await CreateRoomAsync("ツアー", "のん");

        var client = Client;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "でたらめ");
        var response = await client.GetAsync($"/rooms/{host.RoomId}");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task 他人のルームは読めない()
    {
        var roomA = await CreateRoomAsync("Aのツアー", "のん");
        var roomB = await CreateRoomAsync("Bのツアー", "べつのひと");

        // A のトークンで B のルームを覗こうとする
        var client = Authorized(roomA.Token);
        var response = await client.GetAsync($"/rooms/{roomB.RoomId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task 自分のルームはメンバー一覧まで読める()
    {
        var host = await CreateRoomAsync("ツアー", "のん");
        await JoinAsync(host.InviteCode, "ケンタ");

        var room = await Authorized(host.Token).GetFromJsonAsync<RoomDto>($"/rooms/{host.RoomId}");

        Assert.NotNull(room);
        Assert.Equal("ツアー", room.Name);
        Assert.Equal(2, room.Members.Count);
        Assert.Contains(room.Members, m => m.DisplayName == "ケンタ");
    }

    // MARK: - 設定の変更

    [Fact]
    public async Task 区間と最大出目を変更できる()
    {
        var host = await CreateRoomAsync("ツアー", "のん");

        var response = await Authorized(host.Token)
            .PatchAsJsonAsync($"/rooms/{host.RoomId}", new UpdateRoomRequest(6, 11, 3));

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        var room = await Authorized(host.Token).GetFromJsonAsync<RoomDto>($"/rooms/{host.RoomId}");
        Assert.Equal(6, room!.StartStationId);
        Assert.Equal(11, room.GoalStationId);
        Assert.Equal(3, room.DiceMax);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(10)]
    public async Task 範囲外の最大出目は拒否される(int diceMax)
    {
        var host = await CreateRoomAsync("ツアー", "のん");

        var response = await Authorized(host.Token)
            .PatchAsJsonAsync($"/rooms/{host.RoomId}", new UpdateRoomRequest(null, null, diceMax));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task コースにない駅へは変更できない()
    {
        var host = await CreateRoomAsync("ツアー", "のん");

        // 南北線に 999 番の駅は無い。DBのCHECKでは表現できないので、ここで弾く（06_schema.sql）
        var response = await Authorized(host.Token)
            .PatchAsJsonAsync($"/rooms/{host.RoomId}", new UpdateRoomRequest(999, null, null));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ApiError>();
        Assert.Equal("invalid_range", error!.Error);

        var room = await Authorized(host.Token).GetFromJsonAsync<RoomDto>($"/rooms/{host.RoomId}");
        Assert.Equal(1, room!.StartStationId);
    }

    [Fact]
    public async Task スタートとゴールが同じ駅では作れない()
    {
        var response = await Client.PostAsJsonAsync("/rooms",
            new CreateRoomRequest(1, "だめなツアー", 5, 5, 6, "のん"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // MARK: - 補助

    private HttpClient Authorized(string token)
    {
        var client = Client;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private async Task<JoinedRoomDto> CreateRoomAsync(string name, string displayName)
    {
        var response = await Client.PostAsJsonAsync("/rooms",
            new CreateRoomRequest(1, name, 1, 16, 6, displayName));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JoinedRoomDto>())!;
    }

    private async Task<JoinedRoomDto> JoinAsync(string inviteCode, string displayName)
    {
        var response = await Client.PostAsJsonAsync("/rooms/join",
            new JoinRoomRequest(inviteCode, displayName));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JoinedRoomDto>())!;
    }
}
