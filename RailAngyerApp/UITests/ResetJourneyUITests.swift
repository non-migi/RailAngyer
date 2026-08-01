import XCTest
import CoreLocation

/// 「記録を保存して新しい旅へ」。
///
/// 記録を消した直後に、**消したデータを掴んだままの画面が残っていると落ちる**。
/// 実際に1ターン歩いてからリセットし、盤面に戻って次の旅を始められるところまで確かめる。
final class ResetJourneyUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        // 現在地を始点に戻す。前のテストが残した位置のままだと、
        // 出発した瞬間に目的地の圏内にいて自動到着し、手動到着のボタンが消える
        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: 43.10834, longitude: 141.33848))   // 麻生

        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_FIXED_DICE"] = "1"
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }

    /// 盤面の歯車。ラベルが付いていない場合に備えて候補を順に探す
    private func settingsButton() -> XCUIElement {
        for key in ["設定", "gearshape", "gear"] where app.buttons[key].exists {
            return app.buttons[key]
        }
        return app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1)
    }

    func testResetsAfterWalkingAndKeepsRunning() {
        app.launch()

        let start = app.buttons["startJourney"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "ホームが出ていない")
        start.tap()

        let roll = app.buttons["サイコロを振る"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15))
        roll.tap()

        let proceed = app.buttons["向かう"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"),
                               evaluatedWith: proceed)], timeout: 10)
        proceed.tap()

        app.buttons["北34条 に到着した"].tap()
        let next = app.buttons["次へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(roll.waitForExistence(timeout: 5))

        // 設定から「記録を保存して新しい旅へ」
        settingsButton().tap()

        // 設定は縦に長い。目当てのボタンが出るまでスクロールする
        let reset = app.buttons["記録を保存して新しい旅へ"]
        for _ in 0..<8 where !reset.exists { app.swipeUp() }
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "設定にリセットのボタンが見つからない")
        reset.tap()
        app.buttons["保存して新しい旅へ"].tap()

        // ここで落ちていなければ、盤面に戻って次の旅を始められる
        let closeSettings = app.buttons["閉じる"]
        if closeSettings.waitForExistence(timeout: 3) { closeSettings.tap() }

        XCTAssertTrue(roll.waitForExistence(timeout: 10), "リセット後に盤面へ戻れていない")
        XCTAssertTrue(app.state == .runningForeground, "アプリが落ちている")

        roll.tap()
        XCTAssertTrue(app.buttons["向かう"].waitForExistence(timeout: 10),
                      "リセット後に次の旅を始められない")
    }

    /// 記録タブを開いてから設定でリセットする。
    ///
    /// タブは切り替えても生きたままなので、**消したデータを掴んだ画面が残る**経路になる。
    /// 端末で報告された落ち方に近づけるため、保存を効かせたまま（メモリ上ではなく）動かす。
    func testResetsAfterVisitingRecordsTab() {
        app.launchEnvironment.removeValue(forKey: "RAILANGYER_IN_MEMORY")
        app.launchEnvironment["RAILANGYER_RESET"] = "1"
        app.launch()

        let start = app.buttons["startJourney"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "ホームが出ていない")
        start.tap()

        let roll = app.buttons["サイコロを振る"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15))
        roll.tap()

        let proceed = app.buttons["向かう"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"),
                               evaluatedWith: proceed)], timeout: 10)
        proceed.tap()
        app.buttons["北34条 に到着した"].tap()
        let next = app.buttons["次へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()

        // 記録タブを一度描かせてから戻る
        app.buttons["記録"].firstMatch.tap()
        XCTAssertTrue(app.state == .runningForeground)
        app.buttons["旅"].firstMatch.tap()
        XCTAssertTrue(roll.waitForExistence(timeout: 10))

        settingsButton().tap()
        let reset = app.buttons["記録を保存して新しい旅へ"]
        for _ in 0..<8 where !reset.exists { app.swipeUp() }
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        app.buttons["保存して新しい旅へ"].tap()

        let closeSettings = app.buttons["閉じる"]
        if closeSettings.waitForExistence(timeout: 3) { closeSettings.tap() }

        XCTAssertEqual(app.state, .runningForeground, "アプリが落ちている")
        XCTAssertTrue(roll.waitForExistence(timeout: 10), "リセット後に盤面へ戻れていない")

        app.buttons["記録"].firstMatch.tap()
        XCTAssertEqual(app.state, .runningForeground, "記録タブでアプリが落ちている")
    }

    /// 区間を2駅に縮めてゴールし、盤面の「記録を保存して新しい旅へ」を押す。
    ///
    /// クリア表示のまま記録を消す経路。**消したデータを掴んだ画面が残っていると落ちる**。
    func testResetsFromClearedBoard() {
        app.launch()

        let start = app.buttons["startJourney"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "ホームが出ていない")
        start.tap()

        let roll = app.buttons["サイコロを振る"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15))

        // 麻生 → 北34条 の2駅にして、1ターンでゴールさせる
        settingsButton().tap()
        let goalPicker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'ゴール'")).firstMatch
        XCTAssertTrue(goalPicker.waitForExistence(timeout: 5))
        goalPicker.tap()
        app.buttons["北34条"].firstMatch.tap()
        app.buttons["保存"].tap()

        XCTAssertTrue(roll.waitForExistence(timeout: 10))
        roll.tap()

        let proceed = app.buttons["向かう"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"),
                               evaluatedWith: proceed)], timeout: 10)
        proceed.tap()
        app.buttons["北34条 に到着した"].tap()
        let next = app.buttons["次へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()

        let cleared = app.staticTexts["ゴールに到達しました"]
        XCTAssertTrue(cleared.waitForExistence(timeout: 10), "ゴールに到達できていない")

        let reset = app.buttons["記録を保存して新しい旅へ"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()

        XCTAssertEqual(app.state, .runningForeground, "アプリが落ちている")
        XCTAssertTrue(roll.waitForExistence(timeout: 10), "リセット後に盤面へ戻れていない")
    }
}
