import XCTest

/// App Store に出すスクリーンショットを撮る。
///
/// **ふつうのテストではない。** 何かを確かめるためではなく、
/// `tools/shoot-screenshots.sh` から呼ばれて**絵を作るため**に走る。
/// 手で撮ると端末サイズを間違えて弾かれる（1320×2868 でないと通らない）ので、
/// 6.9インチのシミュレータで撮ってそのまま出す。
///
/// 撮った絵は添付として結果バンドルに残り、スクリプトが取り出す。
final class StoreScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // 仲間が居るルームを作っておく。1人だけの画面では、このアプリの
        // 「みんなで歩く」ところが写らない
        app.launchEnvironment["RAILANGYER_SAMPLE_ROOM"] = "1"
        app.launchEnvironment["RAILANGYER_SAMPLE_MISSIONS"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        // 初回の「遊び方」がホームを覆う。撮るときは邪魔なので出さない
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
    }

    func testShootsStoreScreenshots() {
        app.launch()

        let start = app.buttons["startJourney"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "ホームが出ていない")
        // 初回案内が残っていたら閉じる（環境変数で出ない想定だが、念のため）
        closeSheet()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "ホームが出ていない")
        shoot("01-home")

        start.tap()
        // 予定があれば選ぶ画面が挟まる。出たらそのまま始める
        let pickPlan = app.buttons["いまの設定のまま始める"]
        if pickPlan.waitForExistence(timeout: 3) { pickPlan.tap() }

        XCTAssertTrue(app.buttons["サイコロを振る"].waitForExistence(timeout: 20), "盤面が出ていない")
        shoot("02-board")

        app.buttons["旅のお題"].firstMatch.tap()
        if app.navigationBars.firstMatch.waitForExistence(timeout: 5) { shoot("03-missions") }
        closeSheet()

        app.buttons["ふりかえり"].firstMatch.tap()
        if app.navigationBars["ふりかえり"].waitForExistence(timeout: 5) { shoot("04-summary") }
        closeSheet()
    }

    /// 1枚撮って添付する。名前はファイル名になる
    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func closeSheet() {
        for label in ["閉じる", "やめる", "まだ続ける"] {
            let button = app.buttons[label]
            if button.exists && button.isHittable { button.tap(); return }
        }
        app.swipeDown(velocity: .fast)
    }
}
