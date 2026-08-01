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
    /// 2026-08-09(日) 09:00 JST
    private let startAt = Date(timeIntervalSince1970: 1_786_233_600)

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

    @Test("サイコロの最大出目は1〜9に収める")
    func clampsDiceMax() throws {
        let schedule = try schedule("おかしな出目")
        schedule.diceMax = 99
        try context.save()

        #expect(store.applySchedule(schedule) == nil)
        #expect(store.room?.diceMax == 9)
    }
}
