import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// ミッションの自作（SC-12 / UQ-05）。
///
/// **駅ごとに1人1個**という制約と、**効果の組み合わせ**を保存前に弾けるかを確かめる。
/// サーバーの CHECK 制約に頼ると 400 が返ってから気づくことになり、
/// 圏外で書いたお題が後から捨てられてしまう。
@MainActor
struct MissionAuthoringTests {

    private let context: ModelContext
    private let store: GameSessionStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    @Test("お題を書くと自分の一覧に出る")
    func saveAppearsInMine() throws {
        let error = store.saveMission(nil, station: 4, content: "駅名標を撮る",
                                      effect: .none, value: nil, jumpTo: nil)

        #expect(error == nil)
        let mission = try #require(store.myMissions.first)
        #expect(mission.content == "駅名標を撮る")
        #expect(mission.station?.orderNo == 4)
    }

    @Test("同じ駅に2個目は書けない")
    func rejectsSecondMissionAtSameStation() {
        store.saveMission(nil, station: 4, content: "ひとつめ", effect: .none, value: nil, jumpTo: nil)

        let error = store.saveMission(nil, station: 4, content: "ふたつめ",
                                      effect: .none, value: nil, jumpTo: nil)

        #expect(error != nil)
        #expect(store.myMissions.count == 1)
    }

    @Test("書き換えるときは同じ駅のままでよい")
    func allowsEditingInPlace() throws {
        store.saveMission(nil, station: 4, content: "前の内容", effect: .none, value: nil, jumpTo: nil)
        let mission = try #require(store.myMissions.first)

        let error = store.saveMission(mission, station: 4, content: "あとの内容",
                                      effect: .forward, value: 2, jumpTo: nil)

        #expect(error == nil)
        #expect(store.myMissions.count == 1)
        #expect(store.myMissions.first?.content == "あとの内容")
        #expect(store.myMissions.first?.effectType == .forward)
        #expect(store.myMissions.first?.effectValue == 2)
    }

    @Test("空のお題は保存できない")
    func rejectsEmptyContent() {
        let error = store.saveMission(nil, station: 4, content: "   ",
                                      effect: .none, value: nil, jumpTo: nil)

        #expect(error != nil)
        #expect(store.myMissions.isEmpty)
    }

    @Test("効果を変えると、要らなくなった値は落ちる")
    func clearsUnusedEffectFields() throws {
        store.saveMission(nil, station: 4, content: "お題", effect: .forward, value: 3, jumpTo: nil)
        let mission = try #require(store.myMissions.first)

        store.saveMission(mission, station: 4, content: "お題",
                          effect: .rollAgain, value: 3, jumpTo: 6)

        // 駅数も移動先も持たない効果なので、残っているとサーバーの CHECK に弾かれる
        #expect(mission.effectValue == nil)
        #expect(mission.effectStation == nil)
    }

    @Test("指定駅へ移動は移動先が要る")
    func jumpRequiresDestination() {
        let error = store.saveMission(nil, station: 4, content: "お題",
                                      effect: .jump, value: nil, jumpTo: nil)

        #expect(error != nil)
    }

    @Test("消すと一覧から消える")
    func deleteRemovesFromMine() throws {
        store.saveMission(nil, station: 4, content: "消すお題", effect: .none, value: nil, jumpTo: nil)
        let mission = try #require(store.myMissions.first)

        store.deleteMission(mission)

        #expect(store.myMissions.isEmpty)
    }

    @Test("自分のお題だけが一覧に出る")
    func mineExcludesOthers() throws {
        let room = try #require(store.room)
        let other = Member(displayName: "ケンタ")
        other.missionSet = room
        context.insert(other)

        let theirs = Mission(content: "ケンタのお題")
        theirs.missionSet = room
        theirs.member = other
        theirs.station = store.station(5)
        context.insert(theirs)
        try context.save()

        store.saveMission(nil, station: 4, content: "自分のお題",
                          effect: .none, value: nil, jumpTo: nil)

        #expect(store.myMissions.map(\.content) == ["自分のお題"])
    }
}
