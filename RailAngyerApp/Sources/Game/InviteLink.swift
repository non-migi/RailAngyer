import Foundation

/// 共有したリンクからアプリを開き、そのままルームへ入れるようにする。
///
/// **地図のリンクではなく、アプリを開くリンクを配る。**
/// 誘われた側にやってほしいのは「集合場所を見ること」ではなく
/// 「ルームに入って、お題を書いて、当日いっしょに歩くこと」だから。
///
/// 形は `railangyer://join?code=ABC123&name=南北線を歩く`。
/// アプリを入れていない相手には意味がないので、
/// 共有の文には**招待コードそのものも文字で残す**（`ScheduleShare`）。
enum InviteLink {

    static let scheme = "railangyer"
    static let joinHost = "join"

    /// 招待コードから、アプリを開くリンクを作る
    static func url(inviteCode: String, roomName: String? = nil) -> URL? {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = joinHost
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        if let roomName, !roomName.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "name", value: roomName))
        }
        return components.url
    }

    /// 開かれたリンクの中身
    struct Invitation: Equatable, Identifiable {
        let inviteCode: String
        let roomName: String?

        var id: String { inviteCode }
    }

    /// リンクを読む。**このアプリ宛ての招待でなければ nil**。
    ///
    /// 招待コードは大文字で扱う（`RoomJoinView` の入力と揃える）。
    /// 知らない形のリンクで勝手に参加させないよう、host まで見る
    static func invitation(from url: URL) -> Invitation? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // `railangyer://join?...` は host が、`railangyer:join?...` は path が joinHost になる
        let target = url.host?.lowercased()
            ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard target == joinHost else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard code.count >= 4 else { return nil }

        let name = items.first { $0.name == "name" }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Invitation(inviteCode: code,
                          roomName: (name?.isEmpty ?? true) ? nil : name)
    }
}
