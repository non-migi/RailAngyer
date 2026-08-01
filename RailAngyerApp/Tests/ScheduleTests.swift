import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 予定と出欠（SC-21 / フェーズ3）。
///
/// **立てた人だけが直せる**ことと、**出欠は自分のぶんだけ**動かせることを確かめる。
/// サーバー側でも同じ判定をしているが、圏外で書いたものが後から弾かれると分かりにくい。
@MainActor
struct ScheduleTests {

    private let context: ModelContext
    private let store: GameSessionStore
    private let startAt = Date(timeIntervalSince1970: 1_786_000_000)

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    @Test("予定を立てると一覧に出る")
    func saveAppearsInList() throws {
        let error = store.saveSchedule(nil, title: "南北線を歩く",
                                       startAt: startAt, meetPlace: "麻生駅 改札前")

        #expect(error == nil)
        let schedule = try #require(store.schedules.first)
        #expect(schedule.title == "南北線を歩く")
        #expect(schedule.meetPlace == "麻生駅 改札前")
        #expect(schedule.createdById == store.me?.id)
    }

    @Test("名前が空なら立てられない")
    func rejectsEmptyTitle() {
        let error = store.saveSchedule(nil, title: "  ", startAt: startAt, meetPlace: nil)

        #expect(error != nil)
        #expect(store.schedules.isEmpty)
    }

    @Test("予定には最初に決めたルールセットが残る")
    func savesRuleSet() throws {
        let course = try #require(store.room?.course)

        let error = store.saveSchedule(nil, title: "地下鉄を歩く", startAt: startAt,
                                       meetPlace: nil, course: course,
                                       startOrder: 2, goalOrder: 10, diceMax: 4)

        #expect(error == nil)
        let schedule = try #require(store.schedules.first)
        #expect(schedule.courseName == "南北線")
        #expect(schedule.startOrder == 2)
        #expect(schedule.goalOrder == 10)
        #expect(schedule.diceMax == 4)
    }

    @Test("集合場所は空なら持たない")
    func emptyMeetPlaceBecomesNil() throws {
        store.saveSchedule(nil, title: "歩く", startAt: startAt, meetPlace: "   ")

        #expect(try #require(store.schedules.first).meetPlace == nil)
    }

    @Test("他の人が立てた予定は書き換えられない")
    func rejectsEditingOthers() throws {
        let room = try #require(store.room)
        let other = Member(displayName: "ケンタ")
        other.missionSet = room
        context.insert(other)

        let theirs = Schedule(title: "ケンタの予定", startAt: startAt)
        theirs.missionSet = room
        theirs.createdById = other.id
        context.insert(theirs)
        try context.save()

        let error = store.saveSchedule(theirs, title: "勝手に書き換え",
                                       startAt: startAt, meetPlace: nil)

        #expect(error != nil)
        #expect(theirs.title == "ケンタの予定")
    }

    @Test("出欠を答えると自分のぶんだけが変わる")
    func answersOwnAttendanceOnly() throws {
        store.saveSchedule(nil, title: "歩く", startAt: startAt, meetPlace: nil)
        let schedule = try #require(store.schedules.first)

        // 他の人の出欠が先に入っている状態にする
        let theirs = Attendance(memberId: UUID(), displayName: "ケンタ", status: .going)
        theirs.schedule = schedule
        context.insert(theirs)
        try context.save()

        store.answerAttendance(schedule, status: .notGoing)

        #expect(store.myAttendance(schedule) == .notGoing)
        #expect(theirs.status == .going)                  // 他人のぶんは動かない
        #expect(schedule.attendees.count == 2)
    }

    @Test("何度答え直しても自分の行は1つ")
    func answeringTwiceKeepsOneRow() throws {
        store.saveSchedule(nil, title: "歩く", startAt: startAt, meetPlace: nil)
        let schedule = try #require(store.schedules.first)

        store.answerAttendance(schedule, status: .going)
        store.answerAttendance(schedule, status: .notGoing)
        store.answerAttendance(schedule, status: .going)

        #expect(schedule.attendees.count == 1)
        #expect(store.myAttendance(schedule) == .going)
    }

    @Test("これからの予定が先、終わった予定は後ろ")
    func upcomingComesFirst() throws {
        let past = Date().addingTimeInterval(-86_400)
        let soon = Date().addingTimeInterval(3_600)
        let later = Date().addingTimeInterval(86_400)

        store.saveSchedule(nil, title: "終わった", startAt: past, meetPlace: nil)
        store.saveSchedule(nil, title: "あとで", startAt: later, meetPlace: nil)
        store.saveSchedule(nil, title: "もうすぐ", startAt: soon, meetPlace: nil)

        #expect(store.schedules.map(\.title) == ["もうすぐ", "あとで", "終わった"])
    }

    @Test("消すと一覧から消える")
    func deleteRemovesFromList() throws {
        store.saveSchedule(nil, title: "歩く", startAt: startAt, meetPlace: nil)
        let schedule = try #require(store.schedules.first)

        store.deleteSchedule(schedule)

        #expect(store.schedules.isEmpty)
    }

    @Test("立てた予定はその場で一覧に出る")
    func newScheduleAppearsImmediately() throws {
        #expect(store.schedules.isEmpty)

        store.saveSchedule(nil, title: "南北線を歩く", startAt: startAt, meetPlace: nil)

        // 一覧はその場で読み直す。fetch のままだと画面が描き直されず、
        // 「追加したのに出てこない」ように見えていた
        #expect(store.schedules.map(\.title) == ["南北線を歩く"])
        #expect(store.nextSchedule?.title == "南北線を歩く")
    }

    @Test("消した予定はその場で一覧から消える")
    func deletedScheduleDisappearsImmediately() throws {
        store.saveSchedule(nil, title: "歩く", startAt: startAt, meetPlace: nil)
        let schedule = try #require(store.schedules.first)

        store.deleteSchedule(schedule)

        #expect(store.schedules.isEmpty)
    }
}
