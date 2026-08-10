import XCTest

/// 予定の共有。
///
/// **押しても何も起きない**という報告があった。
/// テレメトリ用に足した `.simultaneousGesture` が `ShareLink` の
/// 反応を奪っていないかを確かめる（コースの行で同じ種類の不具合があった）。
final class ShareUITests: XCTestCase {

    func testShareSheetOpens() {
        let app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15))
        // 端末に前回の言語設定が残ることがあるので、表示名では探さない
        app.buttons.matching(NSPredicate(format: "label IN %@", ["予定", "Plans"]))
            .firstMatch.tap()
        let bar = app.navigationBars.matching(
            NSPredicate(format: "identifier IN %@", ["予定", "Plans"])).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "予定の画面が開かない")

        // 予定を1件立てる（名前は既定で入っている）
        app.buttons["plus"].tap()
        let save = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["保存", "Save"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8), "保存が出ない")
        save.tap()

        let share = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["この予定を共有する", "Share this plan"])).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 8), "共有のボタンが無い")
        share.tap()

        // **共有シートが本当に前に出たかを見る。**
        // 一覧そのものを数えないよう、共有シート特有の要素で判定する
        let activity = app.otherElements["ActivityListView"]
        let copyAction = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "コピー", "Copy")).firstMatch
        let appeared = activity.waitForExistence(timeout: 10)
            || copyAction.waitForExistence(timeout: 3)
        XCTAssertTrue(appeared, "共有シートが出ていない（押しても何も起きない）")
    }
}
