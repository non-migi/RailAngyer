import XCTest

/// 予定まわり。
///
/// **立てた予定がその場で一覧に出る**ことを確かめる。
/// 端末の保存は即時なので、待たされてよいのは仲間への共有だけ。
final class ScheduleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }

    func testNewScheduleAppearsImmediately() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15), "ホームが出ていない")

        app.buttons["予定"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["予定"].waitForExistence(timeout: 5))

        addButton().tap()
        // 名前は既定で入っている。付け直せることも一緒に確かめる
        let titleField = app.textFields.firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeKey("a", modifierFlags: .command)      // 既定の名前を選んで置き換える
        titleField.typeText("土曜に歩く")
        app.buttons["保存"].tap()

        // 保存した瞬間に一覧へ出ていること（同期を待たない）
        XCTAssertTrue(app.staticTexts["土曜に歩く"].waitForExistence(timeout: 3),
                      "立てた予定が一覧に出ていない")

        // 予定の段階からお題を書ける
        let writeMissions = app.buttons["この予定のお題を書く"]
        XCTAssertTrue(writeMissions.waitForExistence(timeout: 5))
        writeMissions.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'あなたのお題'")).firstMatch
            .waitForExistence(timeout: 5), "予定からお題の画面を開けない")
    }

    /// **開いた直後から保存できること。**
    ///
    /// 名前が空だと保存は押せない。ところが地図を足したせいで
    /// 名前の入力欄が画面の外へ押し出され、「押せない理由が見えない」状態になっていた
    /// （＝予定が立てられない）。名前を最初から入れておくことで直している。
    func testSaveIsEnabledAsSoonAsDraftOpens() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15), "ホームが出ていない")

        app.buttons["予定"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["予定"].waitForExistence(timeout: 5))
        addButton().tap()

        XCTAssertTrue(app.navigationBars["予定を立てる"].waitForExistence(timeout: 5))
        // **スクロールも入力もせずに**押せること
        XCTAssertTrue(app.buttons["保存"].isEnabled, "開いた直後に保存が押せない")

        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["南北線を歩く"].waitForExistence(timeout: 5),
                      "既定の名前で立てた予定が一覧に出ていない")
    }

    /// **国 → 都道府県 → 路線 とたどって選んだあとでも、予定が立てられること。**
    ///
    /// 平らな `Picker` を3段のたどりに変えたので、
    /// 「選んだのに戻れない／保存できない」状態になっていないかを見る。
    func testCanSaveAfterPickingCourseByRegion() {
        app.launch()
        XCTAssertTrue(app.buttons["startJourney"].waitForExistence(timeout: 15), "ホームが出ていない")

        app.buttons["予定"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["予定"].waitForExistence(timeout: 5))
        addButton().tap()
        XCTAssertTrue(app.navigationBars["予定を立てる"].waitForExistence(timeout: 5))

        app.buttons["coursePicker"].tap()

        XCTAssertTrue(app.navigationBars["コースを選ぶ"].waitForExistence(timeout: 5),
                      "コースを選ぶ画面が開かない")
        tapCell(startingWith: "日本")
        tapCell(startingWith: "大阪府")
        tapCell(startingWith: "阪急京都本線")

        // 選んだら入力へ戻ること
        XCTAssertTrue(app.navigationBars["予定を立てる"].waitForExistence(timeout: 5),
                      "路線を選んだあと入力画面へ戻らない")
        let row = app.buttons["coursePicker"]
        XCTAssertTrue(row.label.contains("阪急京都本線"),
                      "選んだ路線が入力画面に出ていない: \(row.label)")

        let save = app.buttons["保存"]
        XCTAssertTrue(save.isEnabled, "コースを選んだのに保存できない")
        save.tap()

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "阪急京都本線")).firstMatch
            .waitForExistence(timeout: 5), "立てた予定が一覧に出ていない")
    }

    private func tapCell(startingWith text: String) {
        let cell = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "「\(text)」の行が出ない")
        cell.tap()
    }

    /// ＋ボタン。ラベルが付かないことがあるので、右上のボタンを取りにいく
    private func addButton() -> XCUIElement {
        let plus = app.buttons["plus"]
        if plus.exists { return plus }
        let bar = app.navigationBars["予定"]
        return bar.buttons.element(boundBy: bar.buttons.count - 1)
    }
}
