import Foundation
import TelemetryDeck

/// 利用状況の測定（TelemetryDeck）。
///
/// **何が使われていないかを知るために入れている。** 直す先を決めるための道具であって、
/// 人を追いかけるためのものではない。
///
/// > ⚠️ **送ってよいものを決めてある。外すと約束を破ることになる。**
/// > - 送る：画面や操作の種類、コース名、端末の種類、アプリの版
/// > - **送らない：位置（座標・駅名）、写真、お題の中身、表示名、招待コード**
/// >
/// > 駅名は「いまどこにいるか」に近いので送らない。
/// > コース名までなら「どの路線が遊ばれているか」しか分からず、次に足すコースを決められる。
/// > プライバシーポリシー §3 に書いた範囲を超えないこと。
///
/// App ID を入れていないあいだは**何もしない**（初期化もしない）。
enum Telemetry {

    /// 送り先。`Info.plist` の `TelemetryDeckAppID` から読む。
    /// 空なら測定しない — 手元のビルドやテストで勝手に送らないため
    private static var appID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private(set) static var isEnabled = false

    /// 起動時に1回だけ呼ぶ
    static func start() {
        guard !isEnabled, let appID else { return }
        // テストで数字を汚さない
        guard !TestHooks.usesInMemoryStore else { return }

        TelemetryDeck.initialize(config: .init(appID: appID))
        isEnabled = true
        signal("app.launched")
    }

    /// 出来事を送る。
    ///
    /// - Parameters:
    ///   - name: `journey.started` のように「対象.したこと」で書く
    ///   - parameters: **個人に迫らない値だけ**（コース名、件数、真偽）
    static func signal(_ name: String, _ parameters: [String: String] = [:]) {
        guard isEnabled else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }

    // MARK: - 送る出来事
    //
    // 呼び出し側に文字列を散らさない。**ここに並んでいるものが送るものの全部**

    static func journeyStarted(course: String?, isLap: Bool, stationCount: Int) {
        signal("journey.started", [
            "course": course ?? "unknown",
            "isLap": isLap ? "true" : "false",
            // 駅数は区間の長さ。どれくらいの規模で遊ばれているかを知る
            "stationCount": "\(stationCount)"
        ])
    }

    static func diceRolled(value: Int) {
        signal("turn.rolled", ["dice": "\(value)"])
    }

    /// 到着が自動判定だったか、手で押されたか。
    /// **手動が多い駅がある＝座標か半径がずれている**、という読み方をする
    static func arrived(automatic: Bool) {
        signal("turn.arrived", ["automatic": automatic ? "true" : "false"])
    }

    static func missionDrawn(hadCandidates: Bool) {
        signal("mission.drawn", ["hadCandidates": hadCandidates ? "true" : "false"])
    }

    static func missionWritten() { signal("mission.written") }

    static func journeyCleared(turns: Int) {
        signal("journey.cleared", ["turns": "\(turns)"])
    }

    static func scheduleCreated(course: String?, isLap: Bool) {
        signal("schedule.created", [
            "course": course ?? "unknown",
            "isLap": isLap ? "true" : "false"
        ])
    }

    static func scheduleShared() { signal("schedule.shared") }

    /// 共有リンクから開かれた。**誘いが効いているかを知る唯一の手がかり**
    static func inviteOpened() { signal("invite.opened") }

    static func roomJoined() { signal("room.joined") }

    static func photoTaken() { signal("photo.taken") }

    static func courseChanged(to course: String) {
        signal("course.changed", ["course": course])
    }

    static func missionVisibilityChanged(to visibility: MissionVisibility) {
        signal("settings.missionVisibility",
               ["value": visibility == .always ? "always" : "surprise"])
    }

    static func supported(tier: String) {
        signal("support.purchased", ["tier": tier])
    }
}
