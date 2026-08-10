import XCTest
import CoreLocation

/// 「記録を保存して新しい旅へ」。
///
/// 記録を消した直後に、**消したデータを掴んだままの画面が残っていると落ちる**。
/// 実際に1ターン歩いてからリセットし、盤面に戻って次の旅を始められるところまで確かめる。
///
/// このボタンは端末の設定から予定（ホーム → 予定 → いまの旅）へ移った。
/// 遊び方のルールも予定で決めるようになったので、区間の指定もそちらから行う。
final class ResetJourneyUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false

        // 現在地を始点（麻生）に戻す。**前のテストが残した位置のままだと、
        // 出発した瞬間に目的地の圏内にいて自動到着してしまい、手動の導線を通れない**
        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: 43.10834, longitude: 141.33848))

        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_FIXED_DICE"] = "1"
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }

    func testResetsAfterWalkingAndKeepsRunning() {
        app.launch()

        startFromHome()
        walkOneTurn()

        resetFromSchedules()

        // ここで落ちていなければ、盤面に戻って次の旅を始められる
        let roll = app.buttons["サイコロを振る"]
        XCTAssertTrue(roll.waitForExistence(timeout: 10), "リセット後に盤面へ戻れていない")
        XCTAssertTrue(app.state == .runningForeground, "アプリが落ちている")

        roll.tap()
        XCTAssertTrue(app.buttons["向かう"].waitForExistence(timeout: 10),
                      "リセット後に次の旅を始められない")
    }

    /// 記録タブを開いてから予定でリセットする。
    ///
    /// タブは切り替えても生きたままなので、**消したデータを掴んだ画面が残る**経路になる。
    /// 端末で報告された落ち方に近づけるため、保存を効かせたまま（メモリ上ではなく）動かす。
    func testResetsAfterVisitingRecordsTab() {
        app.launchEnvironment.removeValue(forKey: "RAILANGYER_IN_MEMORY")
        app.launchEnvironment["RAILANGYER_RESET"] = "1"
        app.launch()

        startFromHome()
        walkOneTurn()

        // 記録タブを一度描かせてから戻る
        app.buttons["記録"].firstMatch.tap()
        XCTAssertTrue(app.state == .runningForeground)
        app.buttons["旅"].firstMatch.tap()
        XCTAssertTrue(app.buttons["サイコロを振る"].waitForExistence(timeout: 10))

        resetFromSchedules()

        XCTAssertEqual(app.state, .runningForeground, "アプリが落ちている")
        XCTAssertTrue(app.buttons["サイコロを振る"].waitForExistence(timeout: 10),
                      "リセット後に盤面へ戻れていない")

        app.buttons["記録"].firstMatch.tap()
        XCTAssertEqual(app.state, .runningForeground, "記録タブでアプリが落ちている")
    }

    /// 区間を2駅に縮めてゴールし、盤面の「記録を保存して新しい旅へ」を押す。
    ///
    /// クリア表示のまま記録を消す経路。**消したデータを掴んだ画面が残っていると落ちる**。
    func testResetsFromClearedBoard() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15), "ホームが出ていない")

        // 麻生 → 北34条 の2駅にして、1ターンでゴールさせる。
        // 区間は予定で決める（旅を始めるときに取り込まれる）
        planTwoStationJourney()

        startFromHome()
        walkOneTurn()

        let cleared = app.staticTexts["ゴールに到達しました"]
        XCTAssertTrue(cleared.waitForExistence(timeout: 10), "ゴールに到達できていない")

        let reset = app.buttons["記録を保存して新しい旅へ"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()

        XCTAssertEqual(app.state, .runningForeground, "アプリが落ちている")
        XCTAssertTrue(app.buttons["サイコロを振る"].waitForExistence(timeout: 10),
                      "リセット後に盤面へ戻れていない")
    }

    // MARK: - 補助

    /// ホームから旅を始めて、盤面が出るまで待つ
    private func startFromHome() {
        let start = app.buttons["startJourney"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "ホームが出ていない")
        start.tap()
        XCTAssertTrue(app.buttons["サイコロを振る"].waitForExistence(timeout: 15), "盤面が出ていない")
    }

    /// 1ターンぶん歩いて盤面へ戻る（出目は1に固定してあるので隣の駅で止まる）
    private func walkOneTurn() {
        app.buttons["サイコロを振る"].tap()

        let proceed = app.buttons["向かう"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"),
                               evaluatedWith: proceed)], timeout: 10)
        proceed.tap()

        let arrived = app.buttons["北34条 に到着した"]
        XCTAssertTrue(arrived.waitForExistence(timeout: 10), "到着のボタンが出ていない")
        arrived.tap()

        let next = app.buttons["次へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
    }

    /// ホーム → 予定 →「記録を保存して新しい旅へ」。
    /// 設定から移ってきた導線をそのままなぞる
    private func resetFromSchedules() {
        openSchedules()

        let reset = app.buttons["記録を保存して新しい旅へ"]
        for _ in 0..<6 where !reset.exists { app.swipeUp() }
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "予定にリセットのボタンが見つからない")
        XCTAssertTrue(reset.isEnabled, "歩いたのにリセットが押せない")
        reset.tap()
        app.buttons["保存して新しい旅へ"].tap()

        let close = app.buttons["閉じる"]
        if close.waitForExistence(timeout: 3) { close.tap() }
        app.buttons["旅"].firstMatch.tap()
    }

    /// 麻生 → 北34条 の予定を立てる。ホームから旅を始めるときに取り込まれる
    private func planTwoStationJourney() {
        openSchedules()

        let plus = app.buttons["plus"]
        if plus.exists {
            plus.tap()
        } else {
            let bar = app.navigationBars["予定"]
            bar.buttons.element(boundBy: bar.buttons.count - 1).tap()
        }
        XCTAssertTrue(app.navigationBars["予定を立てる"].waitForExistence(timeout: 5),
                      "予定の入力が開いていない")

        let goalPicker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'ゴール'")).firstMatch
        XCTAssertTrue(goalPicker.waitForExistence(timeout: 5), "予定にゴールの選択が無い")
        goalPicker.tap()
        app.buttons["北34条"].firstMatch.tap()

        let titleField = app.textFields["南北線を歩く"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "予定の名前の欄が見つからない")
        titleField.tap()
        titleField.typeText("2駅だけ歩く")

        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["2駅だけ歩く"].waitForExistence(timeout: 10),
                      "立てた予定が一覧に出ていない")

        app.buttons["閉じる"].tap()
    }

    /// ホームの「予定」を開く。盤面にいるときはホームへ戻ってから押す
    private func openSchedules() {
        let home = app.buttons["ホーム"].firstMatch
        if home.exists { home.tap() }

        let schedules = app.buttons["予定"].firstMatch
        XCTAssertTrue(schedules.waitForExistence(timeout: 10), "ホームに予定の入口が無い")
        schedules.tap()
        XCTAssertTrue(app.navigationBars["予定"].waitForExistence(timeout: 10), "予定が開いていない")
    }
}
