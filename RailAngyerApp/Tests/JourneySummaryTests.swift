import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// ふりかえりの集計（SC-17）。
///
/// 数え方を決めるのがこの型の役目なので、**再訪をどう数えるか**（DV-06）と
/// **途中でも出せること**を中心に確かめる。
@MainActor
struct JourneySummaryTests {

    private let context: ModelContext
    private let store: GameSessionStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    private func summary() throws -> JourneySummary {
        let room = try #require(store.room)
        return JourneySummary(room: room, engine: store.engine)
    }

    /// 出目を固定して1ターン歩ききる
    private func playTurn(dice: Int) {
        store.roll(dice: dice)
        for _ in 0..<20 {
            switch store.phase {
            case .walking, .effectWalking: store.arriveAtNextStop()
            case .arrivedPassing: store.continueWalking()
            case .landed: store.drawMission()
            case .mission: store.finishMission(done: true)
            default: return
            }
        }
    }

    @Test("何もしていなければ全部ゼロ")
    func emptyJourney() throws {
        let summary = try summary()

        #expect(summary.visitedCount == 0)
        #expect(summary.turnCount == 0)
        #expect(summary.photoCount == 0)
        #expect(!summary.isCleared)
        #expect(summary.elapsedText == nil)
    }

    @Test("1ターン歩くと通り道もふくめて数える")
    func countsPassingStations() throws {
        playTurn(dice: 3)

        let summary = try summary()
        // 始点1 と、通り道2・3、着地4
        #expect(summary.visitedCount == 4)
        #expect(summary.landedCount == 1)
        #expect(summary.turnCount == 1)
    }

    @Test("同じ駅を再訪しても踏破率は重複して数えない")
    func revisitDoesNotInflateRate() throws {
        playTurn(dice: 2)          // 1 → 3
        playTurn(dice: 1)          // 3 → 4
        let before = try summary().visitedCount

        // 戻ってから同じ駅を通り直す
        let room = try #require(store.room)
        let visit = Visit(kind: .passing)
        visit.missionSet = room
        visit.turn = room.turns.first
        visit.station = store.station(3)
        context.insert(visit)

        let after = try summary()
        #expect(after.visitedCount == before)               // 踏破率は増えない（DV-06）
        #expect(after.stations.first { $0.orderNo == 3 }?.visitCount == 2)  // 訪問回数は増える
    }

    @Test("ゴールに着くとクリアになる")
    func clearedAtGoal() throws {
        for _ in 0..<20 {
            if case .cleared = store.phase { break }
            playTurn(dice: 9)
        }

        let summary = try summary()
        #expect(summary.isCleared)
        #expect(summary.stations.last?.landed == true)
    }

    @Test("引いたお題が結果に並ぶ")
    func listsMissionResults() throws {
        let room = try #require(store.room)
        let me = try #require(store.me)
        let mission = Mission(content: "駅名標を撮る")
        mission.missionSet = room
        mission.member = me
        mission.station = store.station(4)
        context.insert(mission)

        playTurn(dice: 3)          // 4駅目に着地してお題を引く

        let summary = try summary()
        let result = try #require(summary.missionResults.first)
        #expect(result.content == "駅名標を撮る")
        #expect(result.stationName == store.stationName(4))
        #expect(result.outcome == .done)
    }

    @Test("途中でも歩いた時間が出る")
    func reportsElapsedWhileWalking() throws {
        playTurn(dice: 2)

        // 振ってから完了までを明示的に置き、1時間5分ぶんの記録にする
        let room = try #require(store.room)
        let turn = try #require(room.turns.first)
        let visits = turn.visits.sorted {
            ($0.station?.orderNo ?? 0) < ($1.station?.orderNo ?? 0)
        }
        let base = Date().addingTimeInterval(-7_200)
        turn.rolledAt = base
        try #require(room.visits.first { $0.visitKind == .start }).arrivedAt = base
        try #require(visits.first).arrivedAt = base.addingTimeInterval(1_800)
        try #require(visits.last).arrivedAt = base.addingTimeInterval(3_600)
        turn.arrivedAt = base.addingTimeInterval(3_600)
        turn.completedAt = base.addingTimeInterval(3_900)

        let summary = try summary()
        #expect(summary.elapsedText == "1時間5分")
        #expect(summary.timing.walkingSeconds == 3_600)
        #expect(summary.timing.missionSeconds == 300)
        #expect(summary.timing.otherSeconds == 0)
        #expect(summary.timing.pace.text != nil)
    }
}
