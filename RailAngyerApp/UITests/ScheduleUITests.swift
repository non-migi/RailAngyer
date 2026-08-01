import XCTest

/// 予定まわり。
///
/// **立てた予定がその場で一覧に出る**ことを確かめる。
/// 端末の保存は即時なので、待たされてよいのは仲間への共有だけ。
final class ScheduleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }

    func testNewScheduleAppearsImmediately() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15), "ホームが出ていない")

        app.buttons["予定"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["予定"].waitForExistence(timeout: 5))

        addButton().tap()
        let titleField = app.textFields["南北線を歩く"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("土曜に歩く")
        app.buttons["保存"].tap()

        // 保存した瞬間に一覧へ出ていること（同期を待たない）
        XCTAssertTrue(app.staticTexts["土曜に歩く"].waitForExistence(timeout: 3),
                      "立てた予定が一覧に出ていない")

        // 予定の段階からお題を書ける
        let writeMissions = app.buttons["この予定のお題を書く"]
        XCTAssertTrue(writeMissions.waitForExistence(timeout: 5))
        writeMissions.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'あなたのお題'")).firstMatch
            .waitForExistence(timeout: 5), "予定からお題の画面を開けない")
    }

    /// ＋ボタン。ラベルが付かないことがあるので、右上のボタンを取りにいく
    private func addButton() -> XCUIElement {
        let plus = app.buttons["plus"]
        if plus.exists { return plus }
        let bar = app.navigationBars["予定"]
        return bar.buttons.element(boundBy: bar.buttons.count - 1)
    }
}
