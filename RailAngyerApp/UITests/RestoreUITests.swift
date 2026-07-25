import XCTest
import CoreLocation

/// 中断・復帰（10_アプリ設計.md §5.3 / CM-06 / E-05）。
///
/// 歩いている最中にアプリが落ちても、出目と行き先を失わずに同じ画面へ戻れるか。
/// ver.1 の設計では出目が着地まで保存されず復元できなかったため、
/// `Turn` を振った時点で保存するようにした。その効き目をここで確かめる。
final class RestoreUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        // 現在地を始点に戻す。前のテストが残した位置のままだと、
        // 出発した瞬間に目的地の圏内にいて自動到着してしまう
        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: 43.1147, longitude: 141.3406))   // 麻生

        app = XCUIApplication()
        // 保存を効かせたまま初期状態から始めたいので、メモリ上の起動は使わない
        app.launchEnvironment["RAILANGYER_FIXED_DICE"] = "3"
        app.launchEnvironment["RAILANGYER_RESET"] = "1"
    }

    override func tearDown() {
        // 後続のテストに記録を持ち越さない
        app.launchEnvironment["RAILANGYER_RESET"] = "1"
        app.launch()
        app.terminate()
    }

    /// 移動中に強制終了しても、同じ駅へ向かう画面に戻る
    func testResumesWalkingAfterRelaunch() {
        app.launch()

        let rollButton = app.buttons["サイコロを振る"]
        XCTAssertTrue(rollButton.waitForExistence(timeout: 15), "盤面が出ていない")
        rollButton.tap()

        // 出目3なので 麻生(1) → 北18条(4)。通り道は 北34条・北24条
        XCTAssertTrue(app.staticTexts["北18条 まで"].waitForExistence(timeout: 10))
        let go = app.buttons["向かう"]
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: go)],
             timeout: 10)
        go.tap()

        let arrivalButton = app.buttons["北34条 に到着した"]
        XCTAssertTrue(arrivalButton.waitForExistence(timeout: 5))
        arrivalButton.tap()

        // 通り道の駅で一拍おく（ここで写真を撮れる）
        XCTAssertTrue(app.staticTexts["北34条 に到着"].waitForExistence(timeout: 5))
        app.buttons["次の駅へ"].tap()
        XCTAssertTrue(app.buttons["北24条 に到着した"].waitForExistence(timeout: 5))

        // ここで強制終了
        app.terminate()

        // 2回目はリセットせずに起動する
        app.launchEnvironment["RAILANGYER_RESET"] = "0"
        app.launch()

        // 盤面ではなく、続きの画面に戻ること
        XCTAssertTrue(app.buttons["北24条 に到着した"].waitForExistence(timeout: 15),
                      "移動中の状態が復元されていない")
        // 盤面は全画面フローの背後に残るため exists では判定できない。
        // 触れる状態かどうかで見る
        XCTAssertFalse(app.buttons["サイコロを振る"].isHittable,
                       "盤面に戻ってしまっている（進行中のターンが失われた）")
    }
}
