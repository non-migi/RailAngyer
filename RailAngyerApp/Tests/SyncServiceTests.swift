import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 送信キューと取り込み（11_API設計.md §4 / 実装順 8）。
///
/// 確かめたいことは一つに尽きる。**圏外で遊んでも後から揃うこと。**
/// 実際の通信は `StubURLProtocol` で差し替えるので、サーバーには触らない。
@MainActor
struct SyncServiceTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let credentials: InMemoryCredentialStore
    private let room: MissionSet

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)

        let course = try MasterSeeder.seedIfNeeded(context)
        room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)

        // 送信の中身は駅のサーバーIDなので、参加時に取り込んである前提で始める
        // （取り込みそのものは「マスタのサーバーIDを取り込む」で確かめる）
        course.serverId = 1
        for station in course.stations { station.serverId = station.orderNo }
        try context.save()

        credentials = InMemoryCredentialStore(
            RoomCredentials(roomId: UUID(), memberId: UUID(), token: "test-token"))
    }

    private func makeService(_ stub: StubURLProtocol.Behavior = .offline) -> SyncService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.behavior = stub

        let client = ApiClient(baseURL: URL(string: "https://example.invalid")!,
                               credentials: credentials,
                               session: URLSession(configuration: config))
        return SyncService(context: context, client: client, credentials: credentials)
    }

    private func station(_ orderNo: Int) -> Station? {
        room.course?.stations.first { $0.orderNo == orderNo }
    }

    @discardableResult
    private func makeTurn() -> Turn {
        let turn = Turn(turnNo: 1, diceValue: 3)
        turn.missionSet = room
        turn.fromStation = station(1)
        turn.landingStation = station(4)
        context.insert(turn)
        return turn
    }

    @discardableResult
    private func makeVisit(turn: Turn) -> Visit {
        let visit = Visit(kind: .passing)
        visit.missionSet = room
        visit.turn = turn
        visit.station = station(2)
        context.insert(visit)
        return visit
    }

    // MARK: - マスタ

    @Test("マスタのサーバーIDを取り込む")
    func pullMasterStampsServerIds() async throws {
        for station in room.course?.stations ?? [] { station.serverId = nil }
        try context.save()

        let service = makeService(.json("""
        [{"courseId":7,"name":"南北線","lineColor":"#00A85A",
          "stations":[{"stationId":101,"name":"麻生","orderNo":1,
                       "latitude":43.1,"longitude":141.3}]}]
        """))

        #expect(await service.pullMaster())
        #expect(room.course?.serverId == 7)
        #expect(station(1)?.serverId == 101)
    }

    @Test("マスタの取り込みで座標は上書きしない")
    func pullMasterKeepsCorrectedCoordinates() async throws {
        let corrected = 43.123456        // 現地で実測して直した値のつもり
        station(1)?.latitude = corrected
        try context.save()

        let service = makeService(.json("""
        [{"courseId":7,"name":"南北線","lineColor":"#00A85A",
          "stations":[{"stationId":101,"name":"麻生","orderNo":1,
                       "latitude":43.999,"longitude":141.999}]}]
        """))
        _ = await service.pullMaster()

        // サーバーの概値で実測値を潰すと、到着判定がまた合わなくなる
        #expect(station(1)?.latitude == corrected)
    }

    @Test("本物のサーバーが返したJSONでマスタを取り込める")
    func pullMasterAcceptsRealResponse() async throws {
        // 実際の GET /courses の応答を取っておいたもの。
        // 手で書いた見本だけで通していると、列名や日時の形が変わったときに気づけない
        let json = try fixture("courses")

        for station in room.course?.stations ?? [] { station.serverId = nil }
        try context.save()

        let service = makeService(.json(json))
        #expect(await service.pullMaster())

        #expect(room.course?.serverId == 1)
        #expect(station(1)?.serverId == 1)
        #expect(station(16)?.serverId == 16)
    }

    // MARK: - ルーム

    @Test("ルームの設定とメンバーを取り込む")
    func pullRoomAppliesSettings() async throws {
        let roomId = UUID()
        let meId = try #require(credentials.load()?.memberId)
        let service = makeService(.json("""
        {"roomId":"\(roomId.apiString)","name":"夏の南北線ツアー","courseId":1,
         "startStationId":3,"goalStationId":12,"diceMax":4,"inviteCode":"ABC123",
         "members":[{"memberId":"\(meId.apiString)","displayName":"のん",
                     "joinedAt":"2026-07-30T05:00:00Z"},
                    {"memberId":"\(UUID().apiString)","displayName":"ケンタ",
                     "joinedAt":"2026-07-30T05:01:00Z"}]}
        """))

        #expect(await service.pullRoom())

        // 区間と最大出目はサーバーが正。端末ごとに違う盤面で遊ばないように合わせる
        #expect(room.id == roomId)
        #expect(room.name == "夏の南北線ツアー")
        #expect(room.inviteCode == "ABC123")
        #expect(room.diceMax == 4)
        #expect(room.startStation?.orderNo == 3)
        #expect(room.goalStation?.orderNo == 12)
        #expect(room.members.count == 2)
        #expect(room.members.filter(\.isMe).map(\.displayName) == ["のん"])
    }

    @Test("本物のサーバーが返したJSONでルームを取り込める")
    func pullRoomAcceptsRealResponse() async throws {
        // 実際の GET /rooms/{id} の応答。**日時に Z が付かない**（SQLの DATETIME2 をそのまま返すため）。
        // 手で書いた見本には Z を付けてしまいがちで、この形はテストから漏れる
        let json = try fixture("room")
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8))
                                   as? [String: Any])
        let members = try #require(payload["members"] as? [[String: Any]])
        let rawId = try #require(members.first?["memberId"] as? String)
        let meId = try #require(UUID(uuidString: rawId))
        try credentials.save(RoomCredentials(roomId: UUID(), memberId: meId, token: "t"))

        let service = makeService(.json(json))
        #expect(await service.pullRoom())

        #expect(room.members.count == 2)
        #expect(room.members.filter(\.isMe).count == 1)
        #expect(room.members.allSatisfy { $0.joinedAt.timeIntervalSince1970 > 0 })
    }

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: StubURLProtocol.self)
            .url(forResource: name, withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("ルームの取り込みを二度行ってもメンバーが重複しない")
    func pullRoomIsIdempotent() async throws {
        let meId = try #require(credentials.load()?.memberId)
        let service = makeService(.json("""
        {"roomId":"\(UUID().apiString)","name":"ツアー","courseId":1,
         "startStationId":1,"goalStationId":16,"diceMax":6,"inviteCode":"ABC123",
         "members":[{"memberId":"\(meId.apiString)","displayName":"のん",
                     "joinedAt":"2026-07-30T05:00:00Z"}]}
        """))

        _ = await service.pullRoom()
        _ = await service.pullRoom()

        #expect(room.members.count == 1)
    }

    // MARK: - 積む

    @Test("ターンを積むと未送信件数が増える")
    func enqueueCountsUp() throws {
        let service = makeService()
        try service.enqueueTurn(makeTurn())

        #expect(service.pendingCount == 1)
    }

    @Test("同じターンへの更新は最新の1件にまとまる")
    func enqueueCollapsesUpdates() throws {
        let service = makeService()
        let turn = makeTurn()

        try service.enqueueTurn(turn)              // 振った直後
        turn.arrivedAt = Date()
        try service.enqueueTurn(turn)              // 着地した
        turn.missionDone = true
        try service.enqueueTurn(turn)              // ミッション達成

        // PUTは冪等なので、3回ぶん溜めても送るのは最後の状態だけでよい
        #expect(service.pendingCount == 1)

        let payload = try #require(try SyncQueue(context: context).pending().first?.payload)
        let json = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(json["missionDone"] as? Bool == true)
    }

    @Test("参加していなければ積まない")
    func enqueueRequiresJoin() throws {
        try credentials.clear()
        let service = makeService()

        try service.enqueueTurn(makeTurn())

        #expect(service.pendingCount == 0)
    }

    // MARK: - 送る

    @Test("オンラインなら送ってキューが空になる")
    func pushDrainsQueue() async throws {
        let service = makeService(.json("{}"))
        try service.enqueueTurn(makeTurn())

        let sent = await service.push()

        #expect(sent == 1)
        #expect(service.pendingCount == 0)
        #expect(service.lastSyncedAt != nil)
    }

    @Test("圏外ならキューに残り、電波が戻れば送れる")
    func pushKeepsQueueWhenOffline() async throws {
        let service = makeService(.offline)
        try service.enqueueTurn(makeTurn())

        #expect(await service.push() == 0)
        #expect(service.pendingCount == 1)          // プレイはこのまま続けられる

        StubURLProtocol.behavior = .json("{}")
        #expect(await service.push() == 1)
        #expect(service.pendingCount == 0)
    }

    @Test("送る順序は操作した順になる")
    func pushKeepsOrder() async throws {
        let service = makeService(.recordingPaths)
        let turn = makeTurn()
        try service.enqueueTurn(turn)
        try service.enqueueVisit(makeVisit(turn: turn))

        await service.push()

        let paths = StubURLProtocol.recordedPaths
        #expect(paths.count == 2)
        // 訪問が先に届くと、まだ存在しないターンに紐づけようとして弾かれる
        #expect(paths.first?.contains("/turns/") == true)
        #expect(paths.last?.contains("/visits/") == true)
    }

    @Test("失敗したらそこで止めて、後続に追い越させない")
    func pushStopsAtFirstFailure() async throws {
        let service = makeService(.failFirstThenSucceed(status: 503))
        let turn = makeTurn()
        try service.enqueueTurn(turn)
        try service.enqueueVisit(makeVisit(turn: turn))

        let sent = await service.push()

        // 飛ばして次を送ると、あとから古い状態が上書きしてしまう
        #expect(sent == 0)
        #expect(StubURLProtocol.recordedPaths.count == 1)
        #expect(service.pendingCount == 2)
    }

    @Test("何度送っても直らない失敗は捨てて、キューを詰まらせない")
    func pushDropsPermanentFailures() async throws {
        let service = makeService(
            .status(400, #"{"error":"invalid_dice","message":"出目が不正です"}"#))
        try service.enqueueTurn(makeTurn())

        let sent = await service.push()

        #expect(sent == 0)
        #expect(service.pendingCount == 0)   // 400を残すと以降の記録が永久に送れなくなる
        #expect(service.lastError == "出目が不正です")
    }

    @Test("トークンが無効なら捨てずに残す")
    func pushKeepsUnauthorized() async throws {
        let service = makeService(.status(401, ""))
        try service.enqueueTurn(makeTurn())

        await service.push()

        // 再参加すれば送れる内容なので、捨ててはいけない
        #expect(service.pendingCount == 1)
    }

    // MARK: - 取り込む

    @Test("サーバーの訪問を取り込む")
    func pullAddsVisits() async throws {
        let visitId = UUID()
        let service = makeService(.json("""
        {"currentStationId":4,"isCleared":false,"activeTurn":null,
         "visits":[{"visitId":"\(visitId.apiString)","turnId":null,
                    "stationId":3,"arrivedAt":"2026-07-30T05:22:11","visitKind":1}],
         "completedTurnCount":1}
        """))

        #expect(await service.pull())

        let visit = try #require(try context.fetch(FetchDescriptor<Visit>()).first)
        #expect(visit.id == visitId)
        #expect(visit.station?.serverId == 3)
        #expect(visit.visitKind == .passing)
    }

    @Test("進行中のターンを取り込む")
    func pullAddsActiveTurn() async throws {
        let turnId = UUID()
        let service = makeService(.json("""
        {"currentStationId":1,"isCleared":false,
         "activeTurn":{"turnId":"\(turnId.apiString)","turnNo":1,"diceValue":3,
                       "fromStationId":1,"landingStationId":4,
                       "rolledAt":"2026-07-30T05:22:11Z","arrivedAt":null,
                       "selectedMissionId":null,"missionDone":false,"appliedEffectType":null},
         "visits":[],"completedTurnCount":0}
        """))

        #expect(await service.pull())

        let turn = try #require(try context.fetch(FetchDescriptor<Turn>()).first)
        #expect(turn.id == turnId)
        #expect(turn.landingStation?.orderNo == 4)
        #expect(turn.isActive)
    }

    @Test("同じ訪問を二度取り込んでも増えない")
    func pullIsIdempotent() async throws {
        let visitId = UUID()
        let service = makeService(.json("""
        {"currentStationId":4,"isCleared":false,"activeTurn":null,
         "visits":[{"visitId":"\(visitId.apiString)","turnId":null,
                    "stationId":3,"arrivedAt":"2026-07-30T05:22:11Z","visitKind":1}],
         "completedTurnCount":1}
        """))

        _ = await service.pull()
        _ = await service.pull()

        #expect(try context.fetch(FetchDescriptor<Visit>()).count == 1)
    }

    @Test("取り込みはローカルにしかない記録を消さない")
    func pullKeepsLocalOnlyRecords() async throws {
        let service = makeService(.json("""
        {"currentStationId":1,"isCleared":false,"activeTurn":null,
         "visits":[],"completedTurnCount":0}
        """))
        let local = makeVisit(turn: makeTurn())        // まだ送っていない訪問

        _ = await service.pull()

        // 未送信の記録が消えると、歩いた事実そのものが失われる
        #expect(try context.fetch(FetchDescriptor<Visit>()).contains { $0.id == local.id })
    }

    @Test("参加をやめると未送信も消える")
    func leaveClearsQueue() throws {
        let service = makeService()
        try service.enqueueTurn(makeTurn())

        try service.leave()

        #expect(service.pendingCount == 0)
        #expect(!service.isJoined)
    }

    // MARK: - 予定の取り込み
    //
    // **ビルド6がここで落ちた。** 取り込みが画面と別のスレッドで走り、
    // SwiftData の保存が画面の読み出しと衝突していた（`EXC_BAD_ACCESS`）。
    // 直したうえで、そもそも中身が正しいことを押さえていなかったので足す。

    private func scheduleJSON(id: UUID, title: String = "南北線を歩く",
                              attendees: String = "[]") -> String {
        """
        [{"scheduleId":"\(id.uuidString)","title":"\(title)",
          "startAt":"2026-08-09T00:00:00Z","meetPlace":"麻生駅 改札前",
          "courseId":1,"courseName":"南北線","startOrder":1,"goalOrder":16,
          "diceMax":4,"createdBy":null,"attendees":\(attendees)}]
        """
    }

    @Test("サーバーの予定を取り込む")
    func pullSchedulesTakesRemote() async throws {
        let id = UUID()
        let service = makeService(.json(scheduleJSON(id: id)))

        #expect(await service.pullSchedules())

        let saved = try #require(try context.fetch(FetchDescriptor<Schedule>())
            .first { $0.id == id })
        #expect(saved.title == "南北線を歩く")
        #expect(saved.meetPlace == "麻生駅 改札前")
        #expect(saved.courseName == "南北線")
        #expect(saved.goalOrder == 16)
        #expect(saved.diceMax == 4)
        // 取り込んだものは送信済みとして扱う（送り返すと自分の更新で上書きしてしまう）
        #expect(saved.syncStateRaw == SyncState.synced.rawValue)
    }

    @Test("同じ予定を二度取り込んでも増えない")
    func pullSchedulesIsIdempotent() async throws {
        let id = UUID()
        let service = makeService(.json(scheduleJSON(id: id)))

        _ = await service.pullSchedules()
        StubURLProtocol.behavior = .json(scheduleJSON(id: id, title: "予定を直した"))
        _ = await service.pullSchedules()

        let all = try context.fetch(FetchDescriptor<Schedule>()).filter { $0.id == id }
        #expect(all.count == 1)
        #expect(all.first?.title == "予定を直した")
    }

    @Test("出欠も取り込み、二度目は重ならない")
    func pullSchedulesTakesAttendees() async throws {
        let id = UUID()
        let member = UUID()
        let attendees = """
        [{"memberId":"\(member.uuidString)","displayName":"ケンタ","status":1}]
        """
        let service = makeService(.json(scheduleJSON(id: id, attendees: attendees)))

        _ = await service.pullSchedules()
        _ = await service.pullSchedules()

        let saved = try #require(try context.fetch(FetchDescriptor<Schedule>())
            .first { $0.id == id })
        #expect(saved.attendees.count == 1)
        #expect(saved.attendees.first?.displayName == "ケンタ")
    }

    @Test("サーバーから消えた予定は端末からも消える")
    func pullSchedulesRemovesDeleted() async throws {
        let id = UUID()
        let service = makeService(.json(scheduleJSON(id: id)))
        _ = await service.pullSchedules()

        StubURLProtocol.behavior = .json("[]")
        _ = await service.pullSchedules()

        // 消えた予定が端末に残ると、集合場所を取り違える
        #expect(try context.fetch(FetchDescriptor<Schedule>()).isEmpty)
    }

    @Test("まだ送っていない予定は、取り込みで消さない")
    func pullSchedulesKeepsUnsent() async throws {
        let service = makeService(.json("[]"))
        let mine = Schedule(title: "まだ送っていない予定", startAt: Date())
        mine.missionSet = room
        context.insert(mine)
        try context.save()

        _ = await service.pullSchedules()

        // 立てた直後に取り込みが走る（`syncAfterEdit`）。ここで消えると予定が作れない
        #expect(try context.fetch(FetchDescriptor<Schedule>()).contains { $0.id == mine.id })
    }
}

/// 通信の差し替え。実際のHTTPは出さない
final class StubURLProtocol: URLProtocol {

    enum Behavior {
        /// 圏外
        case offline
        case json(String)
        case status(Int, String)
        /// 送信順を記録しつつ 200 を返す
        case recordingPaths
        /// 1件目だけ失敗させる
        case failFirstThenSucceed(status: Int)
    }

    nonisolated(unsafe) private static var _behavior: Behavior = .offline
    nonisolated(unsafe) private static var _paths: [String] = []
    private static let lock = NSLock()

    static var behavior: Behavior {
        get { lock.withLock { _behavior } }
        set { lock.withLock { _behavior = newValue; _paths = [] } }
    }

    static var recordedPaths: [String] { lock.withLock { _paths } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        let outcome: (status: Int, body: String)? = Self.lock.withLock {
            Self._paths.append(path)
            switch Self._behavior {
            case .offline:
                return nil
            case .json(let body):
                return (200, body)
            case .status(let status, let body):
                return (status, body)
            case .recordingPaths:
                return (200, "{}")
            case .failFirstThenSucceed(let status):
                return Self._paths.count == 1 ? (status, "") : (200, "{}")
            }
        }

        guard let outcome else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: outcome.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(outcome.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
