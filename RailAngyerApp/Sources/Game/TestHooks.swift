import Foundation

/// UIテストから進行を再現するための入口。
///
/// 通常の起動では環境変数が無いため、いずれも `nil` / `false` になり影響しない。
/// 出目が乱数のままだと「歩いて到着する」ところを自動で検証できないため、
/// テスト時だけ出目とストアの保存先を固定する。
enum TestHooks {

    /// 出目を固定する（例: `RAILANGYER_FIXED_DICE=1`）
    static var fixedDice: Int? {
        guard let raw = ProcessInfo.processInfo.environment["RAILANGYER_FIXED_DICE"],
              let value = Int(raw), (1...9).contains(value) else { return nil }
        return value
    }

    /// 記録を残さずメモリ上で起動する（例: `RAILANGYER_IN_MEMORY=1`）。
    /// 実行のたびに同じ初期状態から始められる
    static var usesInMemoryStore: Bool {
        ProcessInfo.processInfo.environment["RAILANGYER_IN_MEMORY"] == "1"
    }

    /// お題の見本を入れて起動する（例: `RAILANGYER_SAMPLE_MISSIONS=1`）。
    /// **地図の見え方を確かめるため**。お題が1つも無いと、ピンも文字も出ない
    static var seedsSampleMissions: Bool {
        ProcessInfo.processInfo.environment["RAILANGYER_SAMPLE_MISSIONS"] == "1"
    }

    /// 通知の許可を求めない（例: `RAILANGYER_NO_NOTIF_PROMPT=1`）。
    /// UIテストでは許可ダイアログが操作を塞ぐため、検証対象でないときは出さない
    static var suppressesNotificationPrompt: Bool {
        ProcessInfo.processInfo.environment["RAILANGYER_NO_NOTIF_PROMPT"] == "1"
    }

    /// 参加済みのルームを仲間ごと作って起動する（例: `RAILANGYER_SAMPLE_ROOM=1`）。
    ///
    /// **通報・非表示・ルームから外すの口は、他人のメンバー行にしか出ない。**
    /// 仲間はサーバーから取り込んで初めて増えるので、サーバー無しでは
    /// その導線を画面に出せず、UIテストで守れない。
    /// （App Store ガイドライン 1.2 の要件なので、審査で触られる導線でもある）
    ///
    /// この変数があるときだけ、参加済み・仲間2人・自分が作成者、の状態を作る。
    /// **通常の起動では環境変数が無いため、本番の挙動は変わらない**
    static var seedsSampleRoom: Bool {
        ProcessInfo.processInfo.environment["RAILANGYER_SAMPLE_ROOM"] == "1"
    }

    /// 起動時に進行記録を消す（例: `RAILANGYER_RESET=1`）。
    /// 中断・復帰のテストでは、**保存を効かせたまま**初期状態から始める必要があるため、
    /// メモリ上の起動ではなくこちらを使う
    static var resetsProgressOnLaunch: Bool {
        ProcessInfo.processInfo.environment["RAILANGYER_RESET"] == "1"
    }
}
