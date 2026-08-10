import Foundation
import SwiftUI

/// アプリの中で言語を切り替える（SC-30）。
///
/// **端末の設定を開かせない。** iOS の「設定 ＞ アプリ ＞ 言語」でも変えられるが、
/// アプリを出てから戻ってくる手間があり、そこに言語の項目があると気づく人は少ない。
///
/// > ⚠️ **SwiftUI の `\.locale` を差し替えるやり方にしてある。**
/// > `UserDefaults` の `AppleLanguages` を書き換える手もあるが、
/// > **効かせるにはアプリの再起動が要る**。歩いている最中に再起動させたくない。
/// > `\.locale` なら、選んだその場で画面が切り替わる。
enum AppLanguage: String, CaseIterable, Identifiable {
    /// 端末の設定に従う（既定）
    case system
    case ja, en, de, es, fr, ko, ru
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    /// 選んだ言語の `Locale`。`system` のときは端末に任せる
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }

    /// 一覧に出す名前。**その言語自身の表記で書く**
    /// （読めない言語の名前を、読めない言語で探すことになるのを避ける）
    var label: String {
        switch self {
        case .system: "端末の設定に合わせる"
        case .ja:     "日本語"
        case .en:     "English"
        case .de:     "Deutsch"
        case .es:     "Español"
        case .fr:     "Français"
        case .ko:     "한국어"
        case .ru:     "Русский"
        case .zhHans: "简体中文"
        }
    }
}

/// いま選ばれている言語。画面のいちばん外側で `\.locale` に流す
@Observable
@MainActor
final class LanguageSetting {

    private static let key = "appLanguage"

    var selected: AppLanguage {
        didSet {
            guard selected != oldValue else { return }
            UserDefaults.standard.set(selected.rawValue, forKey: Self.key)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        selected = AppLanguage(rawValue: raw) ?? .system
    }

    /// 画面に流す `Locale`。`system` なら端末のものをそのまま使う
    var locale: Locale { selected.locale ?? Locale.autoupdatingCurrent }
}
