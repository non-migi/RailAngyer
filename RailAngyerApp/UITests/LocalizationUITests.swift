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
