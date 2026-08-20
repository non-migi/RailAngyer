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

        // **数字が 0 のままの画面は撮らない。** ストアに並ぶ絵で
        // 「0駅・0秒・記録なし」が続くと、動いていないアプリに見える。
        // 実際に何駅か歩いてから撮る
        startFromFirstStation()
        playOneTurn()
        playOneTurn()

        shoot("02-board")

        app.buttons["旅のお題"].firstMatch.tap()
        if app.navigationBars.firstMatch.waitForExistence(timeout: 5) { shoot("03-missions") }
        closeSheet()

        // **ふりかえりは盤面にしか無い。** 歩いている最中の全画面から直接は開けないので、
        // いったん盤面へ戻る
        let toBoard = app.buttons["盤面へ"]
        if toBoard.waitForExistence(timeout: 3) { toBoard.tap() }

        let summary = app.buttons["ふりかえり"]
        if summary.waitForExistence(timeout: 8) {
            summary.firstMatch.tap()
            if app.navigationBars["ふりかえり"].waitForExistence(timeout: 8) { shoot("04-summary") }
            closeSheet()
        }
    }

    /// スタート駅に着いたことにする（1駅目として数える）
    private func startFromFirstStation() {
        let arrived = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "に到着した"))
        if arrived.firstMatch.waitForExistence(timeout: 5) { arrived.firstMatch.tap() }
    }

    /// 振る → 止める → 向かう → 着く、を1回。
    /// 位置情報を動かさないので、着いたことは手で押して伝える
    private func playOneTurn() {
        guard app.buttons["サイコロを振る"].waitForExistence(timeout: 10) else { return }
        app.buttons["サイコロを振る"].tap()

        let stop = app.buttons["サイコロを止める"]
        if stop.waitForExistence(timeout: 10) { stop.tap() }

        let go = app.buttons["向かう"]
        if go.waitForExistence(timeout: 10) { go.tap() }

        // 「◯◯ に到着した」「次の駅へ」を、盤面へ戻るまで押し続ける
        for _ in 0..<8 {
            if app.buttons["サイコロを振る"].exists { return }
            let arrived = app.buttons.matching(NSPredicate(
                format: "label ENDSWITH %@ OR label == %@", "に到着した", "次の駅へ"))
            if arrived.firstMatch.waitForExistence(timeout: 8) {
                arrived.firstMatch.tap()
            } else if app.buttons["達成した"].exists {
                app.buttons["達成した"].tap()
            } else if app.buttons["ミッションを引く"].exists {
                app.buttons["ミッションを引く"].tap()
            } else {
                return
            }
        }
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
