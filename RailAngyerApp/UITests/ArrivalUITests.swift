import XCTest
import CoreLocation

/// 位置情報による到着判定を、実際に「歩かせて」確かめる（10_アプリ設計.md §6 / §7）。
///
/// シミュレータの現在地を `XCUIDevice.shared.location` で動かし、
/// 駅の半径150mに入った時点でアプリが自動で先へ進むかを見る。
/// 出目は環境変数で1に固定し、行き先を一意にしている。
final class ArrivalUITests: XCTestCase {

    /// 南北線の座標（RailAngyerCore の同梱マスタと同じ値）
    private let asabu = CLLocationCoordinate2D(latitude: 43.10834, longitude: 141.33848)
    private let kita34 = CLLocationCoordinate2D(latitude: 43.100105, longitude: 141.34213)

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false

        // 位置情報の許可を聞かれたら許す。**許可が無いと自動到着は起きない。**
        // シミュレータで一度断った状態が残っていると、この確認そのものが出なくなる。
        // そのときは端末側の記録を戻してから流す：
        //   xcrun simctl privacy booted grant location-always com.non-migi.RailAngyerApp
        addUIInterruptionMonitor(withDescription: "位置情報の許可") { alert in
            for label in ["Appの使用中は許可", "常に許可", "1度だけ許可",
                          "Allow While Using App", "Allow Once"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }

        app = XCUIApplication()
        app.launchEnvironment["RAILANGYER_FIXED_DICE"] = "1"   // 必ず1駅進む
        app.launchEnvironment["RAILANGYER_IN_MEMORY"] = "1"    // 毎回まっさらな状態から
        // 通知の許可ダイアログは操作を塞ぐ。ここでの検証対象ではないので出さない
        app.launchEnvironment["RAILANGYER_NO_NOTIF_PROMPT"] = "1"
    }


    /// 麻生から北34条まで歩くと、半径に入った時点で自動的に到着になる
    func testWalkingIntoRadiusTriggersArrival() {
        setLocation(asabu)
        app.launch()

        // 盤面 → サイコロ
        rollFromBoard()

        // **止めるまで行き先は分からない**（SC-05）。ここが今回の演出の主眼
        XCTAssertFalse(app.staticTexts["北34条 まで"].exists,
                       "サイコロを止める前から行き先が見えている")
        stopDice()

        // 着地駅の告知（SC-06）。通り道が無いので「となりの駅です」
        XCTAssertTrue(app.staticTexts["北34条 まで"].waitForExistence(timeout: 10),
                      "着地駅の告知が出ていない")
        attach(name: "dice")   // 転がり終わったサイコロの目視確認用
        tapGo()

        // ナビ（SC-07）。現在地から目的地までの距離が出る
        XCTAssertTrue(app.staticTexts["北34条"].waitForExistence(timeout: 5))
        let arrivalButton = app.buttons["北34条 に到着した"]
        XCTAssertTrue(arrivalButton.exists, "手動到着のボタンが常に置かれていること（E-01）")

        // まだ圏外なので、勝手に進んではいけない
        XCTAssertFalse(app.staticTexts["北34条 に到着"].exists, "圏外なのに到着している")

        // 経路の取得を待って画面を記録する（地図と経路線の目視確認用）
        _ = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '徒歩 約'"))
            .firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 3)   // 地図の描画が追いつくのを待つ
        attach(name: "walking")

        // 半径150mの外側（約300m手前）まで近づく → まだ到着しない
        setLocation(interpolate(from: asabu, to: kita34, fraction: 0.68))
        XCTAssertFalse(app.staticTexts["北34条 に到着"].waitForExistence(timeout: 3),
                       "半径の外で到着してしまっている")

        // 駅に入る → 自動的に到着になる
        setLocation(kita34)
        XCTAssertTrue(app.staticTexts["北34条 に到着"].waitForExistence(timeout: 15),
                      "半径に入っても到着にならない")
    }

    /// 位置情報が無くても、手動で到着させれば進行が止まらない（E-01）
    func testManualArrivalWorks() {
        setLocation(asabu)
        app.launch()

        rollFromBoard()
        proceedFromAnnouncement()

        let arrivalButton = app.buttons["北34条 に到着した"]
        XCTAssertTrue(arrivalButton.waitForExistence(timeout: 5))
        arrivalButton.tap()

        XCTAssertTrue(app.staticTexts["北34条 に到着"].waitForExistence(timeout: 5),
                      "手動到着で先へ進めていない")
    }

    // MARK: - 補助

    /// 画面をテスト結果に残す。
    /// アニメーションや地図の描画は、テストの真偽だけでは確認できないため
    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func setLocation(_ coordinate: CLLocationCoordinate2D) {
        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private func interpolate(from: CLLocationCoordinate2D,
                             to: CLLocationCoordinate2D,
                             fraction: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction)
    }

    /// 盤面が出るのを待ってからサイコロを振る。
    /// 起動直後はマスタの投入が走るため、待たずに叩くと取りこぼす
    private func rollFromBoard() {
        let startButton = app.buttons["startJourney"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15), "ホームが出ていない")
        startButton.tap()

        // 旅を始めると、アプリは「常に許可」への引き上げを聞くことがある
        // （すでに「使用中のみ」が下りている場合。iOS は入れ直した直後などに出す）。
        // **待つだけでは割り込みの監視は働かない。** 画面に一度触れて閉じさせる
        let rollButton = app.buttons["サイコロを振る"]
        if !rollButton.waitForExistence(timeout: 10) {
            app.tap()
            XCTAssertTrue(rollButton.waitForExistence(timeout: 10), "盤面が出ていない")
        }
        rollButton.tap()
    }

    /// 着地駅の告知から先へ進む。
    /// **サイコロは押して止める**。止めてから、収まりきるのを待って「向かう」を押す
    private func proceedFromAnnouncement() {
        stopDice()
        tapGo()
    }

    /// 止めたあとの「向かう」。サイコロが収まりきるまで押せないので、有効になるのを待つ
    private func tapGo() {
        let button = app.buttons["向かう"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: button)
        wait(for: [enabled], timeout: 10)
        button.tap()
    }

    /// 転がっているサイコロを止める（SC-05）
    private func stopDice() {
        let stop = app.buttons["サイコロを止める"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "サイコロを止めるボタンが無い")
        stop.tap()
    }
}
