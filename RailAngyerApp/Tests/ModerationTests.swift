import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// UGCの統制（App Store ガイドライン 1.2）と、退室時のサーバーデータ削除。
///
/// 確かめたいことは三つ。**見たくない人の投稿が本当に消えること**（抽選からも）、
/// **退室で自分のデータを消しに行くこと**（圏外でも退室自体は続くこと）、
/// **メンバーを外せるのは作成者だけであること**。
/// 通信は `StubURLProtocol` で差し替える（`SyncServiceTests` と同じ作法）。
@MainActor
struct ModerationTests {

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

        course.serverId = 1
        for station in course.stations { station.serverId = station.orderNo }
        try context.save()

        credentials = InMemoryCredentialStore(
            RoomCredentials(roomId: UUID(), memberId: UUID(), token: "test-token"))
    }

    private func makeService(_ behavior: StubURLProtocol.Behavior = .offline,
                             pendingLeaves: PendingLeaveStoring? = nil) -> SyncService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        stub.open(behavior)

        let client = ApiClient(baseURL: stub.baseURL,
                               credentials: credentials,
                               session: URLSession(configuration: config))
        return SyncService(context: context, client: client, credentials: credentials,
                           pendingLeaves: pendingLeaves)
    }

    /// ブロックの検証に使うストア。**保存した設定はテストの後に消す**
    /// （`UserDefaults` に残ると、走らせるたびにゴミが積もる）
    private func makeStore() -> GameSessionStore {
        let store = GameSessionStore(context: context)
        store.prepare()
        return store
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

    private func makeMember(_ name: String) -> Member {
        let member = Member(displayName: name)
        member.missionSet = room
        context.insert(member)
        return member
    }

    // MARK: - ローカルブロック（非表示）

    @Test("非表示にした人の写真はギャラリーに出ず、解除すれば戻る")
    func blockHidesPhotos() throws {
        let store = makeStore()
        defer { MemberBlockList.save([], roomId: room.id) }
        let kenta = makeMember("ケンタ")

        let photo = Photo(localFileName: "kenta.jpg")
        photo.visit = makeVisit(turn: makeTurn())
        photo.member = kenta
        context.insert(photo)
        try context.save()

        #expect(store.galleryPhotos.count == 1)

        store.block(memberId: kenta.id)
        #expect(store.galleryPhotos.isEmpty, "非表示にしたのに写真が出ている")

        store.unblock(memberId: kenta.id)
        #expect(store.galleryPhotos.count == 1, "解除したのに戻らない")
    }

    @Test("非表示にした人のお題は、一覧からも抽選の候補からも外れる")
    func blockHidesMissions() throws {
        let store = makeStore()
        defer { MemberBlockList.save([], roomId: room.id) }
        let kenta = makeMember("ケンタ")

        let mission = Mission(content: "駅名標を撮る")
        mission.missionSet = room
        mission.station = station(4)
        mission.member = kenta
        context.insert(mission)
        try context.save()

        #expect(store.missions(at: 4).count == 1)
        #expect(store.missionCandidates(at: 4).count == 1)

        store.block(memberId: kenta.id)

        #expect(store.missions(at: 4).isEmpty, "非表示にしたのに一覧に出ている")
        #expect(store.missionCandidates(at: 4).isEmpty, "非表示にしたのに抽選に混ざる")
        #expect(!store.missionOrders.contains(4), "非表示にしたのに地図のピンが残る")
    }

    @Test("自分は非表示にできない")
    func cannotBlockMyself() throws {
        let store = makeStore()
        defer { MemberBlockList.save([], roomId: room.id) }
        let meId = try #require(store.me?.id)

        store.block(memberId: meId)

        #expect(!store.isBlocked(memberId: meId))
    }

    @Test("非表示の設定は端末に保存され、次の起動でも効く")
    func blockSurvivesRelaunch() throws {
        let store = makeStore()
        defer { MemberBlockList.save([], roomId: room.id) }
        let kenta = makeMember("ケンタ")
        try context.save()

        store.block(memberId: kenta.id)

        // 起動し直したつもりで、同じ記録から別のストアを作る
        let relaunched = makeStore()
        #expect(relaunched.isBlocked(memberId: kenta.id), "保存されていない")
    }

    // MARK: - 退室時のサーバーデータ削除

    @Test("退室のとき、資格情報を消す前に自分のデータをサーバーから消しに行く")
    func leaveDeletesMyServerData() async throws {
        let roomId = try #require(credentials.load()?.roomId)
        let service = makeService(.json("{}"))

        let warning = await service.leave()

        #expect(warning == nil)
        #expect(stub.recordedPaths == ["/rooms/\(roomId.apiString)/members/me"])
        #expect(!service.isJoined)
    }

    @Test("圏外でも退室はでき、サーバーに残っている案内が返る")
    func leaveContinuesOffline() async throws {
        let service = makeService(.offline)
        try service.enqueueTurn(makeTurn())

        let warning = await service.leave()

        // 消せなかったことは黙らない。ただし退室そのものは止めない
        #expect(warning != nil, "サーバーに残っていることを知らせていない")
        #expect(!service.isJoined)
        #expect(service.pendingCount == 0)
    }

    /// 退室の送信中に、やり残しの送り直しが割り込んでも二重に送らないこと。
    ///
    /// 送り口は `sendPendingLeave()` 1つに束ねてあり、入口（`retryPendingLeaveIfNeeded`）と
    /// 内側の両方で番人が要る。**片方だけだと素通りする**
    @Test("退室の最中に送り直しが割り込んでも、削除は1回だけ")
    func interleavedRetryDoesNotSendTwice() async throws {
        let pendingLeaves = InMemoryPendingLeaveStore()
        // **応答を遅らせて、退室を「送信中」で掴んだままにする。**
        // 遅らせないと割り込む順序が運任せになり、素通りでも通ってしまう
        let service = makeService(.slow("{}", seconds: 0.5), pendingLeaves: pendingLeaves)

        async let leaving: String? = service.leave()
        await Task.yield()                          // 退室を送信中まで進める
        await service.retryPendingLeaveIfNeeded()   // ここで確実に割り込む
        let warning = await leaving

        #expect(warning == nil)
        #expect(stub.recordedPaths.count == 1, "同じ削除を二重に送っている")
        #expect(pendingLeaves.load() == nil, "片付いたのに控えが残っている")
    }

    /// 割り込みで `attempts` が余計に進まないこと。
    /// 空回りで打ち切りに達すると、**消せているのにメールで依頼しろと出る**
    @Test("圏外の退室に送り直しが割り込んでも、数え上げは1回ぶん")
    func interleavedRetryCountsAttemptOnce() async throws {
        let pendingLeaves = InMemoryPendingLeaveStore()
        let service = makeService(.slowOffline(seconds: 0.5), pendingLeaves: pendingLeaves)

        async let leaving: String? = service.leave()
        await Task.yield()
        await service.retryPendingLeaveIfNeeded()
        _ = await leaving

        let saved = try #require(pendingLeaves.load(), "圏外なら控えが残るはず")
        #expect(saved.attempts == 1, "割り込んだぶんまで失敗として数えている")
        #expect(stub.recordedPaths.count == 1, "同じ削除を二重に送っている")
    }

    // MARK: - 資格が切れたとき（外された端末）

    @Test("外された端末は、資格情報ごと畳んで送るのをやめる")
    func revokedMembershipForfeitsCredentials() async throws {
        defer { SyncNotice.shared.isPresented = false }
        let service = makeService(
            .status(401, #"{"error":"unauthorized","message":"参加していません"}"#))
        try service.enqueueTurn(makeTurn())

        await service.push()

        #expect(!service.isJoined, "外されたのに資格情報が残っている")
        #expect(service.pendingCount == 0, "二度と送れない記録が積まれたまま")
        // 黙って戻すと、外されたことに気づけないまま遊び続けることになる
        #expect(SyncNotice.shared.kind == .removedFromRoom, "外れたことが伝わらない")
    }

    /// **ここが崩れると、間に入る機器が返した 401 で全員が勝手に退室扱いになる。**
    /// 資格を捨てるのは、うちのサーバーが `unauthorized` と名乗ったときだけ
    @Test("本文の無い401では、資格情報を捨てない")
    func bodylessUnauthorizedKeepsCredentials() async throws {
        defer { SyncNotice.shared.isPresented = false }
        let service = makeService(.status(401, ""))
        try service.enqueueTurn(makeTurn())

        await service.push()

        #expect(service.isJoined, "本文の無い401で資格情報を捨てている")
        #expect(service.pendingCount == 1, "再参加すれば送れる記録を捨てている")
        #expect(SyncNotice.shared.kind == nil, "外れてもいないのに知らせが出ている")
    }

    @Test("外されたあとの送信キューは、詰まったままにならない")
    func forfeitDoesNotJamQueue() async throws {
        defer { SyncNotice.shared.isPresented = false }
        let service = makeService(
            .status(401, #"{"error":"unauthorized","message":"参加していません"}"#))
        let turn = makeTurn()
        try service.enqueueTurn(turn)
        try service.enqueueVisit(makeVisit(turn: turn))

        #expect(await service.push() == 0)
        #expect(service.pendingCount == 0, "送れない記録が残ると、以降が永久に詰まる")

        // 資格が無くなった後も叩きに行くと、起動のたびに401で空回りする
        let before = stub.recordedPaths.count
        #expect(await service.push() == 0)
        #expect(stub.recordedPaths.count == before, "資格が無いのに送りに行っている")
    }

    // MARK: - メンバーのキック（ルーム作成者のみ）

    @Test("作成者でなければメンバーを外せない（403）")
    func removeMemberRequiresCreator() async throws {
        let service = makeService(
            .status(403, #"{"error":"forbidden","message":"creator only"}"#))

        let message = await service.removeMember(UUID())

        #expect(message == appLocalized("ルームの作成者だけがメンバーを外せます"))
    }

    @Test("メンバーを外せたら、名簿をその場で取り込み直す")
    func removeMemberRefreshesRoster() async throws {
        let meId = try #require(credentials.load()?.memberId)
        let target = makeMember("ケンタ")
        try context.save()

        // 外したあとの名簿（自分だけ）。createdBy は自分＝作成者
        let roomJson = """
        {"roomId":"\(UUID().apiString)","name":"ツアー","courseId":1,
         "startStationId":1,"goalStationId":16,"diceMax":6,"inviteCode":"ABC123",
         "createdBy":"\(meId.apiString)",
         "members":[{"memberId":"\(meId.apiString)","displayName":"のん",
                     "joinedAt":"2026-07-30T05:00:00Z"}]}
        """
        let service = makeService(.bodies([
            (match: "/members/\(target.id.apiString)", body: "{}"),
            (match: "/rooms/", body: roomJson),
        ]))

        let message = await service.removeMember(target.id)

        #expect(message == nil)
        let paths = stub.recordedPaths
        #expect(paths.count == 2)
        #expect(paths.first?.contains("/members/\(target.id.apiString)") == true)
        #expect(!room.members.contains { $0.id == target.id }, "外した人が名簿に残っている")
        #expect(service.isRoomCreator, "作成者の判定が取り込まれていない")
    }

    @Test("createdBy を返さない古いサーバーでも取り込め、作成者扱いにはならない")
    func toleratesServerWithoutCreatedBy() async throws {
        let meId = try #require(credentials.load()?.memberId)
        let service = makeService(.json("""
        {"roomId":"\(UUID().apiString)","name":"ツアー","courseId":1,
         "startStationId":1,"goalStationId":16,"diceMax":6,"inviteCode":"ABC123",
         "members":[{"memberId":"\(meId.apiString)","displayName":"のん",
                     "joinedAt":"2026-07-30T05:00:00Z"}]}
        """))

        #expect(await service.pullRoom())
        #expect(!service.isRoomCreator, "誰が作ったか分からないのに作成者扱いになっている")
    }

    @Test("作成者が抜けたら、引き継ぎを取り込んで自分が作成者になる")
    func adoptsCreatorHandover() async throws {
        let meId = try #require(credentials.load()?.memberId)
        let founder = makeMember("ケンタ")
        try context.save()

        // 同じルームを二度取り込むので、ルームIDは通しで同じものを使う
        let roomId = UUID()

        // 1回目。作ったのはケンタで、こちらはただの参加者
        let service = makeService(.json("""
        {"roomId":"\(roomId.apiString)","name":"ツアー","courseId":1,
         "startStationId":1,"goalStationId":16,"diceMax":6,"inviteCode":"ABC123",
         "createdBy":"\(founder.id.apiString)",
         "members":[{"memberId":"\(founder.id.apiString)","displayName":"ケンタ",
                     "joinedAt":"2026-07-30T05:00:00Z"},
                    {"memberId":"\(meId.apiString)","displayName":"のん",
                     "joinedAt":"2026-07-30T05:01:00Z"}]}
        """))

        #expect(await service.pullRoom())
        #expect(!service.isRoomCreator, "作った人が居るのに、こちらが作成者になっている")

        // 2回目。ケンタが退室し、サーバーが残った最古参（＝自分）へ引き継いだ
        stub.update(.json("""
        {"roomId":"\(roomId.apiString)","name":"ツアー","courseId":1,
         "startStationId":1,"goalStationId":16,"diceMax":6,"inviteCode":"ABC123",
         "createdBy":"\(meId.apiString)",
         "members":[{"memberId":"\(meId.apiString)","displayName":"のん",
                     "joinedAt":"2026-07-30T05:01:00Z"}]}
        """))

        #expect(await service.pullRoom())
        // ここが false のままだと、引き継がれた人の端末に除名の口が出ず、
        // ルームからモデレーションの手段が消える
        #expect(service.isRoomCreator, "引き継ぎを取り込めていない")
    }
}
