import Testing
import Foundation
@testable import RailAngyerApp

/// 共有したリンクからアプリを開いて、そのままルームへ入る（`InviteLink`）。
///
/// **知らない形のリンクで勝手に参加させない**ことがいちばん大事。
/// リンクは他人が作れるので、読む側が厳しくなければならない。
struct InviteLinkTests {

    @Test("招待コードからリンクを作れる")
    func buildsURL() throws {
        let url = try #require(InviteLink.url(inviteCode: "abc123", roomName: "南北線を歩く"))

        #expect(url.scheme == "railangyer")
        #expect(url.host == "join")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        // 入力の大小はそろえる。招待コードの入力欄も大文字に直している
        #expect(items.first { $0.name == "code" }?.value == "ABC123")
        #expect(items.first { $0.name == "name" }?.value == "南北線を歩く")
    }

    @Test("作ったリンクはそのまま読み戻せる")
    func roundTrips() throws {
        let url = try #require(InviteLink.url(inviteCode: "ABC123", roomName: "南北線を歩く"))

        let invitation = try #require(InviteLink.invitation(from: url))

        #expect(invitation.inviteCode == "ABC123")
        #expect(invitation.roomName == "南北線を歩く")
    }

    @Test("ルーム名が無くてもリンクは作れる")
    func worksWithoutRoomName() throws {
        let url = try #require(InviteLink.url(inviteCode: "ABC123"))

        let invitation = try #require(InviteLink.invitation(from: url))

        #expect(invitation.inviteCode == "ABC123")
        #expect(invitation.roomName == nil)
    }

    @Test("招待コードが空ならリンクを作らない")
    func rejectsEmptyCode() {
        #expect(InviteLink.url(inviteCode: "") == nil)
        #expect(InviteLink.url(inviteCode: "   ") == nil)
    }

    @Test(
        "このアプリ宛てでないリンクは読まない",
        arguments: [
            "https://example.com/join?code=ABC123",     // 別のアプリ／ウェブ
            "railangyer://leave?code=ABC123",           // 知らない用件
            "railangyer://join?code=AB",                // コードが短すぎる
            "railangyer://join",                        // コードが無い
            "maps://?q=ABC123"
        ])
    func ignoresForeignLinks(text: String) throws {
        let url = try #require(URL(string: text))

        // **知らない形で勝手に参加させない。** リンクは誰でも作れる
        #expect(InviteLink.invitation(from: url) == nil)
    }

    @Test("小文字で書かれたコードも受ける")
    func acceptsLowercase() throws {
        let url = try #require(URL(string: "railangyer://join?code=abc123"))

        #expect(InviteLink.invitation(from: url)?.inviteCode == "ABC123")
    }
}
