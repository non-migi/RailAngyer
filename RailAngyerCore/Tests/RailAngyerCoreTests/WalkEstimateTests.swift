import Foundation
import Testing
@testable import RailAngyerCore

/// 予定を立てる段で出す「どれぐらい歩くか」の見積もり。
///
/// **数字が独り歩きしない**ことを確かめる。実測ではないので、
/// 直線より必ず長く、常識的な時速に収まっていればよい。
struct WalkEstimateTests {

    @Test("駅が1つなら距離も時間もゼロ")
    func singlePointIsZero() throws {
        let course = try StationMaster.nanboku()
        let estimate = WalkEstimator.estimate(course: course, from: 3, to: 3)
        #expect(estimate.stationCount == 1)
        #expect(estimate.meters == 0)
        #expect(estimate.seconds == 0)
    }

    @Test("見積もりは直線距離より長い（迂回するぶん）")
    func longerThanStraightLine() throws {
        let course = try StationMaster.nanboku()
        let estimate = WalkEstimator.estimate(course: course, from: 1, to: 16)
        #expect(estimate.straightMeters > 0)
        #expect(estimate.meters > estimate.straightMeters)
    }

    @Test("向きを逆にしても同じ値になる")
    func directionDoesNotMatter() throws {
        let course = try StationMaster.nanboku()
        #expect(WalkEstimator.estimate(course: course, from: 1, to: 16)
                == WalkEstimator.estimate(course: course, from: 16, to: 1))
    }

    @Test("南北線の全区間は14〜20km・3〜5時間に収まる")
    func nanbokuFullSection() throws {
        let course = try StationMaster.nanboku()
        let estimate = WalkEstimator.estimate(course: course, from: 1, to: 16)
        #expect((14_000.0...20_000.0).contains(estimate.meters),
                "麻生〜真駒内は営業キロ14.3km。迂回を足しても20kmは超えない")
        #expect((3.0...5.0).contains(estimate.seconds / 3600))
        #expect(estimate.stationCount == 16)
    }

    @Test("時速が5km前後になる")
    func speedIsPlausible() throws {
        let course = try StationMaster.tozai()
        let estimate = WalkEstimator.estimate(course: course, from: 1, to: 19)
        let kmPerHour = (estimate.meters / 1000) / (estimate.seconds / 3600)
        #expect(abs(kmPerHour - 5) < 0.1)
    }

    @Test("一周は出発した駅へ戻るぶんまで数える")
    func lapClosesTheLoop() throws {
        let course = try StationMaster.yamanote()
        let lap = WalkEstimator.estimateLap(course: course)
        let openEnded = WalkEstimator.estimate(course: course, from: 1, to: 30)
        #expect(lap.meters > openEnded.meters)
        #expect((35_000.0...50_000.0).contains(lap.meters),
                "山手線一周は約34.5km。迂回を足したぶんだけ長くなる")
    }

    @Test("表示は km と時間で読める形になる")
    func textIsReadable() {
        let estimate = WalkEstimate(straightMeters: 10_000, meters: 13_000,
                                    seconds: 9_360, stationCount: 12)
        #expect(estimate.distanceText == "約 13.0 km")
        // 単位は端末の言語で変わる。数字と「約」が入っていることだけを見る
        #expect(estimate.durationText.hasPrefix("約 "))
        #expect(estimate.durationText.contains("2"))
        #expect(estimate.durationText.contains("36"))
        #expect(estimate.summaryText.contains("13.0 km"))
    }

    @Test("1km未満はメートルで出す")
    func shortDistanceUsesMeters() {
        let estimate = WalkEstimate(straightMeters: 500, meters: 650,
                                    seconds: 468, stationCount: 2)
        #expect(estimate.distanceText == "約 650 m")
    }
}
