import Foundation
import SwiftData
import RailAngyerCore

/// ゲームの進行を担う。SwiftData への読み書きと、局面の導出を引き受ける。
///
/// ルールの計算そのものは `GameEngine` が持つ（10_アプリ設計.md AD-03）。
/// ここは「いつ何を保存するか」だけを扱う。
@Observable
final class GameSessionStore {

    private let context: ModelContext

    /// 対象のルーム（フェーズ1では1件だけ）
    private(set) var room: MissionSet?
    /// 直前の操作で起きたエラー
    var lastError: String?
    /// 着地駅の告知（SC-06）を出しているか
    var showingAnnouncement = false

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - 準備

    /// マスタとローカルルームを用意する。初回起動時に1回だけ効く。
    func prepare(sampleMissions: Bool = true) {
        do {
            let course = try MasterSeeder.seedIfNeeded(context)
            let room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)
            if sampleMissions { try MasterSeeder.seedSampleMissionsIfNeeded(context, room: room) }
            self.room = room
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - 導出

    var engine: GameEngine? { room?.engine }

    /// 区間内の駅を進む向きに並べたもの
    var stationsInOrder: [Station] {
        guard let room, let engine else { return [] }
        let all = room.course?.stations ?? []
        return engine.orderedRange.compactMap { order in all.first { $0.orderNo == order } }
    }

    /// 進行中のターン（あれば1件）
    var activeTurn: Turn? { room?.turns.first { $0.isActive } }

    /// 現在位置。最後に完了したターンの終了位置。無ければスタート駅（10_アプリ設計.md §5.2）
    var currentOrder: Int {
        guard let room else { return 1 }
        let completed = room.turns
            .filter { $0.completedAt != nil }
            .max { $0.turnNo < $1.turnNo }
        return completed?.endStation?.orderNo ?? room.startStation?.orderNo ?? 1
    }

    /// 一度でも訪れた駅の数（再訪は重複して数えない。DV-06）
    var visitedCount: Int {
        Set(room?.visits.compactMap { $0.station?.orderNo } ?? []).count
    }

    /// 訪問済みの駅番号
    var visitedOrders: Set<Int> {
        Set(room?.visits.compactMap { $0.station?.orderNo } ?? [])
    }

    /// 着地したことのある駅番号
    var landedOrders: Set<Int> {
        Set(room?.visits.filter { $0.visitKind == .landing }.compactMap { $0.station?.orderNo } ?? [])
    }

    /// いまの局面
    var phase: GamePhase {
        guard let engine else { return .notReady }

        guard let turn = activeTurn else {
            return engine.isCleared(currentOrder) ? .cleared : .waiting(current: currentOrder)
        }
        let landing = turn.landingStation?.orderNo ?? currentOrder

        // 出目による移動中
        if turn.arrivedAt == nil {
            let from = turn.fromStation?.orderNo ?? currentOrder
            let stops = engine.path(from: from, to: landing)
            let done = visitedOrders(in: turn, kinds: [.passing, .landing])
            let remaining = stops.filter { !done.contains($0) }
            return .walking(next: remaining.first ?? landing, remaining: remaining.count)
        }

        // 効果が決まっていなければ、抽選前かミッション中
        guard let applied = turn.appliedEffectType else {
            return turn.selectedMission == nil ? .landed(station: landing) : .mission(station: landing)
        }

        // 効果による移動中
        if applied.movesPiece, let destination = effectDestination(of: turn) {
            let stops = engine.path(from: landing, to: destination)
            let done = visitedOrders(in: turn, kinds: [.effectPassing, .effectArrival])
            let remaining = stops.filter { !done.contains($0) }
            return .effectWalking(next: remaining.first ?? destination, destination: destination)
        }
        return .mission(station: landing)
    }

    // MARK: - 操作

    /// サイコロを振る（F-01）。振った時点で `Turn` を保存するので、
    /// アプリが落ちても出目と行き先が残る。
    func roll() {
        guard let engine else { return }
        roll(dice: engine.roll())
    }

    /// 出目を指定して振る。テストで進行を再現するために分けてある
    func roll(dice: Int) {
        guard let room, let engine, activeTurn == nil else { return }
        do {
            try recordStartVisitIfNeeded(room)

            let landing = engine.landingOrder(from: currentOrder, dice: dice)
            let nextNo = (room.turns.map(\.turnNo).max() ?? 0) + 1

            let turn = Turn(turnNo: nextNo, diceValue: dice)
            turn.missionSet = room
            turn.fromStation = station(currentOrder)
            turn.landingStation = station(landing)
            context.insert(turn)
            try context.save()

            showingAnnouncement = true
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 次の駅に到着した（F-04 / F-06）。
    /// 位置情報が使えるようになったら `LocationService` から呼ぶ。手動到着（E-01）でも同じ。
    func arriveAtNextStop() {
        guard let turn = activeTurn else { return }
        do {
            switch phase {
            case .walking(let next, _):
                let isLanding = next == turn.landingStation?.orderNo
                try record(visit: isLanding ? .landing : .passing, at: next, turn: turn)
                if isLanding { turn.arrivedAt = Date() }
                try context.save()

            case .effectWalking(let next, let destination):
                let isArrival = next == destination
                try record(visit: isArrival ? .effectArrival : .effectPassing, at: next, turn: turn)
                try context.save()
                if isArrival { try complete(turn, at: destination) }

            default:
                break
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 着地駅のミッション候補（R-07 / R-14 既出は除外）
    func missionCandidates(at order: Int) -> [Mission] {
        guard let room, let station = station(order) else { return [] }
        let used = Set(room.turns.compactMap { $0.selectedMission?.id })
        return room.missions.filter { $0.station?.id == station.id && !used.contains($0.id) }
    }

    /// ミッションを抽選する（F-07）。候補が0件ならミッションなしでターンを進める（R-08）
    func drawMission() {
        guard let turn = activeTurn, let landing = turn.landingStation?.orderNo else { return }
        let candidates = missionCandidates(at: landing)
        guard let picked = candidates.randomElement() else {
            finishMission(done: false)   // 候補0件。効果なしとして扱う
            return
        }
        turn.selectedMission = picked
        save()
    }

    /// ミッションを終える（F-08 → F-09）。
    /// 暫定では達成の可否にかかわらず効果を発動する（R-09 / Q-10）。
    func finishMission(done: Bool) {
        guard let turn = activeTurn, let engine else { return }
        turn.missionDone = done

        let mission = turn.selectedMission
        let effect = mission?.effectType ?? .none
        turn.appliedEffectType = effect

        let landing = turn.landingStation?.orderNo ?? currentOrder
        let destination = engine.endOrder(landing: landing,
                                          effect: effect,
                                          value: mission?.effectValue,
                                          jumpTo: mission?.effectStation?.orderNo)
        do {
            if effect.movesPiece && destination != landing {
                try context.save()      // 移動はこのあと歩いて行う
            } else {
                try complete(turn, at: landing)
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 記録をリセットして最初からやり直す（SC-20）
    func resetProgress() {
        guard let room else { return }
        do {
            for visit in room.visits { context.delete(visit) }   // Photo は cascade
            for turn in room.turns { context.delete(turn) }
            try context.save()
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 区間と最大出目を変更する。進行中は変えられない（T-06）
    func updateRule(start: Station?, goal: Station?, diceMax: Int) -> Bool {
        guard let room, room.turns.isEmpty else { return false }
        if let start { room.startStation = start }
        if let goal { room.goalStation = goal }
        room.diceMax = min(max(diceMax, 1), 9)
        save()
        return true
    }

    // MARK: - 補助

    func station(_ order: Int) -> Station? {
        room?.course?.stations.first { $0.orderNo == order }
    }

    func stationName(_ order: Int) -> String { station(order)?.name ?? "-" }

    /// 効果による移動先
    private func effectDestination(of turn: Turn) -> Int? {
        guard let engine, let effect = turn.appliedEffectType, effect.movesPiece else { return nil }
        let landing = turn.landingStation?.orderNo ?? currentOrder
        let destination = engine.endOrder(landing: landing,
                                          effect: effect,
                                          value: turn.selectedMission?.effectValue,
                                          jumpTo: turn.selectedMission?.effectStation?.orderNo)
        return destination == landing ? nil : destination
    }

    private func visitedOrders(in turn: Turn, kinds: Set<VisitKind>) -> Set<Int> {
        Set(turn.visits.filter { kinds.contains($0.visitKind) }.compactMap { $0.station?.orderNo })
    }

    private func record(visit kind: VisitKind, at order: Int, turn: Turn?) throws {
        guard let room, let station = station(order) else { return }
        let visit = Visit(kind: kind)
        visit.missionSet = room
        visit.turn = turn
        visit.station = station
        context.insert(visit)
    }

    /// 始点を記録する（R-17）。踏破率の分子に含めるため
    private func recordStartVisitIfNeeded(_ room: MissionSet) throws {
        guard room.visits.isEmpty, let start = room.startStation?.orderNo else { return }
        try record(visit: .start, at: start, turn: nil)
    }

    private func complete(_ turn: Turn, at order: Int) throws {
        turn.endStation = station(order)
        turn.completedAt = Date()
        try context.save()
    }

    private func save() {
        do { try context.save() } catch { lastError = String(describing: error) }
    }
}
