import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 保存済みのターンと訪問時刻から、移動・ミッション・ペースを数え直す集計。
@MainActor
struct WalkTimingTests {

    private let context: ModelContext
    private let store: GameSessionStore
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    /// 着地または効果移動の終了まで歩かせる。
    private func walk() {
        for _ in 0..<40 {
            switch store.phase {
            case .walking, .effectWalking:
                store.arriveAtNextStop()
            case .arrivedPassing:
                store.continueWalking()
            default:
                return
            }
        }
    }

    /// ミッションなしの1ターンを完了させる。
    private func playTurn(dice: Int) throws -> Turn {
        store.roll(dice: dice)
        walk()
        store.drawMission()
        return try #require(store.room?.turns.max { $0.turnNo < $1.turnNo })
    }

    private func regularVisits(of turn: Turn) -> [Visit] {
        turn.visits
            .filter { $0.visitKind == .passing || $0.visitKind == .landing }
            .sorted { ($0.station?.orderNo ?? 0) < ($1.station?.orderNo ?? 0) }
    }

    @Test("通り道をまたぐ移動を駅間ごとの区間に分ける")
    func splitsPassingStationsIntoLegs() throws {
        let turn = try playTurn(dice: 3) // 1 → 2 → 3 → 4
        turn.rolledAt = base

        let visits = regularVisits(of: turn)
        #expect(visits.count == 3)
        for (index, visit) in visits.enumerated() {
            visit.arrivedAt = base.addingTimeInterval(Double(index + 1) * 600)
        }
        turn.arrivedAt = base.addingTimeInterval(1_800)
        turn.completedAt = base.addingTimeInterval(2_100)

        let legs = WalkTiming.legs(in: turn)
        #expect(legs.count == 3)
        #expect(legs.map(\.fromOrder) == [1, 2, 3])
        #expect(legs.map(\.toOrder) == [2, 3, 4])
        #expect(legs.allSatisfy { $0.seconds == 600 })
    }

    @Test("着地からターン完了までをミッション時間にする")
    func countsMissionTimeAfterLanding() throws {
        let turn = try playTurn(dice: 1)
        turn.rolledAt = base
        let landing = try #require(regularVisits(of: turn).first)
        landing.arrivedAt = base.addingTimeInterval(600)
        turn.arrivedAt = landing.arrivedAt
        turn.completedAt = base.addingTimeInterval(900)

        let timing = WalkTiming.breakdown(of: turn)
        #expect(timing.walkingSeconds == 600)
        #expect(timing.missionSeconds == 300)
        #expect(timing.totalSeconds == 900)
        #expect(timing.isCompleted)
    }

    @Test("効果で歩いた区間も移動時間と距離に含める")
    func includesEffectMovement() throws {
        let error = store.saveMission(nil, station: 2, content: "1駅戻る",
                                      effect: .back, value: 1, jumpTo: nil)
        #expect(error == nil)

        store.roll(dice: 1)
        walk()
        store.drawMission()
        store.finishMission(done: true)
        walk()

        let turn = try #require(store.room?.turns.first)
        turn.rolledAt = base
        let landing = try #require(turn.visits.first { $0.visitKind == .landing })
        let effectArrival = try #require(turn.visits.first { $0.visitKind == .effectArrival })
        landing.arrivedAt = base.addingTimeInterval(600)
        turn.arrivedAt = landing.arrivedAt
        effectArrival.arrivedAt = base.addingTimeInterval(900)
        turn.completedAt = effectArrival.arrivedAt

        let legs = WalkTiming.legs(in: turn)
        let effectLeg = try #require(legs.first { $0.isEffectMove })
        #expect(effectLeg.fromOrder == 2)
        #expect(effectLeg.toOrder == 1)
        #expect(effectLeg.seconds == 300)

        let timing = WalkTiming.breakdown(of: turn)
        #expect(timing.walkingSeconds == 900)
        #expect(timing.meters == legs.reduce(0) { $0 + $1.pace.meters })
    }

    @Test("進行中のターンは指定した現在時刻までを合計にする")
    func reportsInProgressTurnUntilNow() throws {
        store.roll(dice: 1)
        let turn = try #require(store.activeTurn)
        turn.rolledAt = base

        let timing = WalkTiming.breakdown(of: turn, now: base.addingTimeInterval(450))
        #expect(timing.totalSeconds == 450)
        #expect(timing.walkingSeconds == 0, "未到着の区間は距離とペースをまだ確定しない")
        #expect(!timing.isCompleted)
    }

    @Test("サイコロ時刻より前の訪問は区間にも起点にも使わない")
    func ignoresOutOfOrderVisit() throws {
        let turn = try playTurn(dice: 3)
        turn.rolledAt = base
        let visits = regularVisits(of: turn)
        #expect(visits.count == 3)

        visits[0].arrivedAt = base.addingTimeInterval(-60) // 壊れた記録
        visits[1].arrivedAt = base.addingTimeInterval(600)
        visits[2].arrivedAt = base.addingTimeInterval(1_200)

        let legs = WalkTiming.legs(in: turn)
        #expect(legs.count == 2)
        #expect(legs[0].fromOrder == 1)
        #expect(legs[0].toOrder == 3)
        #expect(legs[0].seconds == 600)
        #expect(!legs.contains { $0.toOrder == 2 })
    }
}
