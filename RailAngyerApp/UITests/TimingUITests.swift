import XCTest
import CoreLocation

/// 時間とペースが、歩行中だけでなく盤面・駅詳細・ふりかえりにもつながることを確認する。
final class TimingUITests: XCTestCase {

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

    func testShowsTimingAcrossScreens() {
        app.launch()

        let startButton = app.buttons["startJourney"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15), "ホームが出ていない")
        startButton.tap()
        let roll = app.buttons["サイコロを振る"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15))
        roll.tap()

        let stop = app.buttons["サイコロを止める"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "サイコロを止めるボタンが無い")
        stop.tap()

        let proceed = app.buttons["向かう"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: proceed)
        wait(for: [enabled], timeout: 10)
        proceed.tap()

        XCTAssertTrue(app.staticTexts["今回の記録"].waitForExistence(timeout: 5))
        app.buttons["北34条 に到着した"].tap()

        // 初期お題は入れない仕様。お題がない駅では、そのまま次へ進む。
        let next = app.buttons["次へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()

        XCTAssertTrue(roll.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '合計 '"))
            .firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '平均 '"))
            .firstMatch.exists)

        // 表示方式は AppStorage に残る。単独実行でも全スイートの後でも地図から確認する。
        let showMap = app.buttons["地図で見る"]
        if showMap.exists { showMap.tap() }
        let showList = app.buttons["一覧で見る"]
        XCTAssertTrue(showList.waitForExistence(timeout: 5))
        attach(name: "時間とペース・盤面")

        showList.tap()
        let station = app.buttons.containing(.staticText, identifier: "北34条").firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 5))
        station.tap()
        XCTAssertTrue(app.navigationBars["北34条"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["麻生から"].exists)
        attach(name: "時間とペース・駅詳細")
        app.buttons["閉じる"].tap()

        app.buttons["ふりかえり"].tap()
        XCTAssertTrue(app.staticTexts["時間の内訳"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["合計"].exists)
        XCTAssertTrue(app.staticTexts["移動"].exists)
        XCTAssertTrue(app.staticTexts["ミッション"].exists)
        XCTAssertTrue(app.staticTexts["その他"].exists)
        attach(name: "時間とペース・ふりかえり")
    }

    private func attach(name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
