import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 送信キューと取り込み（11_API設計.md §4 / 実装順 8）。
///
/// 確かめたいことは一つに尽きる。**圏外で遊んでも後から揃うこと。**
/// 実際の通信は `StubURLProtocol` で差し替えるので、サーバーには触らない。
/// 差し替えはテストごとの `StubSession` に閉じているので、並べて走らせても混ざらない。
@MainActor
struct SyncServiceTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let credentials: InMemoryCredentialStore
    private let room: MissionSet

    /// この1件ぶんの通信の差し替え。**テストごとに新しく作られる**
    private let stub = StubSession()

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

    private func makeService(_ behavior: StubURLProtocol.Behavior = .offline) -> SyncService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        stub.open(behavior)

        let client = ApiClient(baseURL: stub.baseURL,
                               credentials: credentials,
                               session: URLSession(configuration: config))
        return SyncService(context: context, client: client, credentials: credentials)
    }

    /// いまの現在地。`GameSessionStore.currentOrder` と同じ数え方
    private var currentOrder: Int {
        let completed = room.turns
            .filter { $0.completedAt != nil }
            .max { $0.turnNo < $1.turnNo }
        return completed?.endPosition
            ?? completed?.endStation?.orderNo
            ?? room.startStation?.orderNo ?? 1
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

    /// `Photo.member` は inverse の無い一方向の参照なので、メンバーの行だけ消すと
    /// **消えた行を指したまま**になり、名前を読んだ瞬間に落ちる。
    /// 退室した人の写真が一覧に出るだけでクラッシュしていた
    @Test("退室した人でも、撮った写真があればメンバーの行を消さない")
    func pullRoomKeepsPhotographers() async throws {
        let meId = try #require(credentials.load()?.memberId)
        let gone = Member(displayName: "ケンタ")
        gone.missionSet = room
        context.insert(gone)

        let visit = makeVisit(turn: makeTurn())
        let photo = Photo(localFileName: "kenta.jpg")
        photo.visit = visit
        photo.member = gone
        context.insert(photo)
        try context.save()

        // サーバーの名簿からケンタが消えた（退室した）
        let service = makeService(.json("""
        {"roomId":"\(UUID().apiString)","name":"ツアー","courseId":1,
         "startStationId":1,"goalStationId":16,"diceMax":6,"inviteCode":"ABC123",
         "members":[{"memberId":"\(meId.apiString)","displayName":"のん",
                     "joinedAt":"2026-07-30T05:00:00Z"}]}
        """))

        #expect(await service.pullRoom())

        #expect(room.members.contains { $0.id == gone.id }, "撮った人の行が消えている")
        #expect(photo.member?.displayName == "ケンタ", "写真から撮った人をたどれない")
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

        stub.update(.json("{}"))
        #expect(await service.push() == 1)
        #expect(service.pendingCount == 0)
    }

    /// めいめいで取り組む旅では、引いたお題は**その端末のもの**。
    /// ターン1件にお題は1つしか持てないので、送ると各自の引きで上書きし合う
    @Test("めいめいで取り組む旅では、引いたお題を送らない")
    func individualStyleKeepsMissionLocal() throws {
        room.missionStyle = .individual
        let mission = Mission(content: "駅名標を撮る")
        mission.missionSet = room
        mission.station = station(4)
        context.insert(mission)

        let turn = makeTurn()
        turn.selectedMission = mission
        turn.missionDone = true
        // **`EffectType` と書く。** 型を省くと `Optional.none`（＝nil）が入り、
        // 「判定の済んだお題」のつもりが判定前の形になってしまう。
        // nil のままだと、下の `appliedEffectType == nil` は
        // めいめい方式の除外が効いていなくても通ってしまい、試験にならない
        turn.appliedEffectType = EffectType.none
        try context.save()

        let service = makeService()
        try service.enqueueTurn(turn)

        let payload = try #require(try SyncQueue(context: context).pending().first?.payload)
        let json = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(json["selectedMissionId"] == nil, "自分の引きを送ってしまっている")
        #expect(json["missionDone"] == nil)
        #expect(json["appliedEffectType"] == nil)
        // 盤面（どこからどこへ動いたか）は共有する
        #expect(json["fromStationId"] as? Int == 1)
        #expect(json["landingStationId"] as? Int == 4)
    }

    /// みんなで1つのお題に取り組む旅では、**判定が仲間の端末にも届く**こと。
    ///
    /// `appliedEffectType` が nil のまま送られていたころは、
    /// 送り主の画面では達成になっても、仲間の画面では永久に「進行中」だった
    @Test("みんなで取り組む旅では、お題の判定も送る")
    func sharedStyleSendsMissionResult() throws {
        let mission = Mission(content: "駅名標を撮る")
        mission.missionSet = room
        mission.station = station(4)
        context.insert(mission)

        let turn = makeTurn()
        turn.selectedMission = mission
        turn.missionDone = true
        turn.appliedEffectType = EffectType.none      // 効果なしのお題を、達成で片づけた
        try context.save()

        let service = makeService()
        try service.enqueueTurn(turn)

        let payload = try #require(try SyncQueue(context: context).pending().first?.payload)
        let json = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(json["selectedMissionId"] as? String != nil, "どのお題かが伝わらない")
        #expect(json["missionDone"] as? Bool == true)
        // 効果なし（0）も**入れて送る**。抜けると受け取った側は判定前と区別できない
        #expect(json["appliedEffectType"] as? Int == 0, "判定が仲間に届かない")
    }

    @Test("チームで取り組む旅では、これまで通り引いたお題も送る")
    func teamStyleSendsMission() throws {
        let mission = Mission(content: "駅名標を撮る")
        mission.missionSet = room
        mission.station = station(4)
        context.insert(mission)

        let turn = makeTurn()
        turn.selectedMission = mission
        turn.missionDone = true
        try context.save()

        let service = makeService()
        try service.enqueueTurn(turn)

        let payload = try #require(try SyncQueue(context: context).pending().first?.payload)
        let json = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(json["selectedMissionId"] as? String == mission.id.uuidString)
        #expect(json["missionDone"] as? Bool == true)
    }

    // MARK: - 写真（§5 / G-6）

    @Test("写真は SAS → Blob → メタ登録 の順で上がり、上げた印が付く")
    func pushPhotosFollowsThreeSteps() async throws {
        let visit = makeVisit(turn: makeTurn())
        let photo = Photo(localFileName: try PhotoStore.save(data: Data("jpeg".utf8)))
        photo.visit = visit
        context.insert(photo)
        try context.save()
        defer { PhotoStore.delete(photo.localFileName) }

        let ticket = """
        {"photoId":"\(photo.id.apiString)","blobPath":"room/visit/photo.jpg",
         "uploadUrl":"\(stub.blobHost)/room/visit/photo.jpg?sig=abc",
         "expiresAt":"2026-08-11T12:00:00Z"}
        """
        let service = makeService(.bodies([(match: "upload-url", body: ticket)]))

        #expect(await service.pushPhotos() == 1)
        #expect(photo.blobUrl == "room/visit/photo.jpg", "上げた印が付いていない")

        let paths = stub.recordedPaths
        #expect(paths.count == 3)
        #expect(paths.first?.contains("/photos/upload-url") == true)
        // 実体は**APIを通らない**でBlobへ直接
        #expect(paths[1] == "/room/visit/photo.jpg")
        #expect(paths.last?.contains("/photos/\(photo.id.apiString)") == true,
                "メタの登録は実体を上げ終えた後")
    }

    @Test("上げ終えた写真は二度と上げ直さない")
    func pushPhotosSkipsUploaded() async throws {
        let visit = makeVisit(turn: makeTurn())
        let photo = Photo(localFileName: try PhotoStore.save(data: Data("jpeg".utf8)))
        photo.visit = visit
        photo.blobUrl = "room/visit/photo.jpg"
        context.insert(photo)
        try context.save()
        defer { PhotoStore.delete(photo.localFileName) }

        let service = makeService(.recordingPaths)

        #expect(await service.pushPhotos() == 0)
        #expect(stub.recordedPaths.isEmpty)
    }

    @Test("仲間の写真を取り込み、実体を端末に保存して訪問に紐づける")
    func pullPhotosSavesOthersPhotos() async throws {
        let visit = makeVisit(turn: makeTurn())
        try context.save()

        let photoId = UUID()
        let takenBy = UUID()
        let list = """
        [{"photoId":"\(photoId.apiString)","visitId":"\(visit.id.apiString)","stationId":2,
          "takenBy":"\(takenBy.apiString)","takenByName":"ケンタ",
          "takenAt":"2026-08-11T09:30:00Z",
          "url":"\(stub.blobHost)/room/visit/photo.jpg?sig=abc",
          "urlExpiresAt":"2026-08-11T12:00:00Z"}]
        """
        let service = makeService(.bodies([(match: "/photos", body: list)]))

        #expect(await service.pullPhotos() == 1)

        let saved = try #require(visit.photos.first)
        defer { PhotoStore.delete(saved.localFileName) }
        #expect(saved.id == photoId)
        #expect(saved.member?.displayName == "ケンタ", "撮った人が分かる")
        #expect(PhotoStore.exists(saved.localFileName), "実体が端末に残っていない")
        // 期限付きの署名は持たない。切れると意味を失うため
        #expect(saved.blobUrl?.contains("sig=") == false)

        // 二度目は取りに行かない（同じ写真を何枚も増やさない）
        #expect(await service.pullPhotos() == 0)
        #expect(visit.photos.count == 1)
    }

    /// 消した直後はサーバーにまだ残っている。**取り込みで蘇らせない**
    @Test("削除待ちの写真は取り込みで戻ってこない")
    func pullPhotosSkipsPendingDeletions() async throws {
        let visit = makeVisit(turn: makeTurn())
        try context.save()

        let photoId = UUID()
        let list = """
        [{"photoId":"\(photoId.apiString)","visitId":"\(visit.id.apiString)","stationId":2,
          "takenBy":"\(UUID().apiString)","takenByName":"ケンタ",
          "takenAt":"2026-08-11T09:30:00Z",
          "url":"\(stub.blobHost)/room/visit/photo.jpg?sig=abc",
          "urlExpiresAt":"2026-08-11T12:00:00Z"}]
        """
        let service = makeService(.bodies([(match: "/photos", body: list)]))
        try service.enqueuePhotoDelete(photoId: photoId)   // 消した。まだ送れていない

        #expect(await service.pullPhotos() == 0)
        #expect(visit.photos.isEmpty, "消した写真が戻ってきている")
    }

    /// **一覧と実体を分けて扱う。** 実体が落ちてくる前でも「その写真がある」ことは分かるので、
    /// ギャラリーは枠を先に出せる（全部落ちるまで開かない作りにしない）
    @Test("実体を落とす前でも、写真があることは先に分かる")
    func pullPhotosRecordsBeforeDownloading() async throws {
        let visit = makeVisit(turn: makeTurn())
        try context.save()

        let list = """
        [{"photoId":"\(UUID().apiString)","visitId":"\(visit.id.apiString)","stationId":2,
          "takenBy":"\(UUID().apiString)","takenByName":"ケンタ",
          "takenAt":"2026-08-11T09:30:00Z",
          "url":"\(stub.blobHost)/room/visit/photo.jpg?sig=abc",
          "urlExpiresAt":"2026-08-11T12:00:00Z"}]
        """
        let service = makeService(.bodies([(match: "/photos", body: list)]))

        #expect(await service.pullPhotos(fetchBodies: false) == 1)

        let saved = try #require(visit.photos.first)
        #expect(saved.localFileName.isEmpty, "実体を落とさない約束なのに落としている")
        #expect(stub.recordedPaths.count == 1, "一覧のほかに叩いている")
    }

    /// 差し替えの土台そのものの確認。
    ///
    /// 以前は状態を静的に1組しか持たず、テストが並んで走ると記録が混ざった。
    /// **ここが崩れると、経路の数え上げを使っている確認が軒並み当てにならなくなる**ので、
    /// 共有状態がうっかり戻ってこないように固定しておく
    @Test("差し替えはテストごとに分かれ、別の差し替えの記録と混ざらない")
    func stubSessionsAreIsolated() async throws {
        let service = makeService(.recordingPaths)
        try service.enqueueTurn(makeTurn())
        await service.push()

        // 別のテストが同時に走っている状況を作る
        let other = StubSession()
        other.open(.recordingPaths)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        _ = try? await URLSession(configuration: config)
            .data(from: other.baseURL.appendingPathComponent("elsewhere"))

        #expect(other.recordedPaths == ["/elsewhere"])
        #expect(!stub.recordedPaths.contains("/elsewhere"), "よその記録が混ざっている")
        #expect(stub.recordedPaths.contains { $0.contains("/turns/") }, "自分の記録が消えている")
    }

    @Test("送る順序は操作した順になる")
    func pushKeepsOrder() async throws {
        let service = makeService(.recordingPaths)
        let turn = makeTurn()
        try service.enqueueTurn(turn)
        try service.enqueueVisit(makeVisit(turn: turn))

        await service.push()

        let paths = stub.recordedPaths
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
        #expect(stub.recordedPaths.count == 1)
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

    // MARK: - 2台で遊ぶときの現在地
    //
    // **もう片方が進んでも、こちらは出発した駅から動かなかった。**
    // 取り込みが「進行中のターン」と「訪問」だけで、
    // 終わったターンを一切取り込んでいなかったのが原因（実際に2台で遊んで判明）。
    // 現在地は終わったターンから計算するので、こちらには何も伝わらなかった

    @Test("相手が終えたターンを取り込むと、現在地が進む")
    func completedTurnMovesCurrentOrder() async throws {
        let turnId = UUID()
        let service = makeService(.json("""
        {"currentStationId":4,"isCleared":false,"activeTurn":null,
         "visits":[],"completedTurnCount":1,
         "completedTurns":[{"turnId":"\(turnId.uuidString)","turnNo":1,"diceValue":3,
           "fromStationId":1,"landingStationId":4,"rolledAt":"2026-08-09T00:00:00Z",
           "arrivedAt":"2026-08-09T00:20:00Z","selectedMissionId":null,"missionDone":true,
           "appliedEffectType":null,"endStationId":4,"completedAt":"2026-08-09T00:30:00Z"}]}
        """))
        #expect(currentOrder == 1, "はじめは出発した駅")

        _ = await service.pull()

        #expect(currentOrder == 4, "相手が進んだのに、出発した駅のまま")
    }

    @Test("同じターンを二度取り込んでも増えない")
    func completedTurnIsIdempotent() async throws {
        let turnId = UUID()
        let body = """
        {"currentStationId":4,"isCleared":false,"activeTurn":null,
         "visits":[],"completedTurnCount":1,
         "completedTurns":[{"turnId":"\(turnId.uuidString)","turnNo":1,"diceValue":3,
           "fromStationId":1,"landingStationId":4,"rolledAt":"2026-08-09T00:00:00Z",
           "arrivedAt":null,"selectedMissionId":null,"missionDone":false,
           "appliedEffectType":null,"endStationId":4,"completedAt":"2026-08-09T00:30:00Z"}]}
        """
        let service = makeService(.json(body))
        _ = await service.pull()
        _ = await service.pull()

        #expect(try context.fetch(FetchDescriptor<Turn>()).filter { $0.id == turnId }.count == 1)
    }

    @Test("進行中だったターンが終わったら、こちらでも終わりになる")
    func activeTurnBecomesCompleted() async throws {
        let turnId = UUID()
        let service = makeService(.json("""
        {"currentStationId":1,"isCleared":false,
         "activeTurn":{"turnId":"\(turnId.uuidString)","turnNo":1,"diceValue":3,
           "fromStationId":1,"landingStationId":4,"rolledAt":"2026-08-09T00:00:00Z",
           "arrivedAt":null,"selectedMissionId":null,"missionDone":false,
           "appliedEffectType":null},
         "visits":[],"completedTurnCount":0}
        """))
        _ = await service.pull()
        #expect(currentOrder == 1, "進行中のターンでは現在地は動かない")

        // 相手がそのターンを終えた
        stub.update(.json("""
        {"currentStationId":4,"isCleared":false,"activeTurn":null,
         "visits":[],"completedTurnCount":1,
         "completedTurns":[{"turnId":"\(turnId.uuidString)","turnNo":1,"diceValue":3,
           "fromStationId":1,"landingStationId":4,"rolledAt":"2026-08-09T00:00:00Z",
           "arrivedAt":"2026-08-09T00:20:00Z","selectedMissionId":null,"missionDone":true,
           "appliedEffectType":null,"endStationId":4,"completedAt":"2026-08-09T00:30:00Z"}]}
        """))
        _ = await service.pull()

        // **同じターンを書き換える。** 足すだけだと、いつまでも進行中のまま
        let turns = try context.fetch(FetchDescriptor<Turn>()).filter { $0.id == turnId }
        #expect(turns.count == 1)
        #expect(turns.first?.completedAt != nil, "終わったことが伝わっていない")
        #expect(currentOrder == 4)
    }

    @Test("古いサーバー（終わったターンを返さない）でも落ちない")
    func toleratesOldServer() async throws {
        let service = makeService(.json("""
        {"currentStationId":1,"isCleared":false,"activeTurn":null,
         "visits":[],"completedTurnCount":0}
        """))

        #expect(await service.pull())
    }

    @Test("参加をやめると未送信も消える")
    func leaveClearsQueue() async throws {
        let service = makeService()
        try service.enqueueTurn(makeTurn())

        await service.leave()

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
        stub.update(.json(scheduleJSON(id: id, title: "予定を直した")))
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

        stub.update(.json("[]"))
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

/// テスト1件ぶんの差し替え。**テストごとに新しく作る。**
///
/// Swift Testing はテストごとにスイートを作り直すので、
/// スイートに `let` で持たせておけば、これ自体がテスト1件に閉じる。
/// 鍵はホスト名の先頭ラベルに載せて運ぶ（`<鍵>.api.invalid`）。
/// こうしておくと、どのリクエストがどのテストのものか URL だけで分かる
final class StubSession {

    private let key = "s" + UUID().uuidString
        .replacingOccurrences(of: "-", with: "").lowercased()

    /// このテスト専用の API の宛先
    var baseURL: URL { URL(string: "https://\(key).api.invalid")! }

    /// 写真の実体は API を通らず Blob へ直に行くので、**別のホスト**として扱う。
    /// 鍵は同じなので、同じテストの記録として並ぶ
    var blobHost: String { "https://\(key).blob.invalid" }

    /// 叩いた経路を、叩いた順に
    var recordedPaths: [String] { StubURLProtocol.paths(key: key) }

    /// 差し替えを用意する（記録は空から）
    func open(_ behavior: StubURLProtocol.Behavior) {
        StubURLProtocol.open(behavior, key: key)
    }

    /// 応答だけ差し替える。**記録は消さない**。
    /// 「1回目と2回目でサーバーの返事が変わる」場面に使う
    func update(_ behavior: StubURLProtocol.Behavior) {
        StubURLProtocol.update(behavior, key: key)
    }

    deinit { StubURLProtocol.close(key: key) }
}

/// 通信の差し替え。実際のHTTPは出さない。
///
/// **差し替えの状態はテストごとに分けて持つ。**
/// 以前は静的に1組しか持たず、`behavior` を入れ直すと記録も消えていたため、
/// テストが並んで走ると「どの経路を叩いたか」が混ざり、
/// 完全一致の確認が偶発的に落ちる余地があった。
/// いまは `StubSession` の鍵ごとに分けて持つので、何本同時に走っても混ざらない
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
        /// URLの一部ごとに本文を返す。どれにも当たらなければ 200 の `{}`。
        /// 写真のように**行き先ごとに違う応答**が要る手順で使う
        case bodies([(match: String, body: String)])
        /// 応答を遅らせて返す。**送信中の状態を掴んだまま**にしたいときに使う
        /// （割り込みの試験で、順序を運任せにしないため）
        case slow(String, seconds: TimeInterval)
        /// 遅れて圏外になる。`slow` の失敗版
        case slowOffline(seconds: TimeInterval)
    }

    /// 差し替え1件ぶん。応答と、叩かれた経路の記録
    private struct State {
        var behavior: Behavior
        var paths: [String] = []
    }

    nonisolated(unsafe) private static var states: [String: State] = [:]
    private static let lock = NSLock()

    static func open(_ behavior: Behavior, key: String) {
        lock.withLock { states[key] = State(behavior: behavior) }
    }

    static func update(_ behavior: Behavior, key: String) {
        lock.withLock { states[key]?.behavior = behavior }
    }

    static func paths(key: String) -> [String] {
        lock.withLock { states[key]?.paths ?? [] }
    }

    static func close(key: String) {
        lock.withLock { states.removeValue(forKey: key) }
    }

    /// 鍵はホスト名の先頭ラベル（`<鍵>.api.invalid` / `<鍵>.blob.invalid`）
    private static func key(for request: URLRequest) -> String? {
        request.url?.host?.split(separator: ".").first.map(String.init)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        let fullURL = request.url?.absoluteString ?? ""
        var delay: TimeInterval = 0
        let outcome: (status: Int, body: String)? = Self.lock.withLock {
            // 用意されていない宛先は圏外として扱う（取り違えて他のテストの記録に混ぜない）
            guard let key = Self.key(for: request), var state = Self.states[key] else { return nil }
            state.paths.append(path)
            defer { Self.states[key] = state }

            switch state.behavior {
            case .bodies(let table):
                return (200, table.first { fullURL.contains($0.match) }?.body ?? "{}")
            case .offline:
                return nil
            case .json(let body):
                return (200, body)
            case .status(let status, let body):
                return (status, body)
            case .recordingPaths:
                return (200, "{}")
            case .failFirstThenSucceed(let status):
                return state.paths.count == 1 ? (status, "") : (200, "{}")
            case .slow(let body, let seconds):
                delay = seconds
                return (200, body)
            case .slowOffline(let seconds):
                delay = seconds
                return nil
            }
        }

        // 待つのは錠を放してから。掴んだままだと、割り込む側まで止めてしまう
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }

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
