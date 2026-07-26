using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using RailAngyerApi.Endpoints;

namespace RailAngyerApi.Tests;

/// <summary>
/// 予定と出欠。<b>立てた人だけが直せる</b>ことと、<b>出欠は自分のぶんだけ</b>変えられること。
/// </summary>
public class ScheduleEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    private static readonly DateTime StartAt = new(2026, 8, 15, 9, 0, 0, DateTimeKind.Utc);

    [Fact]
    public async Task 予定を立てて一覧に出る()
    {
        var (client, room) = await SetUpAsync("のん");
        var scheduleId = Guid.NewGuid();

        var save = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", StartAt, "麻生駅 改札前"));
        Assert.Equal(HttpStatusCode.NoContent, save.StatusCode);

        var schedules = await client.GetFromJsonAsync<List<ScheduleDto>>($"/rooms/{room.RoomId}/schedules");

        var schedule = Assert.Single(schedules!);
        Assert.Equal("南北線を歩く", schedule.Title);
        Assert.Equal("麻生駅 改札前", schedule.MeetPlace);
    }

    [Fact]
    public async Task 同じIDへ二度送っても増えない()
    {
        var (client, room) = await SetUpAsync("のん");
        var scheduleId = Guid.NewGuid();
        var body = new SaveScheduleRequest("南北線を歩く", StartAt, null);

        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}", body);
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}", body);

        var schedules = await client.GetFromJsonAsync<List<ScheduleDto>>($"/rooms/{room.RoomId}/schedules");
        Assert.Single(schedules!);
    }

    [Fact]
    public async Task 名前が空なら拒否される()
    {
        var (client, room) = await SetUpAsync("のん");

        var response = await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{Guid.NewGuid()}",
            new SaveScheduleRequest("   ", StartAt, null));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task 立てた人以外は変更できない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);
        var scheduleId = Guid.NewGuid();
        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", StartAt, null));

        var response = await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("勝手に書き換え", StartAt, null));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task 立てた人以外は削除できない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var scheduleId = Guid.NewGuid();
        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", StartAt, null));

        var response = await Authorized(guest.Token)
            .DeleteAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task 出欠を答えると一覧に反映される()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);
        var scheduleId = Guid.NewGuid();
        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", StartAt, null));

        await hostClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}/attendance",
            new SaveAttendanceRequest(1));                       // 参加
        await guestClient.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}/attendance",
            new SaveAttendanceRequest(2));                       // 不参加

        var schedules = await hostClient.GetFromJsonAsync<List<ScheduleDto>>(
            $"/rooms/{room.RoomId}/schedules");

        var attendees = Assert.Single(schedules!).Attendees;
        Assert.Equal(2, attendees.Count);
        Assert.Contains(attendees, a => a.DisplayName == "のん" && a.Status == 1);
        Assert.Contains(attendees, a => a.DisplayName == "ケンタ" && a.Status == 2);
    }

    [Fact]
    public async Task 出欠は何度答えても1件のまま()
    {
        var (client, room) = await SetUpAsync("のん");
        var scheduleId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", StartAt, null));

        foreach (var status in new[] { 1, 2, 1 })
        {
            await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}/attendance",
                new SaveAttendanceRequest(status));
        }

        var schedules = await client.GetFromJsonAsync<List<ScheduleDto>>($"/rooms/{room.RoomId}/schedules");
        var attendee = Assert.Single(Assert.Single(schedules!).Attendees);
        Assert.Equal(1, attendee.Status);
    }

    [Fact]
    public async Task 出欠の値が範囲外なら拒否される()
    {
        var (client, room) = await SetUpAsync("のん");
        var scheduleId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", StartAt, null));

        var response = await client.PutAsJsonAsync(
            $"/rooms/{room.RoomId}/schedules/{scheduleId}/attendance", new SaveAttendanceRequest(9));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task 他人のルームの予定は読めない()
    {
        var (_, room) = await SetUpAsync("のん");
        var (otherClient, _) = await SetUpAsync("ケンタ");

        var response = await otherClient.GetAsync($"/rooms/{room.RoomId}/schedules");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task 予定を消すと出欠も消える()
    {
        var (client, room) = await SetUpAsync("のん");
        var scheduleId = Guid.NewGuid();
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}",
            new SaveScheduleRequest("南北線を歩く", StartAt, null));
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}/attendance",
            new SaveAttendanceRequest(1));

        var delete = await client.DeleteAsync($"/rooms/{room.RoomId}/schedules/{scheduleId}");

        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        var schedules = await client.GetFromJsonAsync<List<ScheduleDto>>($"/rooms/{room.RoomId}/schedules");
        Assert.Empty(schedules!);
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
}
