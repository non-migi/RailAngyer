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

    /// 通知の許可を求めない（例: `RAILANGYER_NO_NOTIF_PROMPT=1`）。
    /// UIテストでは許可ダイアログが操作を塞ぐため、検証対象でないときは出さない
    static var suppressesNotificationPrompt: Bool {
        ProcessInfo.processInfo.environment["RAILANGYER_NO_NOTIF_PROMPT"] == "1"
    }

    /// 起動時に進行記録を消す（例: `RAILANGYER_RESET=1`）。
    /// 中断・復帰のテストでは、**保存を効かせたまま**初期状態から始める必要があるため、
    /// メモリ上の起動ではなくこちらを使う
    static var resetsProgressOnLaunch: Bool {
        ProcessInfo.processInfo.environment["RAILANGYER_RESET"] == "1"
    }
}
