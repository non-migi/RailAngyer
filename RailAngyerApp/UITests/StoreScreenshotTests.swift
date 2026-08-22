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
        // **本物のサーバーに触らせない。** 見本のルームの資格情報は本物ではないので、
        // 本番へ投げると 401 が返り、「このルームから外れました」の断りが画面を覆う
        // （それがそのままストアに並ぶ絵になる）。届かない宛先にして、
        // ただの圏外として扱わせる
        app.launchEnvironment["RAILANGYER_API_BASE_URL"] = "https://127.0.0.1:9"

        // **どの言語で撮るかは外から渡す。** `xcodebuild` に
        // `TEST_RUNNER_SHOT_LOCALE=en` を渡すと、頭を落として届く。
        // アプリの言語は端末の設定ではなく `UserDefaults` の `appLanguage`（AppLanguage）
        // で決まるので、起動引数で直接そこへ入れる
        if let locale = ProcessInfo.processInfo.environment["SHOT_LOCALE"], !locale.isEmpty {
            app.launchArguments += ["-appLanguage", locale]
        }
    }

    func testShootsStoreScreenshots() {
        app.launch()

        let start = app.buttons["startJourney"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "ホームが出ていない")
        // 初回案内が残っていたら閉じる（環境変数で出ない想定だが、念のため）
        closeSheet()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "ホームが出ていない")

        start.tap()
        // 予定があれば選ぶ画面が挟まる。出たらそのまま始める
        let pickPlan = app.buttons["いまの設定のまま始める"]
        if pickPlan.waitForExistence(timeout: 3) { pickPlan.tap() }

        XCTAssertTrue(app.buttons["rollDice"].waitForExistence(timeout: 20), "盤面が出ていない")

        // **数字が 0 のままの画面は撮らない。** ストアに並ぶ絵で
        // 「0駅・0秒・記録なし」が続くと、動いていないアプリに見える。
        // 実際に何駅か歩いてから撮る
        startFromFirstStation()
        playOneTurn()
        playOneTurn()

        shoot("02-board")

        app.buttons["journeyMissions"].firstMatch.tap()
        if app.navigationBars.firstMatch.waitForExistence(timeout: 5) { shoot("03-missions") }
        closeSheet()

        // **ふりかえりは盤面にしか無い。** 歩いている最中の全画面から直接は開けないので、
        // いったん盤面へ戻る
        let toBoard = app.buttons["minimizeTurn"]
        if toBoard.waitForExistence(timeout: 3) { toBoard.tap() }

        let summary = app.buttons["openSummary"]
        if summary.waitForExistence(timeout: 8) {
            summary.firstMatch.tap()
            if app.navigationBars.firstMatch.waitForExistence(timeout: 8) { shoot("04-summary") }
            closeSheet()
        }

        // **ホームは最後に撮る。** 歩く前だと「0駅・0秒・記録なし」しか写らない。
        // 歩いたあとなら、現在地も時間も記録も入った顔になる
        app.tabBars.buttons.element(boundBy: 0).tap()
        if start.waitForExistence(timeout: 8) { shoot("01-home") }
    }

    /// スタート駅に着いたことにする（1駅目として数える）
    private func startFromFirstStation() {
        let arrived = app.buttons["boardSecondaryAction"]
        if arrived.firstMatch.waitForExistence(timeout: 5) { arrived.firstMatch.tap() }
    }

    /// 振る → 止める → 向かう → 着く、を1回。
    /// 位置情報を動かさないので、着いたことは手で押して伝える。
    ///
    /// **文字では探さない。** 9言語ぶん撮るので、局面ごとに変わる文言ではなく
    /// `primaryAction`（この画面の主操作）を押し続ける形にしてある
    private func playOneTurn() {
        let roll = app.buttons["rollDice"]
        guard roll.waitForExistence(timeout: 10) else { return }
        roll.tap()

        for _ in 0..<10 {
            if app.buttons["rollDice"].exists { return }   // 盤面へ戻ってきた
            let primary = app.buttons["primaryAction"]
            if primary.waitForExistence(timeout: 8), primary.isHittable {
                primary.tap()
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
