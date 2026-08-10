import XCTest

/// 環状線の一周モードでのルール保存。
///
/// 一周は**スタートとゴールが同じ駅になるのが正しい**。
/// これを「別の駅にしてください」の条件で弾いていたため、
/// 一周モードでは最大出目を変えても保存できず、黙って元に戻っていた。
final class LapRuleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }

    func testSavesDiceMaxWhileLapping() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15), "ホームが出ていない")

        openSettings()

        // 環状のコースにしないと「一周する」が出ない
        let coursePicker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'コース'")).firstMatch
        XCTAssertTrue(coursePicker.waitForExistence(timeout: 5), "コースの選択が見つからない")
        coursePicker.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '山手線'")).firstMatch.tap()

        // 行の真ん中は文字の上で、押しても切り替わらない。スイッチそのものを押す
        let lap = app.switches["一周する"]
        XCTAssertTrue(lap.waitForExistence(timeout: 5), "環状のコースなのに一周の設定が出ていない")
        lap.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(lap.value as? String, "1", "一周モードに入れていない")

        // 最大出目を 6 → 7 に
        let dice = app.steppers.element(boundBy: 0)
        XCTAssertTrue(dice.waitForExistence(timeout: 5))
        dice.buttons["Increment"].tap()

        let save = app.buttons["保存"]
        XCTAssertTrue(save.isEnabled, "一周モードで保存できない（スタート＝ゴールで弾かれている）")
        save.tap()

        // 盤面の見出しに、保存した最大出目が出ていること
        app.buttons["旅"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["サイコロ 1〜7"].waitForExistence(timeout: 10),
                      "最大出目が保存されていない")
    }

    /// ホーム右上の歯車。ラベルが付いていない場合に備えて候補を順に探す
    private func openSettings() {
        for key in ["設定", "gearshape", "gear"] where app.buttons[key].firstMatch.exists {
            app.buttons[key].firstMatch.tap()
            return
        }
        app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1).tap()
    }
}
