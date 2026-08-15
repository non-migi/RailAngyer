import Foundation
import SwiftUI
import UIKit

/// 見たくない相手を、この端末の中だけで非表示にする（App Store ガイドライン 1.2）。
///
/// **サーバーには伝えない。** ブロックは「自分の画面に出さない」ための設定であって、
/// 相手の記録を消す権限ではない。ルームごとに `UserDefaults` へ持つ軽い実装で足りる
/// （ルームは招待した仲間内なので、件数はたかが知れている）
enum MemberBlockList {

    private static func key(_ roomId: UUID) -> String {
        "blockedMembers.\(roomId.uuidString)"
    }

    static func load(roomId: UUID) -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: key(roomId)) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func save(_ ids: Set<UUID>, roomId: UUID) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(roomId))
        } else {
            UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: key(roomId))
        }
    }
}

/// 不適切な投稿の通報（App Store ガイドライン 1.2）。
///
/// 通報はメールで受ける。個人開発の規模ではアプリ内に窓口を作るより、
/// **人が確実に読む届き先へ最短で届く**形のほうが対応が速い。
/// 本文には、どの投稿の話かを特定できる情報（ルーム・投稿者・日時）をあらかじめ入れておく
enum ReportMail {

    /// 届け先。退室後のデータ削除依頼もここで受ける
    static let address = "hikagebiyori@gmail.com"

    /// 何を通報しているのか。
    ///
    /// **利用者が作るもの（UGC）は3種**あり、どれにも通報の口が要る
    /// （App Store ガイドライン 1.2）。表示名も投稿と同じく利用者が決める文字なので、
    /// 写真・お題と並べてここに置く
    enum Target {
        case photo, mission, displayName

        /// メールの本文に入れる名前。**訳さない**（`title` と使い分ける）
        var englishLabel: String {
            switch self {
            case .photo:       "Photo"
            case .mission:     "Mission text"
            case .displayName: "Display name"
            }
        }
    }

    /// 通報メールを開く `mailto:` URL。
    ///
    /// **件名と項目名は英語で固定する。** アプリは9言語で使われるので、
    /// 通報者の言語で組むと、受け取る側（開発者ひとり）が読めないメールが届く。
    /// 通報者が自分の言葉で書く「理由」の欄だけ、現地語の案内を添える。
    ///
    /// - Parameters:
    ///   - target: 何の通報か（写真・お題・表示名）
    ///   - detail: 投稿の中身。お題のように文字の投稿ではここに入れる
    static func url(target: Target, roomName: String?, authorName: String,
                    postedAt: Date, detail: String? = nil) -> URL? {
        let subject = "[RailAngyer] Report: \(target.englishLabel)"
        var lines = [
            "Type: \(target.englishLabel)",
            "Room: \(roomName ?? "-")",
            "Posted by: \(authorName)",
            // 端末の暦や書式に左右されない形にする（受け手が読み違えない）
            "Posted at: \(postedAt.formatted(.iso8601))",
        ]
        if let detail, !detail.isEmpty {
            lines.append("Content: \(detail)")
        }
        lines.append("")
        lines.append("Reason (please write in any language):")
        lines.append(appLocalized("通報の理由をここに書いてください："))

        // `mailto:` は URL の形が普通と違う。**手で組み立てず URLComponents に任せる**
        // （件名や本文に日本語・改行が入るため、素朴に足すと壊れた URL になる）
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: lines.joined(separator: "\n")),
        ]
        return components.url
    }
}

extension View {

    /// 通報メールを開けなかったときの逃げ道。
    ///
    /// **`mailto:` は開けない端末がある。** Mail.app を消した端末や、
    /// メールアカウントを1つも設定していない端末では `openURL` が黙って失敗し、
    /// 押しても何も起きない＝通報の手段が無い端末になってしまう
    /// （App Store ガイドライン 1.2 は通報できることを求める）。
    /// 開けなかったときは届け先をその場に出し、コピーして送れるようにする。
    ///
    /// 呼ぶ側は `openURL(url) { if !$0 { showing = true } }` の完了で立てる
    func reportMailFallbackAlert(isPresented: Binding<Bool>) -> some View {
        alert("メールを開けませんでした", isPresented: isPresented) {
            Button("宛先をコピーする") { UIPasteboard.general.string = ReportMail.address }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("この端末ではメールを開けませんでした。通報は \(ReportMail.address) 宛のメールで受け付けています。宛先をコピーして、どの投稿のことか分かるように書いて送ってください。")
        }
    }
}
