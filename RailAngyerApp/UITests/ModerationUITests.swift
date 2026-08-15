import XCTest

/// 利用者が作ったもの（UGC）への対処が、**画面から辿れる**こと。
///
/// App Store ガイドライン 1.2 の要件で、審査担当が実際に触る導線でもある。
/// ここは文言だけでなく「そもそも画面に出るか」が問われるため、
/// ユニットテストでは守れない（`ModerationTests` は仕組みの側を見ている）。
///
/// 仲間はサーバーから取り込んで初めて増えるので、`RAILANGYER_SAMPLE_ROOM` で
/// 参加済み・仲間2人・自分が作成者の状態を作ってから確かめる
final class ModerationUITests: XCTestCase {

    private func launchJoined() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launchEnvironment["RAILANGYER_SAMPLE_ROOM"] = "1"
        // **通信は出さない。** 本物のサーバーに触ると、でたらめなルームIDに
        // 401 が返って資格情報ごと畳まれ、画面が参加前に戻ってしまう。
        // 届かない宛先にして、圏外と同じ扱いにする
        app.launchEnvironment["RAILANGYER_API_BASE_URL"] = "https://127.0.0.1:9"
        app.launch()
        return app
    }

    /// ホームの「いまのルーム」からメンバー一覧へ
    private func openRoom(_ app: XCUIApplication) {
        let card = app.buttons["roomCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "ルームの入口が無い")
        card.tap()
        XCTAssertTrue(app.navigationBars["みんなで遊ぶ"].waitForExistence(timeout: 10),
                      "ルームの画面が開かない")
    }

    /// 仲間の行の操作メニュー。名前は伏せられると変わるので、そのときは呼び分ける
    private func memberMenu(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["\(name) の操作"]
    }

    func testReportAndBlockAreReachableForOtherMembers() {
        let app = launchJoined()
        openRoom(app)

        let menu = memberMenu(app, "ケンタ")
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "仲間の操作メニューが無い")
        menu.tap()

        // 利用者が作るものは写真・お題・表示名の3つ。**表示名にも通報の口が要る**
        XCTAssertTrue(app.buttons["この表示名を通報する"].waitForExistence(timeout: 5),
                      "表示名の通報が無い（ガイドライン1.2）")
        XCTAssertTrue(app.buttons["この人の投稿を非表示にする"].exists,
                      "見たくない人を伏せる口が無い")
    }

    func testBlockingHidesTheDisplayName() {
        let app = launchJoined()
        openRoom(app)

        memberMenu(app, "ケンタ").tap()
        app.buttons["この人の投稿を非表示にする"].tap()

        // 表示名も本人が決める文字なので、伏せたら名前ごと出さない
        XCTAssertTrue(app.staticTexts["非表示にした人"].waitForExistence(timeout: 5),
                      "表示名が伏せられていない")
        XCTAssertFalse(app.staticTexts["ケンタ"].exists, "伏せたはずの表示名が残っている")
        XCTAssertTrue(app.staticTexts["投稿を非表示中"].exists, "伏せている印が出ていない")

        // 伏せたあとも、解除の口は残っていること（戻せないと閉じ込めになる）
        memberMenu(app, "非表示にした人").tap()
        XCTAssertTrue(app.buttons["投稿の非表示を解除する"].waitForExistence(timeout: 5),
                      "解除できない")
    }

    func testKickConfirmationSaysItCannotBeUndone() {
        let app = launchJoined()
        openRoom(app)

        memberMenu(app, "ケンタ").tap()
        let kick = app.buttons["ルームから外す"]
        XCTAssertTrue(kick.waitForExistence(timeout: 5), "作成者なのに外す口が無い")
        kick.tap()

        // **戻せないことを、押す前に言う。**
        // サーバー側は写真の実体・お題・出欠まで消すので、
        // 「入り直せます」だけでは戻ると誤解される
        let warning = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "元には戻せません")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "取り消せない旨の断りが無い")
    }
}
