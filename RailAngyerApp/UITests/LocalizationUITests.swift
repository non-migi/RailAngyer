import XCTest

/// 多言語対応（ParadoxLab と同じ8言語）。
///
/// **訳が入っていない文字列は日本語のまま出る**（String Catalog の既定）。
/// ここで確かめるのは、配線が通っていて**訳が実際に画面へ出る**こと。
final class LocalizationUITests: XCTestCase {

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
        XCTAssertTrue(app.navigationBars["ルール設定"].waitForExistence(timeout: 8))

        // 言語の欄まで送って English を選ぶ
        let picker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "言語")).firstMatch
        for _ in 0..<8 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.exists, "言語の欄が無い")
        picker.tap()
        app.buttons["English"].tap()

        // **その場で切り替わること**（再起動を挟まない）
        XCTAssertTrue(app.navigationBars["Rules"].waitForExistence(timeout: 5)
                      || app.staticTexts["Language"].waitForExistence(timeout: 5),
                      "設定画面が英語にならない")

        app.buttons.matching(NSPredicate(format: "label IN %@", ["閉じる", "Close"]))
            .firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Start walking"].waitForExistence(timeout: 5),
                      "ホームが英語にならない")
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
