import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 1ターンの進行（F-01〜F-11）が、正しい順に正しいものを保存するかを確かめる。
@MainActor
struct GameSessionStoreTests {

    /// 仮ミッションを入れずに、区間だけ整えたストアを用意する
    private func makeStore(start: Int = 1, goal: Int = 16, diceMax: Int = 6) throws -> GameSessionStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        let context = ModelContext(container)
        let store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
        let stations = store.room?.course?.stations.sorted { $0.orderNo < $1.orderNo } ?? []
        _ = store.updateRule(start: stations.first { $0.orderNo == start },
                             goal: stations.first { $0.orderNo == goal },
                             diceMax: diceMax)
        return store
    }

    /// 着地するまで到着ボタンを押し続ける
    private func walkToLanding(_ store: GameSessionStore) {
        var guardCount = 0
        while case .walking = store.phase {
            store.arriveAtNextStop()
            guardCount += 1
            if guardCount > 20 { break }
        }
    }

    // MARK: - 基本

    @Test("初期状態は待機で、現在地はスタート駅")
    func initialState() throws {
        let store = try makeStore()
        #expect(store.phase == .waiting(current: 1))
        #expect(store.currentOrder == 1)
        #expect(store.activeTurn == nil)
    }

    @Test("サイコロを振ると Turn が保存され、始点も記録される")
    func rollPersistsTurn() throws {
        let store = try makeStore(diceMax: 1)
        store.roll()

        let turn = try #require(store.activeTurn)
        #expect(turn.turnNo == 1)
        #expect(turn.diceValue == 1)
        #expect(turn.fromStation?.orderNo == 1)
        #expect(turn.landingStation?.orderNo == 2)
        #expect(turn.isActive)
        #expect(turn.arrivedAt == nil, "まだ着いていない")

        // R-17 始点の記録
        #expect(store.room?.visits.contains { $0.visitKind == .start } == true)
        #expect(store.visitedOrders.contains(1))
    }

    @Test("進行中は二重にサイコロを振れない")
    func cannotRollTwice() throws {
        let store = try makeStore()
        store.roll()
        let first = store.activeTurn?.id
        store.roll()
        #expect(store.activeTurn?.id == first)
        #expect(store.room?.turns.count == 1)
    }

    @Test("通り道の駅がすべて記録され、着地で arrivedAt が入る")
    func recordsPassingAndLanding() throws {
        let store = try makeStore(diceMax: 3)
        store.roll()
        let landing = try #require(store.activeTurn?.landingStation?.orderNo)
        let dice = try #require(store.activeTurn?.diceValue)

        walkToLanding(store)

        let turn = try #require(store.activeTurn)
        #expect(turn.arrivedAt != nil)
        let passing = turn.visits.filter { $0.visitKind == .passing }
        #expect(passing.count == dice - 1, "通り道は出目-1駅")
        #expect(turn.visits.contains { $0.visitKind == .landing && $0.station?.orderNo == landing })
        #expect(store.phase == .landed(station: landing))
    }

    // MARK: - ミッション

    @Test("候補0件の駅ではミッションを出さずターンが終わる（R-08）")
    func noMissionCompletesTurn() throws {
        let store = try makeStore(diceMax: 2)
        store.roll()
        walkToLanding(store)
        let landing = try #require(store.activeTurn?.landingStation?.orderNo)

        store.drawMission()

        #expect(store.activeTurn == nil, "ターンが完了している")
        #expect(store.currentOrder == landing)
        #expect(store.phase == .waiting(current: landing))
    }

    @Test("ミッションを引くと Turn に記録され、達成でターンが終わる")
    func drawAndFinishMission() throws {
        let store = try makeStore(diceMax: 1)
        let station = try #require(store.station(2))
        try addMission(store, at: station, content: "駅名標を撮る")

        store.roll(dice: 1)
        walkToLanding(store)
        store.drawMission()

        let turn = try #require(store.activeTurn)
        #expect(turn.selectedMission?.content == "駅名標を撮る")
        #expect(store.phase == .mission(station: 2))

        store.finishMission(done: true)
        #expect(store.activeTurn == nil)
        #expect(store.currentOrder == 2)
        #expect(store.room?.turns.first?.missionDone == true)
    }

    @Test("一度引いたミッションは再訪しても候補から外れる（R-14）")
    func usedMissionIsExcluded() throws {
        let store = try makeStore(diceMax: 1)
        let station = try #require(store.station(2))
        try addMission(store, at: station, content: "一度きり")

        #expect(store.missionCandidates(at: 2).count == 1)
        store.roll(dice: 1); walkToLanding(store); store.drawMission(); store.finishMission(done: true)
        #expect(store.missionCandidates(at: 2).isEmpty)
    }

    // MARK: - 効果

    @Test("戻る効果でコマが戻り、その道のりも歩いて記録される")
    func backEffectWalksBack() throws {
        let store = try makeStore(diceMax: 3)
        // 3駅進んで4に着地 → 2駅戻って2へ
        let station = try #require(store.station(4))
        try addMission(store, at: station, content: "道に迷う", effect: .back, value: 2)

        store.roll(dice: 3)
        #expect(store.activeTurn?.landingStation?.orderNo == 4)
        walkToLanding(store)
        store.drawMission()
        store.finishMission(done: true)

        // 効果による移動が残っている
        guard case .effectWalking(_, let destination) = store.phase else {
            Issue.record("効果による移動になっていない: \(store.phase)")
            return
        }
        #expect(destination == 2)

        store.arriveAtNextStop()   // 3
        store.arriveAtNextStop()   // 2 に到達 → ターン完了

        #expect(store.activeTurn == nil)
        #expect(store.currentOrder == 2, "コマが戻っている")

        let turn = try #require(store.room?.turns.first)
        #expect(turn.landingStation?.orderNo == 4)
        #expect(turn.endStation?.orderNo == 2)
        #expect(turn.visits.filter { $0.visitKind == .effectPassing }.count == 1)
        #expect(turn.visits.contains { $0.visitKind == .effectArrival && $0.station?.orderNo == 2 })
    }

    @Test("もう一度振る効果は位置を変えずターンを終える")
    func rollAgainDoesNotMove() throws {
        let store = try makeStore(diceMax: 1)
        let station = try #require(store.station(2))
        try addMission(store, at: station, content: "休憩", effect: .rollAgain)

        store.roll(dice: 1); walkToLanding(store); store.drawMission(); store.finishMission(done: true)

        #expect(store.activeTurn == nil)
        #expect(store.currentOrder == 2)
        #expect(store.room?.turns.first?.appliedEffectType == .rollAgain)
    }

    @Test("戻る効果はスタートより手前へ行かない（R-12）")
    func backEffectClampedAtStart() throws {
        let store = try makeStore(start: 1, goal: 16, diceMax: 1)
        let station = try #require(store.station(2))
        try addMission(store, at: station, content: "大きく戻る", effect: .back, value: 5)

        store.roll(dice: 1); walkToLanding(store); store.drawMission(); store.finishMission(done: true)

        // 2 から5駅戻ろうとしてもスタート1で止まる。移動は1駅ぶん
        if case .effectWalking(_, let destination) = store.phase {
            #expect(destination == 1)
            store.arriveAtNextStop()
        }
        #expect(store.currentOrder == 1)
    }

    // MARK: - クリアとリセット

    @Test("ゴールに到達するとクリアになる")
    func reachesGoal() throws {
        let store = try makeStore(start: 1, goal: 3, diceMax: 3)
        store.roll(dice: 3)
        #expect(store.activeTurn?.landingStation?.orderNo == 3, "ゴールでクランプされる")
        walkToLanding(store)
        store.drawMission()
        #expect(store.phase == .cleared)
    }

    @Test("リセットすると記録が消え、設定とミッションは残る")
    func resetKeepsRules() throws {
        let store = try makeStore(diceMax: 2)
        let station = try #require(store.station(2))
        try addMission(store, at: station, content: "残るお題")
        store.roll(dice: 1); walkToLanding(store)

        store.resetProgress()

        #expect(store.room?.turns.isEmpty == true)
        #expect(store.room?.visits.isEmpty == true)
        #expect(store.currentOrder == 1)
        #expect(store.missionCandidates(at: 2).count == 1, "ミッションは残る")
        #expect(store.room?.diceMax == 2, "設定も残る")
    }

    @Test("プレイを始めたら区間を変更できない（T-06）")
    func rulesLockedAfterStart() throws {
        let store = try makeStore(diceMax: 1)
        store.roll()
        let changed = store.updateRule(start: store.station(3), goal: store.station(10), diceMax: 4)
        #expect(!changed)
        #expect(store.room?.startStation?.orderNo == 1)
    }

    // MARK: - 補助

    private func addMission(_ store: GameSessionStore,
                            at station: Station,
                            content: String,
                            effect: EffectType = .none,
                            value: Int? = nil) throws {
        let room = try #require(store.room)
        let mission = Mission(content: content, effectType: effect, effectValue: value)
        mission.missionSet = room
        mission.member = room.members.first
        mission.station = station
        room.modelContext?.insert(mission)
        try room.modelContext?.save()
    }
}
