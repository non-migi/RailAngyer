using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RailAngyerApi.Auth;
using RailAngyerApi.Data;
using RailAngyerApi.Endpoints;

namespace RailAngyerApi.Tests;

/// <summary>
/// 退室と除名。
///
/// <para><b>消えるのは本人のぶんだけ</b>で、ターンと訪問はルーム共有の進行記録として残ること。
/// そして<b>他人を外せるのはルームを作った人だけ</b>であること。</para>
/// </summary>
public class MemberEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    // MARK: - 退室

    [Fact]
    public async Task 退室すると自分の写真とお題と出欠とメンバー行が消える()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        // 予定は作成者（のん）のもの。ケンタは出欠だけ入れる
        var scheduleId = Guid.NewGuid();
        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", new DateTime(2026, 9, 1, 9, 0, 0, DateTimeKind.Utc), null));
        var attendance = await guestClient.PutAsJsonAsync(
            $"/rooms/{room.RoomId}/schedules/{scheduleId}/attendance", new SaveAttendanceRequest(1));
        Assert.Equal(HttpStatusCode.NoContent, attendance.StatusCode);

        await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(5, "ケンタのお題", 0, null, null));
        var visitId = await ArriveAsync(guestClient, room.RoomId, stationId: 4);
        var photoId = await UploadAsync(guestClient, room.RoomId, visitId);
        var blobPath = $"{room.RoomId}/{visitId}/{photoId}.jpg";
        Assert.Contains(blobPath, factory.Photos.Blobs);

        var leave = await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");
        Assert.Equal(HttpStatusCode.NoContent, leave.StatusCode);

        // 残った人から見て、ケンタのぶんが消えている
        var photos = await hostClient.GetFromJsonAsync<List<PhotoDto>>($"/rooms/{room.RoomId}/photos");
        Assert.Empty(photos!);
        Assert.DoesNotContain(blobPath, factory.Photos.Blobs);     // Blobの実体も残さない

        var missions = await hostClient.GetFromJsonAsync<List<MissionDto>>($"/rooms/{room.RoomId}/missions");
        Assert.Empty(missions!);

        var schedules = await hostClient.GetFromJsonAsync<List<ScheduleDto>>($"/rooms/{room.RoomId}/schedules");
        Assert.Empty(Assert.Single(schedules!).Attendees);

        var after = await hostClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        Assert.DoesNotContain(after!.Members, m => m.MemberId == guest.MemberId);
        Assert.Equal("のん", Assert.Single(after.Members).DisplayName);
    }

    [Fact]
    public async Task 退室したトークンはもう使えない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");

        // TokenHash ごと消えるので、本人を引けなくなる
        var response = await guestClient.GetAsync($"/rooms/{room.RoomId}/state");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);

        var again = await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");
        Assert.Equal(HttpStatusCode.Unauthorized, again.StatusCode);

        // 残った人は普通に使える
        Assert.Equal(HttpStatusCode.OK,
            (await hostClient.GetAsync($"/rooms/{room.RoomId}/state")).StatusCode);
    }

    [Fact]
    public async Task 退室してもターンと訪問は残り_引いていたお題の参照だけ外れる()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        var missionId = Guid.NewGuid();
        await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{missionId}",
            new SaveMissionRequest(4, "ケンタのお題", 0, null, null));

        // 1 → 4 へ進んで着地し、ケンタのお題を引いて終わる
        var turnId = Guid.NewGuid();
        await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));
        await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/visits/{Guid.NewGuid()}",
            new SaveVisitRequest(turnId, 4, DateTime.UtcNow, 2));
        await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, null, DateTime.UtcNow, missionId, true, 0, 4, DateTime.UtcNow));

        var before = await hostClient.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");
        Assert.Equal(missionId, Assert.Single(before!.CompletedTurns!).SelectedMissionId);

        await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");

        var state = await hostClient.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");

        // **ターンと訪問はみんなの進行記録。**書いた人が抜けても残す
        var turn = Assert.Single(state!.CompletedTurns!);
        Assert.Equal(turnId, turn.TurnId);
        Assert.Null(turn.SelectedMissionId);          // 参照だけ外れる
        Assert.True(turn.MissionDone);
        Assert.Equal(1, state.CompletedTurnCount);
        Assert.Equal(4, state.CurrentStationId);      // 現在位置も動かない
        Assert.Single(state.Visits);
    }

    [Fact]
    public async Task 他ルームを指して退室はできない()
    {
        var (client, room) = await SetUpAsync("のん");
        var (otherClient, otherRoom) = await SetUpAsync("ケンタ");

        var response = await client.DeleteAsync($"/rooms/{otherRoom.RoomId}/members/me");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        // 巻き添えで自分が抜けてもいないし、隣のルームも無傷
        Assert.Single((await client.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}"))!.Members);
        Assert.Single((await otherClient.GetFromJsonAsync<RoomDto>($"/rooms/{otherRoom.RoomId}"))!.Members);
    }

    [Fact]
    public async Task トークンが無ければ退室もできない()
    {
        var (_, room) = await SetUpAsync("のん");

        var response = await factory.CreateClient().DeleteAsync($"/rooms/{room.RoomId}/members/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // MARK: - 除名

    [Fact]
    public async Task ルームを作った人はメンバーを外せる()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);
        await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/missions/{Guid.NewGuid()}",
            new SaveMissionRequest(5, "ケンタのお題", 0, null, null));

        var kick = await hostClient.DeleteAsync($"/rooms/{room.RoomId}/members/{guest.MemberId}");

        Assert.Equal(HttpStatusCode.NoContent, kick.StatusCode);
        var after = await hostClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        Assert.Single(after!.Members);
        Assert.Empty((await hostClient.GetFromJsonAsync<List<MissionDto>>(
            $"/rooms/{room.RoomId}/missions"))!);
        // 外された人のトークンも無効になる
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await guestClient.GetAsync($"/rooms/{room.RoomId}/state")).StatusCode);
    }

    [Fact]
    public async Task 作った人でなければ他人を外せない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var host = await hostClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        var response = await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/{room.MemberId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ApiError>();
        Assert.Equal("not_owner", error!.Error);

        // 作成者は消えていない
        var after = await hostClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        Assert.Equal(2, after!.Members.Count);
        Assert.Equal(host!.CreatedBy, after.CreatedBy);
    }

    [Fact]
    public async Task いないメンバーを外そうとすると404()
    {
        var (hostClient, room) = await SetUpAsync("のん");

        var response = await hostClient.DeleteAsync($"/rooms/{room.RoomId}/members/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ApiError>();
        Assert.Equal("member_not_found", error!.Error);
    }

    [Fact]
    public async Task 他ルームのメンバーは外せない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var (otherClient, otherRoom) = await SetUpAsync("ケンタ");
        var otherGuest = await JoinAsync(otherRoom.InviteCode, "みか");

        // ① 自分のルーム宛てに、隣のルームのメンバーIDを混ぜる
        var response = await hostClient.DeleteAsync($"/rooms/{room.RoomId}/members/{otherGuest.MemberId}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ApiError>();
        Assert.Equal("member_not_found", error!.Error);

        // ② 隣のルーム宛てに投げても、そのルームのメンバーではないので通らない
        var crossRoom = await hostClient.DeleteAsync($"/rooms/{otherRoom.RoomId}/members/{otherGuest.MemberId}");
        Assert.Equal(HttpStatusCode.Forbidden, crossRoom.StatusCode);

        var after = await otherClient.GetFromJsonAsync<RoomDto>($"/rooms/{otherRoom.RoomId}");
        Assert.Equal(2, after!.Members.Count);
        Assert.Contains(after.Members, m => m.MemberId == otherGuest.MemberId);
    }

    [Fact]
    public async Task 自分のIDを指定したときは作った人でなくても抜けられる()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        var response = await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/{guest.MemberId}");

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        var after = await hostClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        Assert.Single(after!.Members);
    }

    // MARK: - 作った人が抜けたあと（引き継ぎ）

    [Fact]
    public async Task 作った人が抜けると残った最古参が作成者を引き継ぐ()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");        // 先に入った人
        var third = await JoinAsync(room.InviteCode, "みか");          // あとから入った人
        var guestClient = Authorized(guest.Token);
        var thirdClient = Authorized(third.Token);

        var leave = await hostClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");
        Assert.Equal(HttpStatusCode.NoContent, leave.StatusCode);

        // **除名する手立てを絶やさない。**残った人のうち先に入った人へ引き継ぐ
        var after = await guestClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        Assert.Equal(guest.MemberId, after!.CreatedBy);
        Assert.Equal(2, after.Members.Count);

        // 引き継がなかった人は、これまで通り外せない
        var denied = await thirdClient.DeleteAsync($"/rooms/{room.RoomId}/members/{guest.MemberId}");
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        Assert.Equal("not_owner", (await denied.Content.ReadFromJsonAsync<ApiError>())!.Error);

        // 引き継いだ人は外せる
        var kick = await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/{third.MemberId}");
        Assert.Equal(HttpStatusCode.NoContent, kick.StatusCode);
        Assert.Single((await guestClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}"))!.Members);
    }

    [Fact]
    public async Task 入った時刻が同じなら引き継ぎ先はメンバーIDで一意に決まる()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var third = await JoinAsync(room.InviteCode, "みか");

        // 同じ瞬間に入ったことにする。JoinedAt だけでは順序が決まらない状況を作る
        await SetJoinedAtAsync(new DateTime(2026, 8, 15, 12, 0, 0, DateTimeKind.Utc),
                               guest.MemberId, third.MemberId);

        await hostClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");

        // どちらが勝つかは Guid の並び順（SQLite は文字列、SQL Server はバイト列）で変わるので固定しない。
        // 大事なのは**必ずどちらか1人に決まること**——null のままだと誰も除名できないルームになる
        var after = await Authorized(guest.Token).GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        Assert.NotNull(after!.CreatedBy);
        Assert.Contains(after.CreatedBy!.Value, new[] { guest.MemberId, third.MemberId });

        // 引き継いだ人は実際に外せる（肩書きだけでなく権限が伴っている）
        var owner = after.CreatedBy.Value == guest.MemberId ? guest : third;
        var other = after.CreatedBy.Value == guest.MemberId ? third : guest;
        var kick = await Authorized(owner.Token).DeleteAsync(
            $"/rooms/{room.RoomId}/members/{other.MemberId}");
        Assert.Equal(HttpStatusCode.NoContent, kick.StatusCode);
    }

    [Fact]
    public async Task 作成者が続けて抜けても引き継ぎは連鎖する()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);

        // ① 作成者が抜ける → 残った1人へ
        await hostClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");
        Assert.Equal(guest.MemberId,
            (await guestClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}"))!.CreatedBy);

        // ② その1人も抜ける → 引き継ぎ先がいないので null に戻る
        await guestClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");

        // ③ 空いたルームへ入り直した人が作成者になる
        var rejoined = await JoinAsync(room.InviteCode, "みか");
        var rejoinedClient = Authorized(rejoined.Token);
        var after = await rejoinedClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}");
        Assert.Equal(rejoined.MemberId, after!.CreatedBy);

        // ④ 作成者になったので、あとから入った人を外せる
        var late = await JoinAsync(room.InviteCode, "たろう");
        Assert.Equal(rejoined.MemberId,                       // 2人目の参加で奪われない
            (await rejoinedClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}"))!.CreatedBy);
        var kick = await rejoinedClient.DeleteAsync($"/rooms/{room.RoomId}/members/{late.MemberId}");
        Assert.Equal(HttpStatusCode.NoContent, kick.StatusCode);
    }

    [Fact]
    public async Task 最後の1人が抜けてもルームと進行記録は残り招待コードで入り直せる()
    {
        var (client, room) = await SetUpAsync("のん");
        var turnId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, DateTime.UtcNow, null, null, null, null, null, null));
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, 4, null, DateTime.UtcNow, null, true, 0, 4, DateTime.UtcNow));

        Assert.Equal(HttpStatusCode.NoContent,
            (await client.DeleteAsync($"/rooms/{room.RoomId}/members/me")).StatusCode);

        // 同じ名前でも入り直せる（Member 行ごと消えているため名前は空く）
        var rejoined = await JoinAsync(room.InviteCode, "のん");
        var again = Authorized(rejoined.Token);
        var state = await again.GetFromJsonAsync<StateDto>($"/rooms/{room.RoomId}/state");

        Assert.Equal(4, state!.CurrentStationId);            // 進行はそのまま
        Assert.Equal(1, state.CompletedTurnCount);
        // 空いたルームに入り直した人が作成者になる（誰も外せないルームを残さない）
        Assert.Equal(rejoined.MemberId,
            (await again.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}"))!.CreatedBy);
    }

    [Fact]
    public async Task 予定を立てた人が抜けると引き継ぎ先が直せるようになる()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var third = await JoinAsync(room.InviteCode, "みか");
        var guestClient = Authorized(guest.Token);
        var thirdClient = Authorized(third.Token);
        var scheduleId = Guid.NewGuid();
        var startAt = new DateTime(2026, 9, 1, 9, 0, 0, DateTimeKind.Utc);
        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", startAt, null));

        await hostClient.DeleteAsync($"/rooms/{room.RoomId}/members/me");

        // 予定そのものは共有物なので残り、立てた人はルームの引き継ぎ先と同じ人になる
        var schedules = await guestClient.GetFromJsonAsync<List<ScheduleDto>>($"/rooms/{room.RoomId}/schedules");
        Assert.Equal(guest.MemberId, Assert.Single(schedules!).CreatedBy);
        Assert.Equal(guest.MemberId,
            (await guestClient.GetFromJsonAsync<RoomDto>($"/rooms/{room.RoomId}"))!.CreatedBy);

        // 引き継がなかった人は、これまで通り直せない
        var denied = await thirdClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("勝手に変える", startAt, null));
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        Assert.Equal("not_owner", (await denied.Content.ReadFromJsonAsync<ApiError>())!.Error);

        // **引き継ぎ先は直せるし消せる。**直せない予定が残り続けることはない
        var edit = await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("行き先を変える", startAt, "大通駅 改札前"));
        Assert.Equal(HttpStatusCode.NoContent, edit.StatusCode);
        var edited = await guestClient.GetFromJsonAsync<List<ScheduleDto>>($"/rooms/{room.RoomId}/schedules");
        Assert.Equal("行き先を変える", Assert.Single(edited!).Title);

        var remove = await guestClient.DeleteAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}");
        Assert.Equal(HttpStatusCode.NoContent, remove.StatusCode);
        Assert.Empty((await guestClient.GetFromJsonAsync<List<ScheduleDto>>(
            $"/rooms/{room.RoomId}/schedules"))!);
    }

    // MARK: - 補助

    private HttpClient Authorized(string token)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

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

    /// <summary>
    /// 参加時刻をそろえる。APIからは「同じ瞬間に入った2人」を作れないので、
    /// 引き継ぎ先の決め方（JoinedAt が並んだときの扱い）を確かめるためだけにDBを直接触る。
    /// </summary>
    private async Task SetJoinedAtAsync(DateTime joinedAt, params Guid[] memberIds)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<RailAngyerDbContext>();
        var members = await db.Members.Where(m => memberIds.Contains(m.MemberId)).ToListAsync();
        Assert.Equal(memberIds.Length, members.Count);
        foreach (var member in members) member.JoinedAt = joinedAt;
        await db.SaveChangesAsync();
    }

    /// <summary>ターンを1つ回して着地の訪問記録を作る（写真はこれにぶら下がる）</summary>
    private static async Task<Guid> ArriveAsync(HttpClient client, Guid roomId, int stationId)
    {
        var turnId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{roomId}/turns/{turnId}",
            new SaveTurnRequest(1, 3, stationId, DateTime.UtcNow, null, null, null, null, null, null));

        var visitId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{roomId}/visits/{visitId}",
            new SaveVisitRequest(turnId, stationId, DateTime.UtcNow, 2));
        return visitId;
    }

    /// <summary>SASをもらう → 端末が上げたことにする → メタ登録</summary>
    private static async Task<Guid> UploadAsync(HttpClient client, Guid roomId, Guid visitId)
    {
        var photoId = Guid.NewGuid();
        var issued = await client.PostAsJsonAsync($"/rooms/{roomId}/photos/upload-url",
            new UploadUrlRequest(photoId, visitId));
        issued.EnsureSuccessStatusCode();

        var saved = await client.PutAsJsonAsync($"/rooms/{roomId}/photos/{photoId}",
            new SavePhotoRequest(visitId, DateTime.UtcNow));
        saved.EnsureSuccessStatusCode();
        return photoId;
    }
}
