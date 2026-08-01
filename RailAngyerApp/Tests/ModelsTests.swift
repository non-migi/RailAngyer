import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// SwiftData モデルとマスタ投入の検証。
/// インメモリのコンテナを使うので、実機もシミュレータのストレージも汚さない。
@MainActor
struct ModelsTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        return ModelContext(container)
    }

    @Test("マスタを投入すると同梱コースが全部入り、既定は南北線")
    func seedsMaster() throws {
        let context = try makeContext()
        let course = try MasterSeeder.seedIfNeeded(context)

        // 最初に遊ぶのは南北線。他のコースは設定から選べる（フェーズ4）
        #expect(course.name == "南北線")
        let nanboku = course.stations.sorted { $0.orderNo < $1.orderNo }
        #expect(nanboku.count == 16)
        #expect(abs((nanboku.first?.latitude ?? 0) - 43.10834) < 0.000_001)
        #expect(nanboku.first?.name == "麻生")
        #expect(nanboku.last?.name == "真駒内")

        let courses = try context.fetch(FetchDescriptor<Course>())
        #expect(Set(courses.map(\.name)) == ["南北線", "東西線", "東豊線", "山手線", "札幌市電"])
    }

    @Test("二度投入しても重複しない")
    func seedIsIdempotent() throws {
        let context = try makeContext()
        _ = try MasterSeeder.seedIfNeeded(context)
        let before = try context.fetch(FetchDescriptor<Station>()).count
        _ = try MasterSeeder.seedIfNeeded(context)

        #expect(try context.fetch(FetchDescriptor<Course>()).count == 5)
        #expect(try context.fetch(FetchDescriptor<Station>()).count == before)
    }

    @Test("ローカルルームは全線・自分1人で作られる")
    func seedsLocalRoom() throws {
        let context = try makeContext()
        let course = try MasterSeeder.seedIfNeeded(context)
        let room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)

        #expect(room.startStation?.orderNo == 1)
        #expect(room.goalStation?.orderNo == 16)
        #expect(room.diceMax == 6)
        #expect(room.members.count == 1)
        #expect(room.members.first?.isMe == true)
    }

    @Test("ルームから GameEngine を作れる")
    func roomProducesEngine() throws {
        let context = try makeContext()
        let course = try MasterSeeder.seedIfNeeded(context)
        let room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)

        let engine = try #require(room.engine)
        #expect(engine.startOrder == 1)
        #expect(engine.goalOrder == 16)
        #expect(engine.direction == 1)
        #expect(engine.stationCount == 16)
    }

    @Test("区間を変えると GameEngine の向きと駅数が変わる")
    func sectionAndReverse() throws {
        let context = try makeContext()
        let course = try MasterSeeder.seedIfNeeded(context)
        let room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)
        let byOrder = course.stations.sorted { $0.orderNo < $1.orderNo }

        room.startStation = byOrder[15]   // 真駒内
        room.goalStation = byOrder[13]    // 澄川
        room.diceMax = 3

        let engine = try #require(room.engine)
        #expect(engine.direction == -1)
        #expect(engine.stationCount == 3)
        #expect(engine.landingOrder(from: 16, dice: 3) == 14)  // ゴールでクランプ
    }

    // MARK: - Mission の検証（サーバーのCHECK制約に相当）

    @Test("効果なしなのに駅数が入っていると弾く")
    func rejectsValueWithoutEffect() {
        let m = Mission(content: "自販機で当たりを狙う", effectType: .none, effectValue: 3)
        #expect(m.validationError != nil)
    }

    @Test("進む効果に駅数が無いと弾く")
    func rejectsForwardWithoutValue() {
        let m = Mission(content: "ラーメンを食べる", effectType: .forward)
        #expect(m.validationError != nil)
    }

    @Test("ジャンプ効果に移動先が無いと弾く")
    func rejectsJumpWithoutStation() {
        let m = Mission(content: "思い出の駅へ", effectType: .jump)
        #expect(m.validationError != nil)
    }

    @Test("空のお題を弾く")
    func rejectsEmptyContent() {
        #expect(Mission(content: "   ").validationError != nil)
    }

    @Test("正しい組み合わせは通る")
    func acceptsValidMissions() throws {
        #expect(Mission(content: "駅名標を撮る").validationError == nil)
        #expect(Mission(content: "ラーメンを食べる", effectType: .forward, effectValue: 2).validationError == nil)
        #expect(Mission(content: "道に迷う", effectType: .back, effectValue: 1).validationError == nil)
        #expect(Mission(content: "ベンチで休憩", effectType: .rollAgain).validationError == nil)

        let context = try makeContext()
        let course = try MasterSeeder.seedIfNeeded(context)
        let jump = Mission(content: "思い出の駅へ", effectType: .jump)
        jump.effectStation = course.stations.first
        #expect(jump.validationError == nil)
    }

    // MARK: - 進行記録

    @Test("進行中のターンは endStation が nil")
    func activeTurn() throws {
        let context = try makeContext()
        let course = try MasterSeeder.seedIfNeeded(context)
        let room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)
        let byOrder = course.stations.sorted { $0.orderNo < $1.orderNo }

        let turn = Turn(turnNo: 1, diceValue: 3)
        turn.missionSet = room
        turn.fromStation = byOrder[0]
        turn.landingStation = byOrder[3]
        context.insert(turn)
        try context.save()

        #expect(turn.isActive)
        #expect(room.turns.count == 1)

        turn.endStation = byOrder[3]
        turn.completedAt = Date()
        #expect(!turn.isActive)
    }

    @Test("同じ駅を再訪しても記録できる（ver.2 で一意制約を外した）")
    func allowsRevisit() throws {
        let context = try makeContext()
        let course = try MasterSeeder.seedIfNeeded(context)
        let room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)
        let station = course.stations.first { $0.orderNo == 7 }

        for kind in [VisitKind.passing, .landing, .effectPassing] {
            let v = Visit(kind: kind)
            v.missionSet = room
            v.station = station
            context.insert(v)
        }
        try context.save()

        let visits = try context.fetch(FetchDescriptor<Visit>())
        #expect(visits.count == 3)
        #expect(Set(visits.map(\.visitKind)) == [.passing, .landing, .effectPassing])
    }
}
