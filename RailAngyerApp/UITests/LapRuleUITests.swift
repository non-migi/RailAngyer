import XCTest

/// 環状線の一周モードでのルール保存。
///
/// 一周は**スタートとゴールが同じ駅になるのが正しい**。
/// これを「別の駅にしてください」の条件で弾いていたため、
/// 一周モードでは最大出目を変えても保存できず、黙って元に戻っていた。
///
/// 遊び方のルールは端末の設定から予定へ移ったので、ここも予定を立てて確かめる。
final class LapRuleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }

    func testSavesDiceMaxWhileLapping() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15), "ホームが出ていない")

        openScheduleDraft()

        // 環状のコースにしないと「一周する」が出ない。
        // コースは国 → 都道府県 → 路線 の3段をたどって選ぶ
        let coursePicker = app.buttons["coursePicker"]
        XCTAssertTrue(coursePicker.waitForExistence(timeout: 5), "コースの選択が見つからない")
        coursePicker.tap()
        tapRow("日本", missing: "国の一覧が出ていない")
        tapRow("東京都", missing: "都道府県の一覧が出ていない")
        tapRow("山手線", missing: "路線の一覧が出ていない")

        // 行の真ん中は文字の上で、押しても切り替わらない。スイッチそのものを押す
        let lap = app.switches["一周する"]
        XCTAssertTrue(lap.waitForExistence(timeout: 5), "環状のコースなのに一周の設定が出ていない")
        lap.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(lap.value as? String, "1", "一周モードに入れていない")

        // 名前は先に入れる。詳細設定まで下ると、この欄は画面の外へ出てしまう
        let titleField = app.textFields["南北線を歩く"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "予定の名前の欄が見つからない")
        titleField.tap()
        titleField.typeText("山手線を一周")
        // **キーボードは必ず畳む。** 出したままだと、この先の指の動きを鍵盤が拾って
        // 名前の欄に文字が入り続ける
        titleField.typeText("\n")
        XCTAssertEqual(titleField.value as? String, "山手線を一周", "名前の欄に余計な文字が入っている")

        // 最大出目は「詳細設定」の中。決めなくても遊べるものは畳んである
        expandDetailSection()
        let dice = diceStepper()
        XCTAssertTrue(scrollUntilUsable(dice), "最大出目の設定が見つからない")
        dice.buttons["Increment"].tap()   // 6 → 7

        let save = app.buttons["保存"]
        XCTAssertTrue(save.isEnabled, "一周モードで保存できない（スタート＝ゴールで弾かれている）")
        save.tap()

        // 一覧に、一周であることと保存した最大出目が出ていること。
        // 弾かれていれば予定そのものが立たず、直っていなければ出目が元のまま出る
        XCTAssertTrue(app.staticTexts["山手線を一周"].waitForExistence(timeout: 10),
                      "一周の予定が立てられていない")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'から一周'")).firstMatch.exists,
                      "一周として保存されていない")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'サイコロ1〜7'")).firstMatch.exists,
                      "一周モードで最大出目が保存されていない")
    }

    // MARK: - 補助

    /// ホームの「予定」から、新しい予定の入力を開く
    private func openScheduleDraft() {
        let schedules = app.buttons["予定"].firstMatch
        XCTAssertTrue(schedules.waitForExistence(timeout: 10), "ホームに予定の入口が無い")
        schedules.tap()
        XCTAssertTrue(app.navigationBars["予定"].waitForExistence(timeout: 10), "予定が開いていない")

        let plus = app.buttons["plus"]
        if plus.exists {
            plus.tap()
        } else {
            let bar = app.navigationBars["予定"]
            bar.buttons.element(boundBy: bar.buttons.count - 1).tap()
        }
        XCTAssertTrue(app.navigationBars["予定を立てる"].waitForExistence(timeout: 5),
                      "予定の入力が開いていない")
    }

    /// コースをたどる一覧の行。行の見出しは「日本, 7 路線」のように続くので前方一致で引く
    private func tapRow(_ prefix: String, missing message: String) {
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), message)
        row.tap()
    }

    /// 畳まれた「詳細設定」を開く。長い入力なので、見えるところまで下ってから押す
    private func expandDetailSection() {
        let insideDetail = app.switches["サイコロを使う"]
        for _ in 0..<10 {
            if insideDetail.exists { return }             // すでに開いている
            let detail = detailDisclosure()
            if scrollUntilUsable(detail, tries: 1) {
                detail.tap()
                if insideDetail.waitForExistence(timeout: 2) { return }
            }
            scrollDown()
        }
        XCTFail("詳細設定を開けない\n\(app.debugDescription)")
    }

    /// DisclosureGroup の見出し。ボタンとして出ないことがあるので文字でも探す
    private func detailDisclosure() -> XCUIElement {
        let button = app.buttons["詳細設定"]
        return button.exists ? button : app.staticTexts["詳細設定"]
    }

    /// 画面の端に半分だけ出ている要素は押しても効かない。
    /// **真ん中あたりに来るまで送ってから**触る
    @discardableResult
    private func scrollUntilUsable(_ element: XCUIElement, tries: Int = 8) -> Bool {
        let height = app.frame.height
        for _ in 0..<tries {
            if element.exists && element.isHittable
                && element.frame.minY > 100 && element.frame.maxY < height - 90 {
                return true
            }
            scrollDown()
        }
        return element.exists && element.isHittable
    }

    /// 最大出目のステッパー。ラベルで引けないときは詳細設定の先頭を取りにいく
    private func diceStepper() -> XCUIElement {
        let labelled = app.steppers.matching(
            NSPredicate(format: "label BEGINSWITH '最大出目'")).firstMatch
        if labelled.exists { return labelled }
        return app.steppers.element(boundBy: 0)
    }

    /// 入力を下へ送る。
    /// 集合日時のカレンダーが縦の指の動きを吸うことがあるので、画面の下寄りから始める
    private func scrollDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
