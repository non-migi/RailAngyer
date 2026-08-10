import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 環状コースの一周（山手線・札幌市電）。
///
/// 一周は「出発した駅に戻ってきたら終わり」。位置の番号は駅数を超えるので、
/// **画面に出す駅へ正しく戻せているか**と、**一周でちょうどクリアになるか**を確かめる。
@MainActor
struct LapJourneyTests {

    private let context: ModelContext
    private let store: GameSessionStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    private func course(_ name: String) throws -> Course {
        try #require(store.courses.first { $0.name == name })
    }

    /// 環状コースに切り替えて一周の設定にする
    @discardableResult
    private func startLap(_ name: String, forward: Bool = true) throws -> Course {
        let course = try course(name)
        #expect(store.updateCourse(course))
        #expect(store.updateLap(true))
        #expect(store.updateLoopDirection(forward ? 1 : -1))
        return course
    }

    // MARK: - 設定

    @Test("環状線は山手線と札幌市電。ほかは一周にできない")
    func onlyLoopCoursesCanLap() throws {
        #expect(try course("山手線").isLoop)
        #expect(try course("札幌市電").isLoop)
        #expect(try course("南北線").isLoop == false)

        #expect(store.updateCourse(try course("南北線")))
        #expect(store.updateLap(true) == false)
        #expect(store.room?.isLap == false)
    }

    @Test("一周にすると、出発と到着が同じ駅になる")
    func lapUsesTheSameStation() throws {
        try startLap("山手線")

        #expect(store.room?.isLap == true)
        #expect(store.room?.startStation?.name == "東京")
        #expect(store.room?.goalStation?.name == "東京")
        #expect(store.engine?.isLoop == true)
        #expect(store.engine?.distinctStationCount == 30)
    }

    @Test("出発する駅を変えられる")
    func lapStartCanMove() throws {
        try startLap("山手線")
        let shinjuku = try #require(store.courses.first { $0.name == "山手線" }?
            .stations.first { $0.name == "新宿" })

        #expect(store.updateLapStart(orderNo: shinjuku.orderNo))

        #expect(store.room?.startStation?.name == "新宿")
        #expect(store.room?.goalStation?.name == "新宿")
        #expect(store.currentOrder == shinjuku.orderNo)
    }

    // MARK: - 盤面

    @Test("盤面には、同じ駅が二度並ばない")
    func boardListsEachStationOnce() throws {
        try startLap("山手線")

        let names = store.stationsInOrder.map(\.name)
        #expect(names.count == 30)
        #expect(Set(names).count == 30, "一周で戻る駅が二重に並んでいる")
        #expect(names.first == "東京")
        #expect(names[1] == "神田")            // 通し番号が増える向き
    }

    @Test("逆にまわると、並びも逆になる")
    func boardFollowsTheDirection() throws {
        try startLap("山手線", forward: false)

        let names = store.stationsInOrder.map(\.name)
        #expect(names.first == "東京")
        #expect(names[1] == "有楽町")          // 通し番号が減る向き
        #expect(names.count == 30)
    }

    // MARK: - 歩く

    /// 出目を固定して1ターン歩ききる
    private func playTurn(dice: Int) {
        store.roll(dice: dice)
        for _ in 0..<40 {
            switch store.phase {
            case .walking, .effectWalking: store.arriveAtNextStop()
            case .arrivedPassing: store.continueWalking()
            case .landed: store.drawMission()
            case .mission: store.finishMission(done: true)
            default: return
            }
        }
    }

    @Test("一周の終わりをまたいでも、駅の名前が正しく出る")
    func stationNamesWrapAtTheSeam() throws {
        try startLap("札幌市電")
        let count = try #require(store.room?.course?.stations.count)   // 24

        // 位置は24を超えるが、駅としては始発に戻る
        #expect(store.stationName(count) == "狸小路")
        #expect(store.stationName(count + 1) == "西4丁目")
        #expect(store.station(count + 2)?.name == "西8丁目")
    }

    @Test("一周してゴールに着く")
    func completesTheLap() throws {
        try startLap("札幌市電")

        for _ in 0..<40 {
            if case .cleared = store.phase { break }
            playTurn(dice: 9)
        }

        guard case .cleared = store.phase else {
            Issue.record("一周してもクリアにならない（現在地 \(store.currentOrder)）")
            return
        }
        #expect(store.stationName(store.currentOrder) == "西4丁目")
        #expect(store.visitedCount == 24)                 // 全電停を踏んでいる
    }

    @Test("一周の途中では、まだクリアにならない")
    func doesNotClearBeforeTheLap() throws {
        try startLap("札幌市電")
        playTurn(dice: 3)

        if case .cleared = store.phase {
            Issue.record("3駅進んだだけでクリアになっている")
        }
        #expect(store.stationName(store.currentOrder) == "西15丁目")
    }

    @Test("逆まわりでも一周できる")
    func completesTheLapBackward() throws {
        try startLap("札幌市電", forward: false)
        #expect(store.stationsInOrder[1].name == "狸小路")

        for _ in 0..<40 {
            if case .cleared = store.phase { break }
            playTurn(dice: 9)
        }

        guard case .cleared = store.phase else {
            Issue.record("逆まわりで一周できない（現在地 \(store.currentOrder)）")
            return
        }
        #expect(store.stationName(store.currentOrder) == "西4丁目")
    }

    // MARK: - 到着判定

    @Test("市電は、電停が近いぶん到着の半径が小さい")
    func tramUsesSmallerRadius() throws {
        try startLap("札幌市電")
        let radius = try #require(store.arrivalRadius)

        #expect(radius == 90)
        // 最短の電停間（すすきの〜狸小路 約190m）でも、圏内が重ならないこと
        #expect(radius * 2 < 190)
    }

    @Test("地下鉄は路線ごとの半径を持たず、設定の値を使う")
    func subwayHasNoCourseRadius() throws {
        #expect(store.updateCourse(try course("南北線")))
        #expect(store.arrivalRadius == nil)
    }

    // MARK: - 一周の途中の駅
    //
    // **番号ではなく「位置」で数える。** 一周では駅の通し番号が一巡して元に戻るので、
    // 番号のまま経路を出すと、逆向きに路線をほぼ一周ぶん並べてしまう
    // （札幌市電で「途中の◯◯も1駅ずつ歩いて訪れます」が大量に出た）

    @Test("一周で番号が一巡しても、途中の駅は出目のぶんだけ")
    func passingStaysWithinDice() throws {
        try startLap("札幌市電")
        let count = try #require(store.room?.course?.stations.count)   // 24

        // 位置が駅の番号を追い越すところまで歩く
        while store.currentOrder <= count { playTurn(dice: 4) }

        store.roll(dice: 4)
        let turn = try #require(store.activeTurn)
        #expect((turn.fromPosition ?? 0) > count, "一巡していないので確認になっていない")

        let passing = store.passingPositions(of: turn)

        // 出目は4なので、途中の駅は3つまで（着地は含まない）
        #expect(passing.count <= 3, "途中の駅が多すぎる: \(passing.count)")
        // 名前も引ける（位置から駅へ直せている）
        for position in passing {
            #expect(store.stationName(position) != "-")
        }
    }

    @Test("一周でない区間でも、途中の駅は出目のぶんだけ")
    func passingOnStraightCourse() throws {
        store.roll(dice: 3)
        let turn = try #require(store.activeTurn)

        #expect(store.passingPositions(of: turn).count == 2)
    }
}
