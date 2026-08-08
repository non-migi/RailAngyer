import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 立ててある予定から旅を始める（`startableSchedules` / `applySchedule`）。
///
/// **予定にはもうルールが書いてある。** 始めるたびに設定画面をたどり直すのは、
/// 同じことを二度決めているのと同じ。選べばそのまま始められること、
/// そして**歩き始めたあとは移さない**ことを確かめる。
@MainActor
struct StartFromScheduleTests {

    private let context: ModelContext
    private let store: GameSessionStore
    /// **固定の日時を書かない。** `startableSchedules` は先の予定しか返さないので、
    /// 固定日時にすると、その日を過ぎた日から突然落ちる
    private let startAt = Date().addingTimeInterval(7 * 24 * 60 * 60)

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

    @discardableResult
    private func schedule(_ title: String, courseName: String = "東西線",
                          start: Int = 3, goal: Int = 9, dice: Int = 4,
                          at when: Date? = nil) throws -> Schedule {
        let error = store.saveSchedule(nil, title: title, startAt: when ?? startAt,
                                       meetPlace: nil, course: try course(courseName),
                                       startOrder: start, goalOrder: goal, diceMax: dice)
        #expect(error == nil)
        return try #require(store.schedules.first { $0.title == title })
    }

    @Test("これからの予定だけが選べる")
    func onlyUpcomingSchedules() throws {
        try schedule("これから")
        try schedule("むかし", at: Date(timeIntervalSince1970: 1_000_000_000))   // 2001年

        #expect(store.startableSchedules.map(\.title) == ["これから"])
    }

    @Test("集合が近い順に並ぶ")
    func sortedByStartAt() throws {
        try schedule("あと", at: startAt.addingTimeInterval(86_400))
        try schedule("さき", at: startAt)

        #expect(store.startableSchedules.map(\.title) == ["さき", "あと"])
    }

    @Test("端末に無いコースの予定は選べない")
    func hidesUnknownCourse() throws {
        let schedule = try schedule("知らない路線")
        schedule.courseName = "パリ地下鉄1号線"
        try context.save()
        store.reloadSchedules()

        // 選んでもルールを移せない。出さないほうが親切
        #expect(store.startableSchedules.isEmpty)
    }

    @Test("選ぶと、その予定のルールで始められる")
    func appliesRules() throws {
        let schedule = try schedule("東西線を歩く", courseName: "東西線",
                                    start: 3, goal: 9, dice: 4)

        #expect(store.applySchedule(schedule) == nil)

        #expect(store.room?.course?.name == "東西線")
        #expect(store.room?.startStation?.orderNo == 3)
        #expect(store.room?.goalStation?.orderNo == 9)
        #expect(store.room?.diceMax == 4)
    }

    @Test("歩き始めたあとは移さない")
    func refusesAfterPlayStarted() throws {
        let schedule = try schedule("東西線を歩く")
        store.roll(dice: 2)                      // もう1ターン進んでいる

        let error = store.applySchedule(schedule)

        // 区間外を指す記録が残ると進行が壊れる（T-06）
        #expect(error != nil)
        #expect(store.room?.course?.name == "南北線")
    }

    // MARK: - 一周する予定
    //
    // **山手線を東京から出て東京へ戻る。** 予定では同じ駅を指す区間を
    // 「間違い」として弾いていたので、一周の予定が立てられなかった

    @Test("環状線なら、同じ駅を出て同じ駅へ戻る予定を立てられる")
    func canPlanALap() throws {
        let yamanote = try course("山手線")
        let tokyo = try #require(yamanote.stationsInOrder.first)

        let error = store.saveSchedule(nil, title: "山手線を一周", startAt: startAt,
                                       meetPlace: nil, course: yamanote,
                                       startOrder: tokyo.orderNo, goalOrder: tokyo.orderNo,
                                       diceMax: 6, isLap: true)

        #expect(error == nil)
        let schedule = try #require(store.schedules.first { $0.title == "山手線を一周" })
        #expect(schedule.isLap)
        #expect(schedule.startOrder == tokyo.orderNo)
        // 一周ではゴールも出発した駅にそろえる
        #expect(schedule.goalOrder == tokyo.orderNo)
    }

    @Test("環状でないコースは一周にできない")
    func rejectsLapOnStraightCourse() throws {
        let nanboku = try course("南北線")

        let error = store.saveSchedule(nil, title: "南北線を一周", startAt: startAt,
                                       meetPlace: nil, course: nanboku,
                                       startOrder: 1, goalOrder: 1, diceMax: 6, isLap: true)

        #expect(error == "このコースは一周できません")
    }

    @Test("一周でなければ、同じ駅の区間はこれまでどおり弾く")
    func stillRejectsSameStationWhenNotLap() throws {
        let error = store.saveSchedule(nil, title: "おかしな区間", startAt: startAt,
                                       meetPlace: nil, course: try course("山手線"),
                                       startOrder: 3, goalOrder: 3, diceMax: 6)

        #expect(error == "スタートとゴールは別の駅にしてください")
    }

    @Test("一周の予定を選ぶと、一周する設定で始まる")
    func appliesLap() throws {
        let yamanote = try course("山手線")
        let tokyo = try #require(yamanote.stationsInOrder.first)
        store.saveSchedule(nil, title: "山手線を一周", startAt: startAt, meetPlace: nil,
                           course: yamanote, startOrder: tokyo.orderNo,
                           goalOrder: tokyo.orderNo, diceMax: 6,
                           isLap: true, loopDirection: -1)
        let schedule = try #require(store.schedules.first { $0.title == "山手線を一周" })

        #expect(store.applySchedule(schedule) == nil)

        #expect(store.room?.isLap == true)
        #expect(store.room?.startStation?.orderNo == tokyo.orderNo)
        #expect(store.room?.goalStation?.orderNo == tokyo.orderNo)
        // まわる向きも予定に書いたものに合わせる
        #expect(store.room?.loopDirectionRaw == -1)
        // 一周ぶんの盤面になっていること
        #expect(store.stationsInOrder.count == yamanote.stations.count)
    }

    @Test("サイコロの最大出目は1〜9に収める")
    func clampsDiceMax() throws {
        let schedule = try schedule("おかしな出目")
        schedule.diceMax = 99
        try context.save()

        #expect(store.applySchedule(schedule) == nil)
        #expect(store.room?.diceMax == 9)
    }
}
