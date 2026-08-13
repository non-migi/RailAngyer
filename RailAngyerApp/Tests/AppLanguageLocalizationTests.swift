import Testing
import Foundation
@testable import RailAngyerApp

/// アプリ内で選んだ言語で文言を引くヘルパー（`appLocalized` / `AppLanguage.bundle`）。
///
/// **`String(localized:)` を素で呼ぶと端末のシステム言語で固まる。**
/// アプリには言語切り替えの画面があるので、`UserDefaults` に保存した選択が
/// そのまま文言の解決に効くことを、ビルド済みカタログ（各言語の .lproj）で確かめる。
@MainActor
struct AppLanguageLocalizationTests {

    /// 言語を一時的に切り替えて確かめ、**必ず元へ戻す**。
    /// `UserDefaults` はプロセス全体で共有なので、戻し忘れると他の試験の言語が変わる
    private func withLanguage<T>(_ raw: String?, _ body: () throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.storageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppLanguage.storageKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.storageKey)
            }
        }
        if let raw {
            defaults.set(raw, forKey: AppLanguage.storageKey)
        } else {
            defaults.removeObject(forKey: AppLanguage.storageKey)
        }
        return try body()
    }

    @Test("英語を選ぶと、端末の言語に関係なく英語の訳が返る")
    func resolvesEnglish() {
        withLanguage("en") {
            #expect(appLocalized("設定") == "Settings")
            #expect(appLocalized("ホーム") == "Home")
        }
    }

    @Test("ヒンディー語を選ぶとヒンディー語の訳が返る")
    func resolvesHindi() {
        withLanguage("hi") {
            #expect(appLocalized("設定") == "सेटिंग्स")
            #expect(appLocalized("ホーム") == "होम")
        }
    }

    @Test("ヒンディー語の代表文言はデーヴァナーガリー文字で書かれている")
    func hindiUsesDevanagariScript() {
        withLanguage("hi") {
            for text in [appLocalized("サイコロを振る"), appLocalized("ホーム")] {
                #expect(text.unicodeScalars.contains { ("\u{0900}"..."\u{097F}").contains($0) },
                        "デーヴァナーガリー文字が含まれない: \(text)")
            }
        }
    }

    @Test("日本語以外のどの言語を選んでも、代表文言が日本語のままにならない")
    func everyLanguageResolvesAwayFromJapanese() {
        for language in AppLanguage.allCases where language != .system && language != .ja {
            withLanguage(language.rawValue) {
                #expect(appLocalized("設定") != "設定",
                        "\(language.rawValue) で「設定」が日本語のまま")
                #expect(appLocalized("サイコロを振る") != "サイコロを振る",
                        "\(language.rawValue) で「サイコロを振る」が日本語のまま")
            }
        }
    }

    @Test("今回そろえた書式付きキーが、選んだ言語の訳で解決される")
    func newlyAlignedKeysResolve() {
        withLanguage("en") {
            #expect(appLocalized("直線 約 \("1.2") km") == "About 1.2 km direct")
            #expect(appLocalized("徒歩 約 \(350) m") == "About 350 m on foot")
            #expect(appLocalized("\("南北線")ツアー") == "南北線 tour")
        }
        withLanguage("de") {
            #expect(appLocalized("直線 約 \(350) m") == "Luftlinie ca. 350 m")
        }
    }

    @Test("日本語を選ぶと日本語のまま返る")
    func resolvesJapanese() {
        withLanguage("ja") {
            #expect(appLocalized("設定") == "設定")
        }
    }

    @Test("カタログに無い文言は、そのままの形で返る")
    func fallsBackToKeyText() {
        // キーは日本語文言そのもの。訳がまだ無い言語では日本語のまま出る
        withLanguage("en") {
            #expect(appLocalized("この文言はカタログにありません") == "この文言はカタログにありません")
        }
    }

    @Test("バンドルは選んだ言語の lproj を指し、system なら main に任せる")
    func bundleFollowsSelection() {
        withLanguage("en") {
            #expect(AppLanguage.bundle.bundlePath.hasSuffix("en.lproj"))
        }
        // フォルダ名は zh-Hans.lproj。enum の rawValue と一致していること
        withLanguage("zh-Hans") {
            #expect(AppLanguage.bundle.bundlePath.hasSuffix("zh-Hans.lproj"))
        }
        withLanguage(nil) {
            #expect(AppLanguage.bundle == Bundle.main)
        }
    }
}
