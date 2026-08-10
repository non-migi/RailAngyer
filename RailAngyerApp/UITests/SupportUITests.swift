import XCTest

/// 開発者への応援（SC-28）。
///
/// **買っても何も起こらない**ので、確かめるのは「たどり着けること」と
/// 「3段の金額がちゃんと出ること」。金額は StoreKit の設定ファイルから来る。
final class SupportUITests: XCTestCase {

    /// 設定は縦に長い。見つかるまで送る
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication,
                          swipes: Int = 8) -> XCUIElement {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return element }
            app.swipeUp()
        }
        return element
    }

    func testSupportTiersAreListed() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        app.buttons["設定"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 8))

        let support = scrollTo(app.buttons["supportDeveloper"], in: app)
        XCTAssertTrue(support.exists, "応援の導線が無い")
        support.tap()

        XCTAssertTrue(app.navigationBars["開発者を応援する"].waitForExistence(timeout: 8))

        // **金額の並びはここでは確かめられない。**
        // 商品は App Store Connect（または Xcode の Debug > StoreKit で
        // `RailAngyerApp/StoreKit/Tips.storekit` を選ぶ）から来るため、
        // `xcodebuild` のテスト実行では空になる。
        // ここで押さえるのは「たどり着けること」と「商品が無くても壊れないこと」

        // 何も解放しないことを、画面で先に明言していること
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "機能が増えたり")).firstMatch
            .waitForExistence(timeout: 5),
            "何も起こらないことを書いていない")

        // 商品が取れないときは、理由を出して静かに畳む（登録前はこの状態になる）
        let unavailable = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "応援を受け取れません")).firstMatch
        let listed = app.staticTexts["コーヒー1杯ぶん"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10) || listed.exists,
                      "商品が無いのに、理由も一覧も出ていない")

        if listed.exists {
            for caption in ["コーヒー1杯ぶん", "ランチ1回ぶん", "しっかり応援"] {
                XCTAssertTrue(app.staticTexts[caption].exists, "「\(caption)」が出ていない")
            }
        }
    }

    func testAttributionIsReachable() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        app.buttons["設定"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 8))

        let row = scrollTo(app.buttons["データの出典"], in: app)
        XCTAssertTrue(row.exists, "出典の導線が無い")
        row.tap()

        XCTAssertTrue(app.navigationBars["データの出典"].waitForExistence(timeout: 8))
        // 出典表示は義務。文言が消えていないこと
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "OpenStreetMap")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "国土数値情報")).firstMatch.exists)
    }
}
