import Foundation
import UserNotifications
import UIKit

/// 到着をユーザーに知らせる（10_アプリ設計.md §6.4）。
///
/// 歩いている間ずっと画面を見ているとは限らない。
/// ジオフェンスで到着を検知しても、知らせる手段が無ければ気づけないため、
/// **バックグラウンドのときだけ**ローカル通知を出す。
///
/// フェーズ1ではローカル通知のみ。他の端末の進行を知らせるプッシュ通知は
/// Q-02（誰がサイコロを振るか）が決まってから判断する。
enum NotificationService {

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 画面を見ているときは通知しない。見ているのに二重に知らせても邪魔なだけ
    @MainActor
    private static var isBackgrounded: Bool {
        UIApplication.shared.applicationState != .active
    }

    /// 通り道の駅に着いた
    @MainActor
    static func notifyPassingArrival(station: String) {
        post(title: appLocalized("\(station) に到着"),
             body: appLocalized("写真を撮ったら、次の駅へ進みましょう"))
    }

    /// 着地駅に着いた（ミッションを引く駅）
    @MainActor
    static func notifyLanding(station: String, missionCount: Int) {
        post(title: appLocalized("\(station) に到着"),
             body: missionCount > 0
                 ? appLocalized("ミッション \(missionCount) 個から1つ引きます")
                 : appLocalized("この駅にミッションはありません"))
    }

    /// ゴールした
    @MainActor
    static func notifyCleared(station: String) {
        post(title: appLocalized("ゴール！"),
             body: appLocalized("\(station) に到達しました。おつかれさまでした"))
    }

    @MainActor
    private static func post(title: String, body: String) {
        guard isBackgrounded else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)   // 即時
        UNUserNotificationCenter.current().add(request)
    }
}
