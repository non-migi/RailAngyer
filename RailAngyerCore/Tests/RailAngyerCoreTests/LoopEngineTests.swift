import Foundation
import Testing
@testable import RailAngyerCore

/// 環状コースの一周（山手線・札幌市電）。
///
/// 一周を「通し番号が1周ぶん伸びた直線」として扱っているので、
/// **ゴールのクランプも戻る効果も、直線区間と同じ計算がそのまま効く**。
/// ここでは、位置の番号が駅に正しく戻ることと、一周でちょうど終わることを確かめる。
struct LoopEngineTests {

    /// 30駅の環状（山手線に相当）を、通し番号が増える向きで一周する
    private let outer = GameEngine.lap(from: 1, stationCount: 30, forward: true, diceMax: 6)
    /// 同じ環状を、逆向きに一周する
    private let inner = GameEngine.lap(from: 1, stationCount: 30, forward: false, diceMax: 6)

    @Test("一周は、始発駅に戻ってくるところで終わる")
    func lapEndsWhereItStarted() {
        #expect(outer.startOrder == 1)
        #expect(outer.goalOrder == 31)                 // 位置としては1周ぶん先
        #expect(outer.stationOrder(at: 31) == 1)       // 駅としては始発駅そのもの
        #expect(outer.isCleared(31))
        #expect(!outer.isCleared(30))
    }

    @Test("駅数は、戻ってくる1駅を二重に数えない")
    func distinctStationCount() {
        #expect(outer.stationCount == 31)              // 位置の数
        #expect(outer.distinctStationCount == 30)      // 実際に訪れる駅の数
    }

    @Test("位置の番号は、一周を超えても駅に戻せる", arguments: [
        (1, 1), (30, 30), (31, 1), (32, 2), (60, 30), (61, 1)
    ])
    func wrapsForward(_ position: Int, _ expected: Int) {
        #expect(outer.stationOrder(at: position) == expected)
    }

    @Test("逆向きでも、位置の番号が駅に戻せる", arguments: [
        (1, 1), (0, 30), (-1, 29), (-29, 1), (-28, 2)
    ])
    func wrapsBackward(_ position: Int, _ expected: Int) {
        #expect(inner.stationOrder(at: position) == expected)
    }

    @Test("外回りは通し番号が増える向きへ進む")
    func outerMovesForward() {
        #expect(outer.direction == 1)
        #expect(outer.landingOrder(from: 1, dice: 3) == 4)
        #expect(outer.stationOrder(at: outer.landingOrder(from: 29, dice: 3)) == 1)
    }

    @Test("内回りは通し番号が減る向きへ進む")
    func innerMovesBackward() {
        #expect(inner.direction == -1)
        #expect(inner.landingOrder(from: 1, dice: 3) == -2)
        #expect(inner.stationOrder(at: inner.landingOrder(from: 1, dice: 3)) == 28)
    }

    @Test("出目が余ってもゴールを通り越さない")
    func doesNotOvershootTheLap() {
        // あと2駅で一周というところで6が出ても、ちょうど一周で止まる
        #expect(outer.landingOrder(from: 29, dice: 6) == 31)
        #expect(outer.isCleared(outer.landingOrder(from: 29, dice: 6)))

        #expect(inner.landingOrder(from: -27, dice: 6) == -29)
        #expect(inner.isCleared(inner.landingOrder(from: -27, dice: 6)))
    }

    @Test("戻る効果でも、始発より手前へは戻らない")
    func backEffectStopsAtStart() {
        #expect(outer.endOrder(landing: 3, effect: .back, value: 5) == 1)
        #expect(inner.endOrder(landing: -1, effect: .back, value: 5) == 1)
    }

    @Test("進む効果でも、一周を超えない")
    func forwardEffectStopsAtGoal() {
        #expect(outer.endOrder(landing: 28, effect: .forward, value: 9) == 31)
    }

    @Test("通り道は、一周をまたいでも順に並ぶ")
    func pathCrossesTheSeam() {
        let stops = outer.path(from: 29, to: 31)
        #expect(stops == [30, 31])
        #expect(stops.map(outer.stationOrder(at:)) == [30, 1])   // 駅としては 30 → 東京

        let back = inner.path(from: 0, to: -2)
        #expect(back == [-1, -2])
        #expect(back.map(inner.stationOrder(at:)) == [29, 28])
    }

    @Test("盤面に並べる位置は、始発から一周ぶん")
    func orderedRangeCoversOneLap() {
        #expect(outer.orderedRange.first == 1)
        #expect(outer.orderedRange.last == 31)
        #expect(outer.orderedRange.count == 31)

        #expect(inner.orderedRange.first == 1)
        #expect(inner.orderedRange.last == -29)
    }

    @Test("1ターンの道のりも、一周をまたいで組み立てられる")
    func planCrossesTheSeam() {
        let plan = outer.plan(from: 28, dice: 3)
        #expect(plan.landing == 31)
        #expect(plan.passing == [29, 30])
        #expect(plan.reachesGoal)
        #expect(plan.allStops.map(outer.stationOrder(at:)) == [29, 30, 1])
    }

    @Test("札幌市電の24電停でも、一周で戻ってくる")
    func tramLap() throws {
        let course = try StationMaster.shiden()
        let engine = GameEngine.lap(from: 1, stationCount: course.stations.count,
                                    forward: true, diceMax: 6)

        #expect(engine.distinctStationCount == 24)
        #expect(engine.stationOrder(at: engine.goalOrder) == 1)
        #expect(course.station(orderNo: engine.stationOrder(at: 25))?.name == "西4丁目")
    }

    @Test("直線のコースは、これまでどおり動く")
    func linearCourseIsUnchanged() {
        let line = GameEngine(startOrder: 1, goalOrder: 16, diceMax: 6)

        #expect(!line.isLoop)
        #expect(line.distinctStationCount == 16)
        #expect(line.stationOrder(at: 20) == 20)          // 直線では丸めない
        #expect(line.landingOrder(from: 14, dice: 6) == 16)
    }
}
