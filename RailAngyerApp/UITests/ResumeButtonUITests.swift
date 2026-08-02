import XCTest

/// 盤面へ抜けたときの戻り口（ビルド11で「サイコロを振る」に被っていた）。
///
/// **重ねて置かない。** 盤面の操作そのものを差し替える。
final class ResumeButtonUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launchEnvironment["RAILANGYER_FIXED_DICE"] = "2"
    }

    func testBoardShowsResumeInsteadOfDice() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        app.buttons["startJourney"].tap()

        let dice = app.buttons["サイコロを振る"]
        XCTAssertTrue(dice.waitForExistence(timeout: 8), "盤面にサイコロのボタンが無い")
        dice.tap()

        // 振ったらターンの画面が出る。「盤面へ」で抜ける
        let leave = app.buttons["minimizeTurn"]
        XCTAssertTrue(leave.waitForExistence(timeout: 8), "盤面へ抜けるボタンが無い")
        leave.tap()

        // **盤面の操作が「戻る」に差し替わっていること**
        let resume = app.buttons["resumeTurn"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8), "戻る口が出ていない")
        XCTAssertFalse(app.buttons["サイコロを振る"].exists,
                       "進行中なのにサイコロのボタンが残っている（被りの原因）")

        resume.tap()
        XCTAssertTrue(app.buttons["minimizeTurn"].waitForExistence(timeout: 8),
                      "戻る口からターンの画面へ戻れない")
    }
}
