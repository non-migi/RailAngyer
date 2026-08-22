import Foundation
import SwiftUI
import RailAngyerCore

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
    case ja, en, de, es, fr, hi, ko, ru
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
        case .system: appLocalized("端末の設定に合わせる")
        case .ja:     "日本語"
        case .en:     "English"
        case .de:     "Deutsch"
        case .es:     "Español"
        case .fr:     "Français"
        case .hi:     "हिन्दी"
        case .ko:     "한국어"
        case .ru:     "Русский"
        case .zhHans: "简体中文"
        }
    }

    /// `UserDefaults` の保存キー。`LanguageSetting` と共用する
    static let storageKey = "appLanguage"

    /// いま選ばれている言語。**ビュー階層の外から読むための入口**
    /// （通知や共有文は `\.locale` の環境値を受け取れない）。
    /// 保存キーと `locale` の導出は `LanguageSetting` と同じ
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// いま選ばれている言語の `Locale`。`system` なら端末のものをそのまま使う
    static var currentLocale: Locale {
        current.locale ?? Locale.autoupdatingCurrent
    }

    /// いま選ばれている言語の文言が入った `Bundle`。
    ///
    /// `String(localized:)` を素で呼ぶと**端末のシステム言語**で解決され、
    /// アプリ内の言語切り替えに追随しない。選んだ言語の `.lproj` を直接指した
    /// バンドルを通すと、切り替えたその場から新しい言語で引ける。
    /// `system` のときと、その言語の訳がまだ無いときは `.main` に任せる
    static var bundle: Bundle {
        guard let code = current.locale?.identifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

/// アプリ内で選んだ言語で文言を引く。
///
/// **`String(localized:)` を直接使わず、必ずここを通す。**
/// 素の `String(localized:)` は端末のシステム言語で固まり、
/// アプリ内の言語切り替え（`AppLanguage` / `LanguageSetting`）に追随しない。
/// 言語を切り替えたあと画面が描き直されれば、ここを通した文言は新しい言語で出る
func appLocalized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: AppLanguage.bundle, locale: AppLanguage.currentLocale)
}

/// いま選ばれている言語。画面のいちばん外側で `\.locale` に流す
@Observable
@MainActor
final class LanguageSetting {

    private static let key = AppLanguage.storageKey

    var selected: AppLanguage {
        didSet {
            guard selected != oldValue else { return }
            UserDefaults.standard.set(selected.rawValue, forKey: Self.key)
            applyToCore()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        selected = AppLanguage(rawValue: raw) ?? .system
        applyToCore()
    }

    /// **時間の単位を `RailAngyerCore` にも伝える。**
    /// `DurationText` は画面の文言と別の場所（訳文を持たない計算側）にいるので、
    /// ここで渡さないと、英語で開いても「32秒」と日本語の単位が出る
    private func applyToCore() {
        DurationText.locale = locale
    }

    /// 画面に流す `Locale`。`system` なら端末のものをそのまま使う
    var locale: Locale { selected.locale ?? Locale.autoupdatingCurrent }
}
