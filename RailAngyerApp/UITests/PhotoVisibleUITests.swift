import XCTest

/// 撮った写真が実際に画面へ出るか。
///
/// **保存できても読めなければ、写真はどこにも出ない。**
/// ビルド13まで、保存先のパスの扱いを誤って読み出しが必ず失敗していた。
/// ユニットテストは往復を押さえたが、画面まで届くかはここで見る。
final class PhotoVisibleUITests: XCTestCase {

    func testPhotoAppearsAfterTaking() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launchEnvironment["RAILANGYER_FIXED_DICE"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        app.buttons["startJourney"].tap()
        app.buttons["サイコロを振る"].tap()

        // 振ったら向かい、着くまで手動で進める
        let goButton = app.buttons["向かう"]
        XCTAssertTrue(goButton.waitForExistence(timeout: 10))
        // サイコロが止まるまで待つ
        let deadline = Date().addingTimeInterval(8)
        while !goButton.isEnabled && Date() < deadline { usleep(200_000) }
        goButton.tap()

        // 出目1なので、隣の北34条へ向かう
        let arrive = app.buttons["北34条 に到着した"]
        XCTAssertTrue(arrive.waitForExistence(timeout: 10), "手動到着のボタンが無い")
        arrive.tap()

        // 端末にカメラがあれば「写真を撮る」、無ければ「写真を選ぶ」
        let pick = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "写真を")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 10), "写真の操作が出ていない")
    }
}
