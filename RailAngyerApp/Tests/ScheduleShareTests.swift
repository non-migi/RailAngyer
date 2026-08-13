import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 予定をアプリの外へ持ち出す文（`ScheduleShare`）。
///
/// **相手がこのアプリを入れていなくても伝わる**ことが要件。だから確かめるのは
/// 「日時・場所・区間・歩く目安が文だけで読めるか」と、
/// **招待コードや内部のIDが混ざっていないか**（誘う相手とルームに入れる相手は別の話）。
@MainActor
final class ScheduleShareTests {

    private let context: ModelContext
    private let store: GameSessionStore
    /// 2026-08-09(日) 09:00 JST。
    /// **ここは固定でよい。** 「8月9日(日) 9:00」と書けることを確かめる試験があり、
    /// 日時が動くと確かめようがない。先の予定かどうかは見ていない
    private let startAt = Date(timeIntervalSince1970: 1_786_233_600)

    /// 試験の前に選ばれていた言語。終わったら戻す
    private let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)

    init() throws {
        // **言語は日本語に固定する。** 「8月9日(日) 9:00」の形を確かめる試験があり、
        // 共有の文はアプリ内で選んだ言語に追随する。端末の言語に任せると
        // 日本語以外のシミュレータで確かめようがなくなる
        UserDefaults.standard.set(AppLanguage.ja.rawValue, forKey: AppLanguage.storageKey)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    deinit {
        if let previousLanguage {
            UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        }
    }

    private func course(_ name: String) throws -> Course {
        try #require(store.courses.first { $0.name == name })
    }

    /// ルールセットまで決めた予定を1つ作る。
    /// 一覧の並び順に頼らず、付けた名前で引き当てる（同じ時刻の予定を複数作るため）
    private func schedule(title: String = "南北線を歩く",
                          startOrder: Int = 1, goalOrder: Int = 16,
                          meetPlace: String? = "麻生駅 改札前",
                          courseName: String = "南北線") throws -> Schedule {
        let error = store.saveSchedule(nil, title: title, startAt: startAt,
                                       meetPlace: meetPlace,
                                       course: try course(courseName),
                                       startOrder: startOrder, goalOrder: goalOrder, diceMax: 4)
        #expect(error == nil)
        return try #require(store.schedules.first { $0.title == title })
    }

    @Test("共有の文に、日時・集合・区間・サイコロ・目安が並ぶ")
    func textCarriesEverythingNeeded() throws {
        let schedule = try schedule()

        let text = ScheduleShare.text(for: schedule, course: try course("南北線"))

        #expect(text.contains("【レイルアンギャー】南北線を歩く"))
        #expect(text.contains("8月9日(日) 9:00"))
        #expect(text.contains("麻生駅 改札前"))
        #expect(text.contains("南北線（北海道）"))
        #expect(text.contains("麻生 → 真駒内"))
        #expect(text.contains("16駅"))
        #expect(text.contains("サイコロ 1〜4"))
        #expect(text.contains("歩く目安"))
        #expect(text.contains("https://maps.apple.com/"))
    }

    @Test("日時は日本時間・日本の曜日で書く")
    func dateTextIsJapanese() {
        // 端末の時計や言語がどこであっても、集合時刻は日本時間で読ませる
        #expect(ScheduleShare.dateText(startAt) == "8月9日(日) 9:00")
    }

    @Test("内部のIDや招待コードは載せない")
    func textHidesInternalIdentifiers() throws {
        let schedule = try schedule()
        let room = try #require(store.room)

        let text = ScheduleShare.text(for: schedule, course: try course("南北線"))

        #expect(!text.contains(schedule.id.uuidString))
        #expect(!text.contains(room.id.uuidString))
        if let code = room.inviteCode { #expect(!text.contains(code)) }
    }

    @Test("区間は向きを逆に決めても通し番号の順で返る")
    func sectionStationsAreAlwaysInOrder() throws {
        let schedule = try schedule(startOrder: 10, goalOrder: 4)

        let stations = ScheduleShare.sectionStations(schedule, course: try course("南北線"))

        #expect(stations.map(\.orderNo) == Array(4...10))
    }

    @Test("目安は区間の長さについて変わる")
    func estimateFollowsSection() throws {
        let nanboku = try course("南北線")
        let whole = try schedule(title: "全線", startOrder: 1, goalOrder: 16)
        let part = try schedule(title: "3駅だけ", startOrder: 1, goalOrder: 3)

        let full = try #require(ScheduleShare.estimate(whole, course: nanboku))
        let short = try #require(ScheduleShare.estimate(part, course: nanboku))
        #expect(short.meters < full.meters)
        #expect(short.seconds < full.seconds)
    }

    @Test("駅が1つだけの区間には目安を出さない")
    func noEstimateForSingleStation() throws {
        // 同じ駅を指す区間は予定として作れない（`saveSchedule` が弾く）。
        // ただし他の端末やサーバー由来の予定は入ってきうるので、直接その形を作って確かめる
        let schedule = Schedule(title: "同じ駅", startAt: startAt)
        schedule.courseName = "南北線"
        schedule.startOrder = 5
        schedule.goalOrder = 5
        context.insert(schedule)
        try context.save()

        #expect(ScheduleShare.estimate(schedule, course: try course("南北線")) == nil)
        // 文は作れる。目安の行だけが落ちる
        #expect(ScheduleShare.text(for: schedule, course: try course("南北線"))
            .contains("歩く目安") == false)
    }

    @Test("コースが分からない古い予定でも文は作れる")
    func worksWithoutCourse() throws {
        // 予定はコースを決める前の版でも作れていた。落ちずに、日時と場所だけ出す
        store.saveSchedule(nil, title: "どこかを歩く", startAt: startAt, meetPlace: "札幌駅")
        let schedule = try #require(store.schedules.first)

        let text = ScheduleShare.text(for: schedule, course: nil)

        #expect(text.contains("どこかを歩く"))
        #expect(text.contains("札幌駅"))
        #expect(!text.contains("歩く目安"))
        #expect(ScheduleShare.estimate(schedule, course: nil) == nil)
        #expect(ScheduleShare.mapURL(schedule, course: nil) == nil)
    }

    @Test("地図のリンクはスタート駅の座標と集合場所を指す")
    func mapURLPointsAtStart() throws {
        let schedule = try schedule(startOrder: 1, goalOrder: 16)

        let url = try #require(ScheduleShare.mapURL(schedule, course: try course("南北線")))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        // 麻生（43.11 / 141.34 付近）
        let ll = try #require(items.first { $0.name == "ll" }?.value)
        #expect(ll.hasPrefix("43.1"))
        #expect(ll.contains("141.3"))
        #expect(items.first { $0.name == "q" }?.value == "麻生駅 改札前")
    }

    @Test("集合場所を書いていなければ、スタート駅の名前で探させる")
    func mapURLFallsBackToStationName() throws {
        let schedule = try schedule(meetPlace: nil)

        let url = try #require(ScheduleShare.mapURL(schedule, course: try course("南北線")))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.first { $0.name == "q" }?.value == "麻生駅")
    }

    @Test("出欠は誰かが答えてから出す")
    func attendanceAppearsOnlyWhenAnswered() throws {
        let schedule = try schedule()
        #expect(ScheduleShare.attendanceText(schedule) == nil)

        store.answerAttendance(schedule, status: .going)
        #expect(ScheduleShare.attendanceText(schedule) == "参加 1人")

        let theirs = Attendance(memberId: UUID(), displayName: "ケンタ", status: .notGoing)
        theirs.schedule = schedule
        context.insert(theirs)
        try context.save()
        #expect(ScheduleShare.attendanceText(schedule) == "参加 1人・不参加 1人")
    }

    // MARK: - お題とルームの共有

    @Test("お楽しみの設定では、共有の文にお題を出さない")
    func hidesMissionsWhenSurprise() throws {
        let schedule = try schedule()
        store.saveMission(nil, station: 3, content: "駅名標を撮る",
                          effect: .none, value: nil, jumpTo: nil)
        // **既定は「いつでも見える」。** 伏せる側は選んだときだけなので、ここで明示する
        store.updateMissionVisibility(.surprise)

        let text = ScheduleShare.text(for: schedule, course: try course("南北線"),
                                      room: store.room)

        // 共有した先で読めてしまうと、その場で設定を守った意味がなくなる
        #expect(!text.contains("駅名標を撮る"))
        #expect(!text.contains("📝"))
    }

    @Test("いつでも見える設定なら、共有の文にお題も載る")
    func sharesMissionsWhenAlways() throws {
        let schedule = try schedule()
        store.saveMission(nil, station: 3, content: "駅名標を撮る",
                          effect: .none, value: nil, jumpTo: nil)
        store.updateMissionVisibility(.always)

        let text = ScheduleShare.text(for: schedule, course: try course("南北線"),
                                      room: store.room)

        #expect(text.contains("駅名標を撮る"))
        #expect(text.contains("📝 お題"))
    }

    @Test("区間の外に書いたお題は共有しない")
    func sharesOnlyMissionsInSection() throws {
        let schedule = try schedule(startOrder: 1, goalOrder: 4)
        store.saveMission(nil, station: 3, content: "区間の中",
                          effect: .none, value: nil, jumpTo: nil)
        store.saveMission(nil, station: 12, content: "区間の外",
                          effect: .none, value: nil, jumpTo: nil)
        store.updateMissionVisibility(.always)

        let text = ScheduleShare.text(for: schedule, course: try course("南北線"),
                                      room: store.room)

        #expect(text.contains("区間の中"))
        #expect(!text.contains("区間の外"))
    }

    @Test("共有の文からアプリを開いてルームへ入れる")
    func sharesRoomInvite() throws {
        let schedule = try schedule()
        let room = try #require(store.room)
        room.inviteCode = "ABC123"
        try context.save()

        let text = ScheduleShare.text(for: schedule, course: try course("南北線"), room: room)

        // **地図ではなくアプリへ誘う。** 見てほしいのは集合場所ではなく、参加そのもの
        #expect(text.contains("railangyer://join?code=ABC123"))
        // アプリを入れていない相手にはリンクが効かないので、コードも文字で残す
        #expect(text.contains("招待コード：ABC123"))
        #expect(!text.contains("https://maps.apple.com/"))
    }

    @Test("招待コードが無いときは、これまでどおり地図のリンクを出す")
    func fallsBackToMapWithoutInvite() throws {
        let schedule = try schedule()
        store.room?.inviteCode = nil
        try context.save()

        let text = ScheduleShare.text(for: schedule, course: try course("南北線"),
                                      room: store.room)

        #expect(text.contains("https://maps.apple.com/"))
        #expect(!text.contains("railangyer://"))
    }

    // MARK: - 一周の予定
    //
    // **一周はスタートとゴールが同じ駅。** そのまま範囲として扱うと1駅しか取れず、
    // 地図も歩く目安も出なくなる（札幌市電の予定で実際に起きた）

    private func lapSchedule(courseName: String = "札幌市電") throws -> (Schedule, Course) {
        let course = try course(courseName)
        let first = try #require(course.stationsInOrder.first)
        let error = store.saveSchedule(nil, title: "市電を一周", startAt: startAt, meetPlace: nil,
                                       course: course, startOrder: first.orderNo,
                                       goalOrder: first.orderNo, diceMax: 4, isLap: true)
        #expect(error == nil)
        return (try #require(store.schedules.first { $0.title == "市電を一周" }), course)
    }

    @Test("一周の予定では、コース全体の駅が対象になる")
    func lapCoversWholeCourse() throws {
        let (schedule, course) = try lapSchedule()

        let stations = ScheduleShare.sectionStations(schedule, course: course)

        // 1駅しか返らないと、地図（2駅以上で出る）が消える
        #expect(stations.count == course.stations.count)
        #expect(stations.count > 2)
    }

    @Test("一周の予定にも歩く目安が出る")
    func lapHasEstimate() throws {
        let (schedule, course) = try lapSchedule()

        let estimate = try #require(ScheduleShare.estimate(schedule, course: course))

        // 出発した駅へ戻るぶんまで数える。片道より長い
        let oneWay = WalkEstimator.estimate(points: course.stationsInOrder)
        #expect(estimate.meters > oneWay.meters)
    }

    @Test("一周の予定は「◯◯から一周」と書く")
    func lapCourseText() throws {
        let (schedule, course) = try lapSchedule()

        let text = ScheduleShare.courseText(schedule, course: course)

        #expect(text.contains("から一周"))
        #expect(!text.contains("→"))
    }

    @Test("県をまたぐコースは通る県をすべて書く")
    func crossingCourseShowsEveryRegion() throws {
        let hankyu = try course("阪急京都本線")
        let error = store.saveSchedule(nil, title: "阪急を歩く", startAt: startAt, meetPlace: nil,
                                       course: hankyu, startOrder: 1,
                                       goalOrder: hankyu.stations.count, diceMax: 6)
        #expect(error == nil)
        let schedule = try #require(store.schedules.first)

        let text = ScheduleShare.courseText(schedule, course: hankyu)

        #expect(text.contains("阪急京都本線（大阪府・京都府）"))
        #expect(text.contains("大阪梅田 → 京都河原町"))
    }
}
