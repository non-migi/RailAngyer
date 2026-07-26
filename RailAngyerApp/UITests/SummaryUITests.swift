import XCTest

/// ふりかえり（SC-17）。
///
/// 集計そのものは `JourneySummaryTests` で確かめている。
/// ここで見たいのは**盤面から開けること**と、**まだ何も歩いていなくても壊れないこと**。
/// 記録が空のときに落ちる画面は、遊び始めの人が最初に踏む。
final class SummaryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }

    func testOpensSummaryFromBoard() {
        app.launch()

        XCTAssertTrue(app.buttons["サイコロを振る"].waitForExistence(timeout: 15), "盤面が出ていない")

        app.buttons["ふりかえり"].tap()

        XCTAssertTrue(app.navigationBars["ふりかえり"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["歩いた駅"].exists, "駅の一覧が出ていない")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ふりかえり"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["サイコロを振る"].waitForExistence(timeout: 5), "盤面に戻れていない")
    }
}
