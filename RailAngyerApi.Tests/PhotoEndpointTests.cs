using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using RailAngyerApi.Endpoints;

namespace RailAngyerApi.Tests;

/// <summary>
/// 写真（11_API設計.md §5）。
/// <b>SASの発行先が正しいこと</b>と、<b>消したときに実体が残らないこと</b>を確かめる。
/// </summary>
public class PhotoEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Fact]
    public async Task アップロード用のURLが訪問ごとのパスで発行される()
    {
        var (client, room) = await SetUpAsync("のん");
        var visitId = await ArriveAsync(client, room.RoomId, stationId: 4);
        var photoId = Guid.NewGuid();

        var response = await client.PostAsJsonAsync($"/rooms/{room.RoomId}/photos/upload-url",
            new UploadUrlRequest(photoId, visitId));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var issued = await response.Content.ReadFromJsonAsync<UploadUrlDto>();
        Assert.Equal($"{room.RoomId}/{visitId}/{photoId}.jpg", issued!.BlobPath);
        Assert.Contains(issued.BlobPath, issued.UploadUrl);
        Assert.True(issued.ExpiresAt > DateTime.UtcNow);   // 期限付き
    }

    [Fact]
    public async Task 他ルームの訪問には発行されない()
    {
        var (client, room) = await SetUpAsync("のん");
        var (otherClient, otherRoom) = await SetUpAsync("ケンタ");
        var otherVisitId = await ArriveAsync(otherClient, otherRoom.RoomId, stationId: 4);

        var response = await client.PostAsJsonAsync($"/rooms/{room.RoomId}/photos/upload-url",
            new UploadUrlRequest(Guid.NewGuid(), otherVisitId));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task メタを登録すると読み取りURL付きで一覧に出る()
    {
        var (client, room) = await SetUpAsync("のん");
        var visitId = await ArriveAsync(client, room.RoomId, stationId: 4);
        var photoId = await UploadAsync(client, room.RoomId, visitId);

        var photos = await client.GetFromJsonAsync<List<PhotoDto>>($"/rooms/{room.RoomId}/photos");

        var photo = Assert.Single(photos!);
        Assert.Equal(photoId, photo.PhotoId);
        Assert.Equal(4, photo.StationId);
        Assert.Equal("のん", photo.TakenByName);
        Assert.Contains("sig=read", photo.Url);
        Assert.True(photo.UrlExpiresAt > DateTime.UtcNow);
    }

    [Fact]
    public async Task 同じIDへ二度登録しても増えない()
    {
        var (client, room) = await SetUpAsync("のん");
        var visitId = await ArriveAsync(client, room.RoomId, stationId: 4);
        var photoId = Guid.NewGuid();
        var body = new SavePhotoRequest(visitId, DateTime.UtcNow);

        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/photos/{photoId}", body);
        await client.PutAsJsonAsync($"/rooms/{room.RoomId}/photos/{photoId}", body);

        var photos = await client.GetFromJsonAsync<List<PhotoDto>>($"/rooms/{room.RoomId}/photos");
        Assert.Single(photos!);
    }

    [Fact]
    public async Task 写真はチームの全員に見える()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);
        var visitId = await ArriveAsync(hostClient, room.RoomId, stationId: 4);
        await UploadAsync(hostClient, room.RoomId, visitId);

        // お題と違い、写真は伏せない（一緒に歩いた記録なので）
        var seen = await guestClient.GetFromJsonAsync<List<PhotoDto>>($"/rooms/{room.RoomId}/photos");

        Assert.Single(seen!);
    }

    [Fact]
    public async Task 他人の写真は消せない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);
        var visitId = await ArriveAsync(hostClient, room.RoomId, stationId: 4);
        var photoId = await UploadAsync(hostClient, room.RoomId, visitId);

        var response = await guestClient.DeleteAsync($"/rooms/{room.RoomId}/photos/{photoId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Contains(factory.Photos.Blobs, b => b.Contains(photoId.ToString()));
    }

    [Fact]
    public async Task 他人の写真を差し替えるSASは出ない()
    {
        var (hostClient, room) = await SetUpAsync("のん");
        var guest = await JoinAsync(room.InviteCode, "ケンタ");
        var guestClient = Authorized(guest.Token);
        var visitId = await ArriveAsync(hostClient, room.RoomId, stationId: 4);
        var photoId = await UploadAsync(hostClient, room.RoomId, visitId);

        var response = await guestClient.PostAsJsonAsync($"/rooms/{room.RoomId}/photos/upload-url",
            new UploadUrlRequest(photoId, visitId));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task 自分の写真を消すとBlobの実体も消える()
    {
        var (client, room) = await SetUpAsync("のん");
        var visitId = await ArriveAsync(client, room.RoomId, stationId: 4);
        var photoId = await UploadAsync(client, room.RoomId, visitId);
        var path = $"{room.RoomId}/{visitId}/{photoId}.jpg";
        Assert.Contains(path, factory.Photos.Blobs);

        var response = await client.DeleteAsync($"/rooms/{room.RoomId}/photos/{photoId}");

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.DoesNotContain(path, factory.Photos.Blobs);
        Assert.Empty((await client.GetFromJsonAsync<List<PhotoDto>>($"/rooms/{room.RoomId}/photos"))!);
    }

    [Fact]
    public async Task 記録をリセットするとルーム配下のBlobも消える()
    {
        var (client, room) = await SetUpAsync("のん");
        var (otherClient, otherRoom) = await SetUpAsync("ケンタ");
        var visitId = await ArriveAsync(client, room.RoomId, stationId: 4);
        await UploadAsync(client, room.RoomId, visitId);
        var otherVisitId = await ArriveAsync(otherClient, otherRoom.RoomId, stationId: 4);
        await UploadAsync(otherClient, otherRoom.RoomId, otherVisitId);

        await client.DeleteAsync($"/rooms/{room.RoomId}/progress");

        // 孤児Blobを残さない。かつ、他のルームの写真は巻き添えにしない
        Assert.DoesNotContain(factory.Photos.Blobs, b => b.StartsWith($"{room.RoomId}/"));
        Assert.Contains(factory.Photos.Blobs, b => b.StartsWith($"{otherRoom.RoomId}/"));
    }

    [Fact]
    public async Task トークンが無ければ写真は見られない()
    {
        var (client, room) = await SetUpAsync("のん");
        var visitId = await ArriveAsync(client, room.RoomId, stationId: 4);
        await UploadAsync(client, room.RoomId, visitId);

        var response = await factory.CreateClient().GetAsync($"/rooms/{room.RoomId}/photos");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
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

    /// <summary>SASをもらう → 端末がBlobへ上げる（偽物では発行時点で上がったことにする） → メタ登録</summary>
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
