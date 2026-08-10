import XCTest

/// 多言語対応（ParadoxLab と同じ8言語）。
///
/// **訳が入っていない文字列は日本語のまま出る**（String Catalog の既定）。
/// ここで確かめるのは、配線が通っていて**訳が実際に画面へ出る**こと。
final class LocalizationUITests: XCTestCase {

    /// アプリの中で選んだ言語は `UserDefaults` に残り、**再起動しても消えない**。
    /// 英語のまま終わると、後ろに続くスイートが軒並み英語の画面を相手にすることになる。
    /// 戻し損ねたときのために、後片付けでも必ず既定へ戻す
    private var needsLanguageRestore = false

    override func tearDown() {
        guard needsLanguageRestore else { return }
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launch()
        restoreDefaultLanguage(app)
        app.terminate()
        needsLanguageRestore = false
    }

    /// 言語を「端末の設定に合わせる」へ戻す。
    /// 一覧の名前はその言語自身の表記（＝訳さない）なので、画面が何語でも同じ文字で引ける
    private func restoreDefaultLanguage(_ app: XCUIApplication) {
        let gear = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label IN %@",
                        "gearshape", ["設定", "Settings"])).firstMatch
        guard gear.waitForExistence(timeout: 10) else { return }
        gear.tap()

        let picker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
                        "言語", "Language")).firstMatch
        guard picker.waitForExistence(timeout: 8) else { return }
        picker.tap()

        let system = app.buttons["端末の設定に合わせる"]
        if system.waitForExistence(timeout: 5) { system.tap() }

        app.buttons.matching(NSPredicate(format: "label IN %@", ["閉じる", "Close"]))
            .firstMatch.tap()
    }

    func testEnglishAppearsOnHome() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        // 「旅をスタート」が英語になっていること
        XCTAssertTrue(app.staticTexts["Start walking"].waitForExistence(timeout: 5),
                      "英語の訳が出ていない")
        // タブも英語
        XCTAssertTrue(app.buttons["Home"].exists, "タブが英語になっていない")
        XCTAssertTrue(app.buttons["Records"].exists)
    }

    /// **アプリの中で切り替えられること。** 端末の設定を開かせない
    func testSwitchesLanguageInApp() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        // まずは日本語
        XCTAssertTrue(app.staticTexts["旅をスタート"].exists, "日本語で始まっていない")

        app.buttons["設定"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 8))

        // 言語の欄まで送って English を選ぶ
        let picker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "言語")).firstMatch
        for _ in 0..<8 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.exists, "言語の欄が無い")
        picker.tap()
        // ここから先は端末に残る設定を触る。後片付けの対象になる
        needsLanguageRestore = true
        app.buttons["English"].tap()

        // **その場で切り替わること**（再起動を挟まない）
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5)
                      || app.staticTexts["Language"].waitForExistence(timeout: 5),
                      "設定画面が英語にならない")

        app.buttons.matching(NSPredicate(format: "label IN %@", ["閉じる", "Close"]))
            .firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Start walking"].waitForExistence(timeout: 5),
                      "ホームが英語にならない")

        // **選んだ言語は端末に残る。** ここで既定へ戻さないと、後続のスイートが
        // 英語の画面を相手にして軒並み落ちる
        restoreDefaultLanguage(app)
        XCTAssertTrue(app.staticTexts["旅をスタート"].waitForExistence(timeout: 8),
                      "既定の言語に戻せていない")
        needsLanguageRestore = false
    }

    func testGermanAppearsOnHome() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Reise starten"].waitForExistence(timeout: 5),
                      "ドイツ語の訳が出ていない")
    }
}
