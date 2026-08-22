import Foundation
import Testing
@testable import RailAngyerCore

/// 距離と速さの計算。
///
/// 地図の色分けと「何分/km」の表示がここに乗るので、
/// **境目の値でどちらに転ぶか**を決めておく。
struct PaceTests {

    @Test("札幌駅から大通までの距離が実際と近い")
    func distanceMatchesReality() {
        // さっぽろ(43.0682, 141.3505) 〜 大通(43.0611, 141.3506)。実際は約800m
        let d = Geo.distanceMeters(lat1: 43.0682, lon1: 141.3505,
                                   lat2: 43.0611, lon2: 141.3506)
        #expect((700.0...900.0).contains(d), "計算値: \(Int(d))m")
    }

    @Test("同じ地点なら0メートル")
    func sameCoordinateIsZero() {
        #expect(Geo.distanceMeters(lat1: 43.06, lon1: 141.35, lat2: 43.06, lon2: 141.35) == 0)
    }

    @Test("1kmを12分で歩けば12分/km")
    func computesPace() throws {
        let pace = Pace(meters: 1000, seconds: 720)

        #expect(pace.minutesPerKilometer == 12)
        #expect(pace.category == .normal)
        #expect(pace.text(locale: Locale(identifier: "ja_JP")) == "12分/km")
        #expect(try #require(pace.kilometersPerHour) == 5)
    }

    @Test("秒が半端なときも読める形にする")
    func formatsFractionalPace() {
        // 1km を 11分30秒
        #expect(Pace(meters: 1000, seconds: 690).text(locale: Locale(identifier: "ja_JP")) == "11分30秒/km")
    }

    @Test("止まっていたり距離が0なら求めない")
    func undefinedPace() {
        #expect(Pace(meters: 0, seconds: 600).minutesPerKilometer == nil)
        #expect(Pace(meters: 1000, seconds: 0).minutesPerKilometer == nil)
        #expect(Pace(meters: 1000, seconds: 0).text == nil)
    }

    @Test("速さの区分は境目で切り替わる", arguments: [
        (9.9, PaceCategory.fast),
        (10.0, PaceCategory.normal),     // 10分/km ちょうどは「ふつう」
        (13.9, PaceCategory.normal),
        (14.0, PaceCategory.slow),       // 14分/km ちょうどは「ゆっくり」
        (20.0, PaceCategory.slow)
    ])
    func categoryBoundaries(_ minutes: Double, _ expected: PaceCategory) {
        #expect(PaceCategory(minutesPerKilometer: minutes) == expected)
    }

    @Test("時間の表し方")
    func durationText() {
        // **言語を決めてから確かめる。** 単位は端末の言語で変わるので、
        // 固定しないと英語の Mac で流したときに落ちる
        let ja = Locale(identifier: "ja_JP")
        #expect(DurationText.text(45, locale: ja) == "45秒")
        #expect(DurationText.text(600, locale: ja) == "10分")
        #expect(DurationText.text(3_900, locale: ja) == "1時間5分")
        #expect(DurationText.clock(3_930) == "1:05:30")
        #expect(DurationText.clock(90) == "1:30")
    }

    @Test("単位はその言語の言い方になる")
    func durationTextFollowsLocale() {
        // 直書きの「秒」に戻ると、英語で開いても日本語の単位が出る（実際に出ていた）
        let text = DurationText.text(45, locale: Locale(identifier: "en_US"))
        #expect(!text.contains("秒"), "英語なのに日本語の単位が出ている: \(text)")
        #expect(text.contains("45"))
        #expect(DurationText.text(45, locale: Locale(identifier: "ja_JP")).contains("秒"))
    }
}
