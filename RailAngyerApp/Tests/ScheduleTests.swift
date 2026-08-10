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
    /// **固定の日時を書かない。** 以前は `1_786_000_000` と書いていて、
    /// その日を過ぎた日に「立てた予定はその場で一覧に出る」が突然落ちた
    /// （`nextSchedule` は先の予定しか返さない）。いまから見た未来にする
    private let startAt = Date().addingTimeInterval(7 * 24 * 60 * 60)

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

    // MARK: - 予定を旅に効かせる
    //
    // **同梱マスタは `serverId` を持たない。** サーバーIDだけでコースを引き当てていたころは、
    // ルーム未参加（＝この端末だけで遊ぶ）と圏外でコースの切り替えが丸ごと素通りし、
    // それでいて区間だけが別路線の駅番号で上書きされていた。
    // 番号が重なるので画面には何も出ず、気づけない壊れ方をする。

    private func course(_ name: String) throws -> Course {
        try #require(store.courses.first { $0.name == name })
    }

    private func stations(of course: Course) -> [Station] {
        course.stations.sorted { $0.orderNo < $1.orderNo }
    }

    @Test("予定で選んだコースが、サーバーIDが無くても旅に効く")
    func appliesPlannedCourseWithoutServerId() throws {
        let tozai = try course("東西線")
        let ordered = stations(of: tozai)
        let start = try #require(ordered.dropFirst(2).first)
        let goal = try #require(ordered.dropFirst(6).first)
        // このテストが守りたい前提。同梱マスタに serverId が入るようになったら、
        // 名前で引き当てる経路は別の作り方で確かめ直すこと
        #expect(tozai.serverId == nil)

        let error = store.saveSchedule(nil, title: "東西線を歩く", startAt: startAt,
                                       meetPlace: nil, course: tozai,
                                       startOrder: start.orderNo, goalOrder: goal.orderNo,
                                       diceMax: 4)
        #expect(error == nil)

        let schedule = try #require(store.schedules.first)
        #expect(schedule.courseServerId == nil)
        #expect(store.room?.course?.name == "南北線")        // 取り込む前は既定のまま

        #expect(store.applySchedule(schedule) == nil)

        #expect(store.room?.course?.name == "東西線")
        #expect(store.room?.startStation?.name == start.name)
        #expect(store.room?.goalStation?.name == goal.name)
        #expect(store.engine?.diceMax == 4)
    }

    @Test("一周の予定は、出発した駅がそのままゴールになる")
    func appliesLappingPlan() throws {
        let yamanote = try course("山手線")
        let start = try #require(stations(of: yamanote).dropFirst(4).first)

        // 一周はスタート＝ゴールが正しい。ここで弾かれると予定そのものが立たない
        let error = store.saveSchedule(nil, title: "山手線を一周", startAt: startAt,
                                       meetPlace: nil, course: yamanote,
                                       startOrder: start.orderNo, goalOrder: start.orderNo,
                                       diceMax: 7, isLap: true)
        #expect(error == nil)

        let schedule = try #require(store.schedules.first)
        #expect(store.applySchedule(schedule) == nil)

        #expect(store.room?.course?.name == "山手線")
        #expect(store.room?.startStation?.name == start.name)
        #expect(store.room?.goalStation?.name == start.name)
        #expect(store.room?.isLap == true)
        #expect(store.engine?.diceMax == 7)
    }

    @Test("歩き始めたあとは、予定のルールを取り込まない")
    func doesNotApplyAfterWalkingStarted() throws {
        let tozai = try course("東西線")
        let ordered = stations(of: tozai)
        store.saveSchedule(nil, title: "東西線を歩く", startAt: startAt, meetPlace: nil,
                           course: tozai,
                           startOrder: try #require(ordered.first).orderNo,
                           goalOrder: try #require(ordered.last).orderNo, diceMax: 4)
        let schedule = try #require(store.schedules.first)

        store.roll(dice: 1)                       // ここで旅が始まる

        // すでに進んだ盤面と食い違うので、取り込まずに理由を返す（T-06）
        #expect(store.applySchedule(schedule) != nil)
        #expect(store.room?.course?.name == "南北線")
    }

    @Test("予定のコースが端末に無ければ、何も取り込まない")
    func rejectsPlanWithUnknownCourse() throws {
        let room = try #require(store.room)
        let beforeCourse = room.course?.name
        let beforeStart = room.startStation?.name
        let beforeGoal = room.goalStation?.name
        let beforeDice = room.diceMax

        // サーバーにしかない路線を指す予定。手元のマスタには無い
        let schedule = Schedule(title: "まだ無い路線を歩く", startAt: startAt)
        schedule.missionSet = room
        schedule.courseName = "銀座線"
        schedule.courseServerId = 999
        schedule.startOrder = 3
        schedule.goalOrder = 7
        schedule.diceMax = 9
        context.insert(schedule)
        try context.save()

        let error = store.applySchedule(schedule)

        // **中途半端に区間だけ写さない。** 駅の通し番号は路線をまたいで重なるので、
        // 別路線の番号を当てると、画面には何も出ないまま違う駅を指して進んでしまう
        #expect(error != nil)
        #expect(error?.contains("銀座線") == true)
        #expect(store.room?.course?.name == beforeCourse)
        #expect(store.room?.startStation?.name == beforeStart)
        #expect(store.room?.goalStation?.name == beforeGoal)
        #expect(store.room?.diceMax == beforeDice)      // 出目も含めて何も動かない
    }
}
