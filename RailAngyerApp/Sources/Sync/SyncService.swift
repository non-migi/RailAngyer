import Foundation
import SwiftData
import RailAngyerCore

/// 送信と取り込み（11_API設計.md §4 / 実装順 8）。
///
/// <para>方針は「**ローカルが正、サーバーは共有の場**」。
/// 送れていなくてもプレイは最後まで続けられる。</para>
///
/// > ⚠️ **`@MainActor` を外さない。**
/// > ここが持つ `ModelContext` は画面と同じもので、SwiftData のコンテキストは
/// > スレッドをまたいで触れない。付けていないと `await` のたびに別スレッドへ移り、
/// > 取り込みの `save()` が画面の読み出しと衝突して `EXC_BAD_ACCESS` で落ちる
/// > （ビルド6で実際に起きた。`14_引き継ぎ.md` §5）。
/// > 通信そのものは `URLSession` が別スレッドで行うので、待っている間に画面は止まらない。
@Observable
@MainActor
final class SyncService {

    /// 画面に出す未送信件数（SC-20）
    private(set) var pendingCount: Int = 0
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var isSyncing = false

    private let context: ModelContext
    private let client: ApiClient
    private let credentials: CredentialStoring
    private let queue: SyncQueue

    init(context: ModelContext, client: ApiClient, credentials: CredentialStoring) {
        self.context = context
        self.client = client
        self.credentials = credentials
        self.queue = SyncQueue(context: context)
        self.pendingCount = (try? queue.count()) ?? 0
    }

    var isJoined: Bool { credentials.load() != nil }

    /// 参加していればサーバーを起こしておく。F1 とサーバーレスDBは寝ている（§1）
    func wakeUpIfJoined() async {
        guard isJoined else { return }
        await client.wakeUp()
    }

    // MARK: - マスタ

    /// 駅マスタのサーバーIDを取り込む。
    ///
    /// 同梱マスタとは**駅の並び順（`orderNo`）で突き合わせる**。
    /// 送信の中身は駅のIDなので、**これを済ませるまで何も送れない**。
    ///
    /// 座標は上書きしない。現地で実測して直した値を、サーバー側の概値で潰さないため
    /// （04_ロードマップ.md「駅座標の実測と補正」）。
    @discardableResult
    func pullMaster() async -> Bool {
        do {
            let courses = try await client.courses()
            try applyMaster(courses)
            return true
        } catch let error as ApiError {
            lastError = error.message
            return false
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    private func applyMaster(_ courses: [CourseResponse]) throws {
        let local = try context.fetch(FetchDescriptor<Course>())

        for incoming in courses {
            guard let course = local.first(where: { $0.name == incoming.name }) else { continue }
            course.serverId = incoming.courseId

            let byOrder = Dictionary(uniqueKeysWithValues: incoming.stations.map { ($0.orderNo, $0) })
            for station in course.stations {
                station.serverId = byOrder[station.orderNo]?.stationId
            }
        }
        try context.save()
    }

    // MARK: - 積む

    /// ターンの作成・更新を積む
    func enqueueTurn(_ turn: Turn) throws {
        guard let room = credentials.load()?.roomId else { return }
        guard let from = turn.fromStation?.serverId,
              let landing = turn.landingStation?.serverId else { return }

        // **めいめいで取り組む旅では、引いたお題を送らない。**
        // ターン1件にお題は1つしか持てないので、各自の引きを送ると上書きし合う。
        // 盤面（どこからどこへ動いたか）は共有したいので、そこだけを送る
        let individual = (try? localRoom())?.missionStyle == .individual

        let body = SaveTurnBody(
            fromStationId: from,
            diceValue: turn.diceValue,
            landingStationId: landing,
            rolledAt: turn.rolledAt,
            arrivedAt: turn.arrivedAt,
            selectedMissionId: individual ? nil : turn.selectedMission?.id,
            missionDone: individual ? nil : turn.missionDone,
            appliedEffectType: individual ? nil : turn.appliedEffectType?.rawValue,
            endStationId: turn.endStation?.serverId,
            completedAt: turn.completedAt)

        try enqueue(path: "/rooms/\(room.apiString)/turns/\(turn.id.apiString)", body: body)
    }

    /// 訪問の記録を積む
    func enqueueVisit(_ visit: Visit) throws {
        guard let room = credentials.load()?.roomId else { return }
        guard let station = visit.station?.serverId else { return }

        let body = SaveVisitBody(turnId: visit.turn?.id,
                                 stationId: station,
                                 arrivedAt: visit.arrivedAt,
                                 visitKind: visit.visitKind.rawValue)

        try enqueue(path: "/rooms/\(room.apiString)/visits/\(visit.id.apiString)", body: body)
    }

    /// ミッションの作成・更新を積む
    func enqueueMission(_ mission: Mission) throws {
        guard let room = credentials.load()?.roomId else { return }
        guard let station = mission.station?.serverId else { return }

        let body = SaveMissionBody(stationId: station,
                                   content: mission.content,
                                   effectType: mission.effectType.rawValue,
                                   effectValue: mission.effectValue,
                                   effectStationId: mission.effectStation?.serverId)

        try enqueue(path: "/rooms/\(room.apiString)/missions/\(mission.id.apiString)", body: body)
    }

    /// お題の削除を積む
    func enqueueMissionDelete(missionId: UUID) throws {
        guard let room = credentials.load()?.roomId else { return }
        try queue.enqueue(PendingChange(method: "DELETE",
                                        path: "/rooms/\(room.apiString)/missions/\(missionId.apiString)",
                                        payload: nil))
        pendingCount = try queue.count()
    }

    /// 写真の削除を積む。
    /// **実体は消したそばから端末から消える**ので、送信は後追いでよい
    func enqueuePhotoDelete(photoId: UUID) throws {
        guard let room = credentials.load()?.roomId else { return }
        try queue.enqueue(PendingChange(
            method: "DELETE",
            path: "/rooms/\(room.apiString)/photos/\(photoId.apiString)",
            payload: nil))
        pendingCount = try queue.count()
    }

    /// 記録リセットを積む（`DELETE /progress`）
    func enqueueReset() throws {
        guard let room = credentials.load()?.roomId else { return }
        try queue.enqueue(PendingChange(method: "DELETE",
                                        path: "/rooms/\(room.apiString)/progress",
                                        payload: nil))
        pendingCount = try queue.count()
    }

    private func enqueue<Body: Encodable>(path: String, body: Body) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ApiDate.text(date))
        }
        try queue.enqueue(PendingChange(path: path, payload: try encoder.encode(body)))
        pendingCount = try queue.count()
    }

    // MARK: - 送る

    /// キューを古い順に流す。
    ///
    /// <b>1件でも「後で送り直すべき失敗」が出たらそこで止める。</b>
    /// 飛ばして次を送ると、あとから古い状態が上書きされる（着地の後に「振った直後」が届く）。
    @discardableResult
    func push() async -> Int {
        guard isJoined else { return 0 }
        isSyncing = true
        defer { isSyncing = false }

        var sent = 0
        for change in (try? queue.pending()) ?? [] {
            do {
                try await client.perform(change)
                try queue.remove(change)
                sent += 1
                lastError = nil
            } catch let error as ApiError {
                try? queue.recordFailure(change, message: error.message)
                lastError = error.message

                if error.isRetryable { break }

                // 400 のような「何度送っても同じ」失敗は捨てる。
                // 残すとキューが永久に詰まり、以降の記録が一切送れなくなる
                try? queue.remove(change)

                // 同時にサイコロを振って負けた（409）。自分の一手は取り下げて、
                // **勝った人の進行をすぐ取り込み、画面をみんなと合わせる**（§6）
                if case .server(let status, _) = error, status == 409 {
                    await pull()
                }
            } catch {
                lastError = String(describing: error)
                break
            }
        }

        pendingCount = (try? queue.count()) ?? 0

        // **記録を送り終えてから写真を上げる。** 訪問がサーバーに無いうちは
        // 写真の登録が弾かれる（写真は訪問にぶら下がる）
        sent += await pushPhotos()

        if sent > 0 { lastSyncedAt = Date() }
        return sent
    }

    // MARK: - 写真（11_API設計.md §5 / G-6）

    /// このプロセスのあいだ、諦めた写真。
    ///
    /// **「何度やっても同じ」失敗を延々と繰り返さない。**
    /// 400 のような失敗は次の取り込みでも同じ結果になるので、
    /// 開くたびに同じ1枚で時間を使わせないために覚えておく。
    /// **起動し直せば消える**ので、原因が直れば次の起動で拾い直せる
    private var skippedPhotoIds: Set<UUID> = []

    /// 削除待ちの写真。
    ///
    /// **消した写真を取り込みで蘇らせない。** 消した直後はサーバーにまだ残っているので、
    /// 先に一覧を取りに行くと戻ってきてしまう（送信キューが流れるまでのあいだ）
    private func photoIdsPendingDeletion() -> Set<UUID> {
        let pending = (try? queue.pending()) ?? []
        return Set(pending.compactMap { change -> UUID? in
            guard change.method == "DELETE", change.path.contains("/photos/"),
                  let last = change.path.split(separator: "/").last else { return nil }
            return UUID(uuidString: String(last))
        })
    }

    /// まだ上げていない自分の写真を、Blobへ上げてメタを登録する。
    ///
    /// 手順は **①SASをもらう → ②端末がBlobへ直接PUT → ③メタを登録** の3段（G-6）。
    /// 実体は普通の送信キューに載せない。中身が大きく、
    /// 途中で失敗したときに「同じものをもう一度」で済ませたいため、ここで1枚ずつ面倒を見る。
    ///
    /// - Returns: 上げ終えた枚数
    @discardableResult
    func pushPhotos() async -> Int {
        guard let saved = credentials.load(), let room = try? localRoom() else { return 0 }

        var sent = 0
        for photo in pendingPhotos(in: room, meId: saved.memberId) {
            guard let visitId = photo.visit?.id,
                  let data = PhotoStore.data(of: photo.localFileName) else { continue }

            do {
                let ticket = try await client.photoUploadUrl(roomId: saved.roomId,
                                                             photoId: photo.id,
                                                             visitId: visitId)
                guard let url = URL(string: ticket.uploadUrl) else { continue }
                try await client.uploadBlob(data, to: url)
                try await client.savePhotoMeta(roomId: saved.roomId,
                                               photoId: photo.id,
                                               visitId: visitId,
                                               takenAt: photo.takenAt)
                photo.blobUrl = ticket.blobPath        // 上がった印
                photo.syncStateRaw = SyncState.synced.rawValue
                try context.save()
                sent += 1
                lastError = nil
            } catch let error as ApiError {
                lastError = error.message
                // 圏外や、写真置き場が未設定（503）なら、残りも同じ結果になる
                if error.isRetryable { break }
                // 何度上げても同じ失敗（400 など）。この起動のあいだは諦めて先へ進む
                skippedPhotoIds.insert(photo.id)
                continue
            } catch {
                lastError = String(describing: error)
                break
            }
        }
        return sent
    }

    /// ルームの写真を取り込む（**仲間が撮ったぶんも**）。
    ///
    /// **一覧（軽い）と実体（重い）を分けて扱う。**
    /// 先に一覧だけを写して「その写真がある」ことを記録し、実体は後から埋める。
    /// こうすると、まだ落ちてきていない写真も枠として並べられる。
    /// 全部落ちるまで画面を止めると、サーバーが寝ている間は
    /// 「ギャラリーが開かない」ように見えてしまう。
    ///
    /// **30秒ごとの取り込みには混ぜない**（`pull()` から呼ばない）。
    /// 写真は重く、歩いている最中に電池と通信量を使う理由が無い。
    /// ギャラリーを開いたとき・引っ張ったとき・復帰したときに呼ぶ。
    ///
    /// - Parameter fetchBodies: 実体まで落とすか。枠だけ先に欲しいときは false
    /// - Returns: 新しく分かった枚数（実体の有無は問わない）
    @discardableResult
    func pullPhotos(fetchBodies: Bool = true) async -> Int {
        guard let saved = credentials.load() else { return 0 }
        do {
            let remote = try await client.photos(roomId: saved.roomId)
            let added = try applyPhotos(remote)
            if fetchBodies { await fetchPhotoBodies(from: remote) }
            return added
        } catch let error as ApiError {
            lastError = error.message
            return 0
        } catch {
            lastError = String(describing: error)
            return 0
        }
    }

    /// まだ上げていない自分の写真。
    ///
    /// 撮った人が分からない古い記録は自分のものとして扱う。
    /// **誰の写真かはサーバーがトークンから決める**ので、送って困ることはない
    private func pendingPhotos(in room: MissionSet, meId: UUID) -> [Photo] {
        room.visits
            .flatMap(\.photos)
            .filter { $0.blobUrl == nil && ($0.member?.id ?? meId) == meId }
            .filter { !skippedPhotoIds.contains($0.id) }
            .sorted { $0.takenAt < $1.takenAt }
    }

    /// 一覧を端末の記録に写す。**実体はまだ落とさない。**
    /// 実体を持っていない写真は `localFileName` が空のまま置かれる
    private func applyPhotos(_ remote: [PhotoResponse]) throws -> Int {
        guard let room = try localRoom() else { return 0 }
        var known = Set(room.visits.flatMap(\.photos).map(\.id))
        // 消したばかりの写真はまだサーバーに残っている。取り込みで蘇らせない
        known.formUnion(photoIdsPendingDeletion())

        var added = 0
        for incoming in remote where !known.contains(incoming.photoId) {
            // 訪問がまだ端末に無ければ見送る。次の取り込みで訪問ごと揃う
            guard let visit = room.visits.first(where: { $0.id == incoming.visitId }) else {
                continue
            }
            let photo = Photo(localFileName: "")      // 実体はこれから
            photo.id = incoming.photoId
            photo.takenAt = incoming.takenAt
            photo.blobUrl = blobReference(incoming.url)
            photo.visit = visit
            photo.member = photographer(of: incoming, in: room)
            photo.syncStateRaw = SyncState.synced.rawValue
            context.insert(photo)
            added += 1
        }

        if added > 0 { try context.save() }
        return added
    }

    /// 一度に落とす上限。残りは次に開いたときに埋まる。
    /// **待たせ続けないため**の区切りで、枠は先に出ている
    private static let photoBodyBatch = 20

    /// 実体をまだ持っていない写真を落として、端末に保存する。
    ///
    /// **1枚ごとに保存する。** まとめて最後に書くと、途中で切れたときに全部やり直しになり、
    /// 画面にも1枚も出ないまま待たせることになる
    private func fetchPhotoBodies(from remote: [PhotoResponse]) async {
        guard let room = try? localRoom() else { return }
        let urls = Dictionary(remote.map { ($0.photoId, $0.url) }, uniquingKeysWith: { first, _ in first })

        let missing = room.visits.flatMap(\.photos)
            .filter { $0.localFileName.isEmpty && !skippedPhotoIds.contains($0.id) }
            .sorted { $0.takenAt > $1.takenAt }       // 新しいものから埋める
            .prefix(Self.photoBodyBatch)

        for photo in missing {
            guard let text = urls[photo.id], let url = URL(string: text) else { continue }
            do {
                let data = try await client.downloadBlob(from: url)
                photo.localFileName = try PhotoStore.save(data: data)
                try context.save()
            } catch let error as ApiError {
                lastError = error.message
                if error.isRetryable { break }        // 圏外。残りも落ちてこない
                // 何度取っても同じ失敗。この起動のあいだは枠のままにして先へ進む
                skippedPhotoIds.insert(photo.id)
                continue
            } catch {
                lastError = String(describing: error)
                break
            }
        }
    }

    /// 署名を落とした在り処。
    ///
    /// **署名付きURLをそのまま持たない**（期限が切れて意味を失う）。
    /// `blobUrl` は「サーバーに実体がある」印として使うだけなので、
    /// 上げたときはコンテナ内のパス、取り込んだときはこの形になる
    private func blobReference(_ signedUrl: String) -> String? {
        guard var components = URLComponents(string: signedUrl) else { return nil }
        components.query = nil
        return components.url?.absoluteString
    }

    /// 撮った人。まだ取り込んでいないメンバーなら、名前だけの行を作る
    private func photographer(of incoming: PhotoResponse, in room: MissionSet) -> Member? {
        if let existing = room.members.first(where: { $0.id == incoming.takenBy }) {
            return existing
        }
        let created = Member(displayName: incoming.takenByName)
        created.id = incoming.takenBy
        created.missionSet = room
        context.insert(created)
        return created
    }

    // MARK: - ルーム

    /// ルームの設定とメンバーを取り込む。
    ///
    /// **区間と最大出目はサーバーが正**（T-06。プレイ開始後は変更できない）。
    /// 端末ごとに違う区間で遊んでいると、同じ盤面を共有できない。
    @discardableResult
    func pullRoom() async -> Bool {
        guard let saved = credentials.load() else { return false }
        do {
            let remote = try await client.room(roomId: saved.roomId)
            try applyRoom(remote, meId: saved.memberId)
            return true
        } catch let error as ApiError {
            lastError = error.message
            return false
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    /// お題の見え方を変える。**端末には先に書く**（サーバーが寝ていても操作できる）。
    ///
    /// - Returns: サーバーへ届けられなければ理由。届かなくても端末の設定は変わっている
    @discardableResult
    func updateMissionVisibility(_ visibility: MissionVisibility) async -> String? {
        guard let saved = credentials.load() else { return nil }
        do {
            try await client.updateRoom(roomId: saved.roomId,
                                        UpdateRoomRequest(missionVisibility: visibility.rawValue))
            // 見え方が変わると、返ってくるお題の顔ぶれも変わる
            await pullMissions(includeOthers: visibility == .always)
            return nil
        } catch let error as ApiError {
            lastError = error.message
            return error.message
        } catch {
            lastError = String(describing: error)
            return "みんなに届けられませんでした。電波が戻ったら設定を開き直してください"
        }
    }

    private func applyRoom(_ remote: RoomResponse, meId: UUID) throws {
        guard let room = try localRoom() else { return }

        // ローカルのルームをサーバーのものと同じIDにしておく。
        // 別々のIDのままだと、どの記録がどのルームのものか後から追えなくなる
        room.id = remote.roomId
        room.name = remote.name
        room.inviteCode = remote.inviteCode
        room.diceMax = remote.diceMax
        // 古いサーバーは返さない。返らなければ端末の設定を保つ
        if let visibility = remote.missionVisibility {
            room.missionVisibilityRaw = visibility
        }
        room.syncStateRaw = SyncState.synced.rawValue

        // **コースもサーバーに合わせる。** 別路線のルームに入ったとき、
        // 駅の並びごと切り替えないと、区間の駅を引き当てられない
        let courses = try context.fetch(FetchDescriptor<Course>())
        if let course = courses.first(where: { $0.serverId == remote.courseId }),
           room.course !== course {
            room.course = course
        }

        let stations = room.course?.stations ?? []
        room.startStation = stations.first { $0.serverId == remote.startStationId } ?? room.startStation
        room.goalStation = stations.first { $0.serverId == remote.goalStationId } ?? room.goalStation

        for incoming in remote.members {
            let member = room.members.first { $0.id == incoming.memberId }
                ?? {
                    let created = Member(displayName: incoming.displayName)
                    created.id = incoming.memberId
                    created.missionSet = room
                    context.insert(created)
                    return created
                }()
            member.displayName = incoming.displayName
            member.joinedAt = incoming.joinedAt
            member.isMe = incoming.memberId == meId
        }

        // フェーズ1で作った「じぶん」は、参加後は本人のメンバーに置き換わる。
        //
        // **書いた人・撮った人は消さない。**
        // `Mission.member` も `Photo.member` も inverse の無い一方向の参照なので、
        // メンバーの行だけ消すと**消えた行を指したまま**になる。
        // そのあと属性（名前など）を読んだ瞬間に落ちる（`_InvalidFutureBackingData`）。
        // 退室した人の写真が一覧に出るだけで落ちていた
        let serverIds = Set(remote.members.map(\.memberId))
        var keep = Set(room.missions.compactMap { $0.member?.id })
        keep.formUnion(room.visits.flatMap(\.photos).compactMap { $0.member?.id })

        for stale in room.members where !serverIds.contains(stale.id) && !keep.contains(stale.id) {
            context.delete(stale)
        }

        try context.save()
    }

    // MARK: - ミッション

    /// お題を取り込む（機種変更や再インストールの後で書き直さずに済む）。
    ///
    /// **既定ではみんなのお題を取り込む。** 着地した駅で引く候補は端末の中で選ぶので、
    /// 自分のぶんしか持っていないと、仲間が書いたお題が一度も引かれない。
    /// 当日まで伏せる設定のときだけ `includeOthers: false` で自分のぶんに絞る
    @discardableResult
    func pullMissions(includeOthers: Bool = true) async -> Bool {
        guard let saved = credentials.load() else { return false }
        do {
            let remote = try await client.missions(roomId: saved.roomId,
                                                   includeOthers: includeOthers)
            try applyMissions(remote, meId: saved.memberId)
            return true
        } catch let error as ApiError {
            lastError = error.message
            return false
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    /// 駅ごとの準備状況。
    ///
    /// **既定では中身も受け取る**（お題はみんなに見える）。
    /// 伏せる設定のときは `includeContent: false` にして、件数だけを受け取る。
    /// 画面で隠すだけにせず**そもそも取りに行かない**ことで、中身が端末に残らない
    func missionSummary(includeContent: Bool = true) async -> [MissionSummaryResponse] {
        guard let saved = credentials.load() else { return [] }
        do {
            return try await client.missionSummary(roomId: saved.roomId,
                                                   includeContent: includeContent)
        } catch let error as ApiError {
            lastError = error.message
            return []
        } catch {
            lastError = String(describing: error)
            return []
        }
    }

    private func applyMissions(_ remote: [MissionResponse], meId: UUID) throws {
        guard let room = try localRoom() else { return }

        let stations = room.course?.stations ?? []

        for incoming in remote {
            guard let station = stations.first(where: { $0.serverId == incoming.stationId }) else {
                continue
            }
            let mission = room.missions.first { $0.id == incoming.missionId }
                ?? {
                    let created = Mission(content: incoming.content)
                    created.id = incoming.missionId
                    created.missionSet = room
                    context.insert(created)
                    return created
                }()

            mission.content = incoming.content
            // 現行ルールではお題は行動だけ。旧サーバーに残る効果は取り込まない。
            mission.effectType = .none
            mission.effectValue = nil
            mission.effectStation = nil
            mission.station = station
            // **書き手のIDで突き合わせる。** 名前は同名の人がいると取り違えるし、
            // 一律に自分のものとして取り込むと、全部が自分の作ったお題になってしまう
            mission.member = author(of: incoming, meId: meId, in: room) ?? mission.member
            mission.syncStateRaw = SyncState.synced.rawValue
        }

        // **お楽しみへ戻したら、端末に残る他人のお題を消す。**
        // 消さないと、設定を戻したのに中身が見えたままになる
        if room.missionVisibility == .surprise {
            let arrived = Set(remote.map(\.missionId))
            for stale in room.missions
            where stale.member?.id != meId && !arrived.contains(stale.id) {
                context.delete(stale)
            }
        }

        try context.save()
    }

    /// お題を書いた人。
    ///
    /// **他人のお題も降りてくる**ので、名前ではなくIDで引き当てる。
    /// まだ取り込んでいないメンバーなら名前だけの行を作る（誰が書いたか出せるように）。
    /// IDを返さない古いサーバー相手では、自分のぶんしか返らないので自分として扱う
    private func author(of incoming: MissionResponse, meId: UUID, in room: MissionSet) -> Member? {
        let id = incoming.memberId ?? meId
        if let existing = room.members.first(where: { $0.id == id }) { return existing }

        let created = Member(displayName: incoming.createdByName, isMe: id == meId)
        created.id = id
        created.missionSet = room
        context.insert(created)
        return created
    }

    // MARK: - 予定（フェーズ3）

    /// 予定を積む。**共有しない予定は送らない**（この端末の中だけに置く）
    func enqueueSchedule(_ schedule: Schedule) throws {
        guard schedule.isShared else { return }
        guard let room = credentials.load()?.roomId else { return }
        let body = SaveScheduleBody(title: schedule.title,
                                    startAt: schedule.startAt,
                                    meetPlace: schedule.meetPlace,
                                    courseId: schedule.courseServerId,
                                    courseName: schedule.courseName,
                                    startOrder: schedule.startOrder,
                                    goalOrder: schedule.goalOrder,
                                    diceMax: schedule.diceMax,
                                    isLap: schedule.isLap,
                                    loopDirection: schedule.loopDirectionRaw,
                                    usesDice: schedule.usesDice,
                                    usesMissions: schedule.usesMissions,
                                    missionVisibility: schedule.missionVisibilityRaw,
                                    missionStyle: schedule.missionStyleRaw,
                                    includesOwnMissions: schedule.includesOwnMissions,
                                    arrivalRadius: schedule.arrivalRadius,
                                    isShared: schedule.isShared,
                                    timeZoneId: schedule.timeZoneIdentifier)
        try enqueue(path: "/rooms/\(room.apiString)/schedules/\(schedule.id.apiString)", body: body)
    }

    func enqueueScheduleDelete(scheduleId: UUID) throws {
        guard let room = credentials.load()?.roomId else { return }
        try queue.enqueue(PendingChange(
            method: "DELETE",
            path: "/rooms/\(room.apiString)/schedules/\(scheduleId.apiString)",
            payload: nil))
        pendingCount = try queue.count()
    }

    /// 出欠を積む。**誰の出欠かはサーバーがトークンから決める**ので、送るのは値だけ
    func enqueueAttendance(scheduleId: UUID, status: AttendanceStatus) throws {
        guard let room = credentials.load()?.roomId else { return }
        try enqueue(path: "/rooms/\(room.apiString)/schedules/\(scheduleId.apiString)/attendance",
                    body: SaveAttendanceBody(status: status.rawValue))
    }

    /// 予定と出欠を取り込む。
    ///
    /// 予定は**サーバーが正**にする。進行の記録と違い、誰かが消したら消えてほしい
    /// （消えた予定が端末に残り続けると、集合場所を取り違える）。
    /// ただし**まだ送っていない予定は消さない**。
    @discardableResult
    func pullSchedules() async -> Bool {
        guard let saved = credentials.load() else { return false }
        do {
            let remote = try await client.schedules(roomId: saved.roomId)
            try applySchedules(remote)
            return true
        } catch let error as ApiError {
            lastError = error.message
            return false
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    private func applySchedules(_ remote: [ScheduleResponse]) throws {
        guard let room = try localRoom() else { return }
        let existing = try context.fetch(FetchDescriptor<Schedule>())

        for incoming in remote {
            let schedule = existing.first { $0.id == incoming.scheduleId }
                ?? {
                    let created = Schedule(title: incoming.title, startAt: incoming.startAt)
                    created.id = incoming.scheduleId
                    created.missionSet = room
                    context.insert(created)
                    return created
                }()

            schedule.title = incoming.title
            schedule.startAt = incoming.startAt
            schedule.meetPlace = incoming.meetPlace
            if let courseId = incoming.courseId { schedule.courseServerId = courseId }
            if let courseName = incoming.courseName { schedule.courseName = courseName }
            if let startOrder = incoming.startOrder { schedule.startOrder = startOrder }
            if let goalOrder = incoming.goalOrder { schedule.goalOrder = goalOrder }
            if let diceMax = incoming.diceMax { schedule.diceMax = diceMax }
            if let isLap = incoming.isLap { schedule.isLap = isLap }
            if let direction = incoming.loopDirection {
                schedule.loopDirectionRaw = direction >= 0 ? 1 : -1
            }
            if let usesDice = incoming.usesDice { schedule.usesDice = usesDice }
            if let usesMissions = incoming.usesMissions { schedule.usesMissions = usesMissions }
            if let visibility = incoming.missionVisibility {
                schedule.missionVisibilityRaw = visibility
            }
            // お題の取り組み方。**古いサーバーは返さない**ので、来たときだけ書く
            // （返らない＝既定のまま＝みんなで1つ）
            if let missionStyle = incoming.missionStyle {
                schedule.missionStyleRaw = missionStyle
            }
            if let includesOwnMissions = incoming.includesOwnMissions {
                schedule.includesOwnMissions = includesOwnMissions
            }
            if let radius = incoming.arrivalRadius { schedule.arrivalRadius = radius }
            if let isShared = incoming.isShared { schedule.isShared = isShared }
            if let timeZoneId = incoming.timeZoneId { schedule.timeZoneIdentifier = timeZoneId }
            schedule.createdById = incoming.createdBy
            schedule.syncStateRaw = SyncState.synced.rawValue

            for person in incoming.attendees {
                if let attendance = schedule.attendees.first(where: { $0.memberId == person.memberId }) {
                    attendance.displayName = person.displayName
                    attendance.statusRaw = person.status
                } else {
                    let created = Attendance(memberId: person.memberId,
                                             displayName: person.displayName,
                                             status: AttendanceStatus(rawValue: person.status) ?? .undecided)
                    created.schedule = schedule
                    context.insert(created)
                }
            }
        }

        // サーバーから消えた予定は端末からも消す。ただし未送信のものは残す
        let remoteIds = Set(remote.map(\.scheduleId))
        for stale in existing
        where !remoteIds.contains(stale.id) && stale.syncStateRaw == SyncState.synced.rawValue {
            context.delete(stale)
        }

        try context.save()
    }

    // MARK: - 取り込む

    /// サーバーの進行を取り込む。**送るものを送ってから取りに行く**（自分の記録が消えないように）
    @discardableResult
    func pull() async -> Bool {
        guard let room = credentials.load()?.roomId else { return false }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let state = try await client.state(roomId: room)
            try apply(state)
            // **写真はここでは取らない。** 30秒ごとに実体まで落とすと、
            // 歩いている最中に電池と通信量を使う。見たいとき（ギャラリー）に取りに行く
            lastSyncedAt = Date()
            lastError = nil
            return true
        } catch let error as ApiError {
            lastError = error.message
            return false
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    /// 取り込みは**足すだけ**。ローカルにしかない記録は消さない
    /// （未送信のものが消えてしまうため）。
    private func apply(_ state: StateResponse) throws {
        guard let room = try localRoom() else { return }

        let stations = room.course?.stations ?? []
        func station(_ serverId: Int) -> Station? { stations.first { $0.serverId == serverId } }

        /// ターンを1件取り込む。**すでにあれば書き換える。**
        ///
        /// 以前は「無ければ足す」だけで、終わったターンは取り込んですらいなかった。
        /// 現在地は終わったターンから計算するので、**もう片方の端末が
        /// 出発した駅から動かない**という形で表に出た（2台で遊んで判明）。
        func upsert(id: UUID, turnNo: Int, dice: Int, from: Int, landing: Int,
                    rolledAt: Date, arrivedAt: Date?, missionDone: Bool,
                    appliedEffect: Int?, endStationId: Int?, completedAt: Date?) {
            let turn = room.turns.first { $0.id == id }
                ?? {
                    let created = Turn(turnNo: turnNo, diceValue: dice)
                    created.id = id
                    created.missionSet = room
                    context.insert(created)
                    return created
                }()
            turn.turnNo = turnNo
            turn.diceValue = dice
            turn.fromStation = station(from)
            turn.landingStation = station(landing)
            turn.rolledAt = rolledAt
            turn.arrivedAt = arrivedAt
            turn.missionDone = missionDone
            turn.appliedEffectTypeRaw = appliedEffect
            if let endStationId { turn.endStation = station(endStationId) }
            if let completedAt { turn.completedAt = completedAt }
            turn.syncStateRaw = SyncState.synced.rawValue
        }

        if let a = state.activeTurn {
            upsert(id: a.turnId, turnNo: a.turnNo, dice: a.diceValue,
                   from: a.fromStationId, landing: a.landingStationId,
                   rolledAt: a.rolledAt, arrivedAt: a.arrivedAt, missionDone: a.missionDone,
                   appliedEffect: a.appliedEffectType, endStationId: nil, completedAt: nil)
        }

        // **終わったターンを取り込む。** ここが現在地の元になる
        for c in state.completedTurns ?? [] {
            upsert(id: c.turnId, turnNo: c.turnNo, dice: c.diceValue,
                   from: c.fromStationId, landing: c.landingStationId,
                   rolledAt: c.rolledAt, arrivedAt: c.arrivedAt, missionDone: c.missionDone,
                   appliedEffect: c.appliedEffectType,
                   endStationId: c.endStationId, completedAt: c.completedAt ?? c.rolledAt)
        }

        for incoming in state.visits where !room.visits.contains(where: { $0.id == incoming.visitId }) {
            guard let station = station(incoming.stationId) else { continue }
            let visit = Visit(kind: VisitKind(rawValue: incoming.visitKind) ?? .passing)
            visit.id = incoming.visitId
            visit.missionSet = room
            visit.station = station
            visit.arrivedAt = incoming.arrivedAt
            visit.turn = incoming.turnId.flatMap { id in room.turns.first { $0.id == id } }
            visit.syncStateRaw = SyncState.synced.rawValue
            context.insert(visit)
        }

        try context.save()
    }

    private func localRoom() throws -> MissionSet? {
        try context.fetch(FetchDescriptor<MissionSet>()).first
    }

    // MARK: - 参加

    /// 招待コードで参加し、資格情報を保存する
    func join(inviteCode: String, displayName: String) async throws {
        let joined = try await client.joinRoom(inviteCode: inviteCode, displayName: displayName)
        try credentials.save(joined.credentials)
        await pullMaster()          // サーバーIDが無いと以降の送信が積めない
        await pullRoom()            // 区間と最大出目を相手に合わせる
        await pull()
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> JoinedRoomResponse {
        let created = try await client.createRoom(request)
        try credentials.save(created.credentials)
        await pullMaster()
        await pullRoom()
        return created
    }

    /// 参加をやめる。**未送信の記録も捨てる**（別のルームへ送ってしまわないように）
    func leave() throws {
        try credentials.clear()
        try queue.removeAll()
        pendingCount = 0
    }
}

// MARK: - 送信する形（サーバーの Request レコードに合わせる）

private struct SaveTurnBody: Encodable {
    let fromStationId: Int
    let diceValue: Int
    let landingStationId: Int
    let rolledAt: Date
    let arrivedAt: Date?
    let selectedMissionId: UUID?
    let missionDone: Bool?
    let appliedEffectType: Int?
    let endStationId: Int?
    let completedAt: Date?
}

private struct SaveVisitBody: Encodable {
    let turnId: UUID?
    let stationId: Int
    let arrivedAt: Date
    let visitKind: Int
}

private struct SaveScheduleBody: Encodable {
    let title: String
    let startAt: Date
    let meetPlace: String?
    let courseId: Int?
    let courseName: String
    let startOrder: Int
    let goalOrder: Int
    let diceMax: Int
    let isLap: Bool
    let loopDirection: Int
    let usesDice: Bool
    let usesMissions: Bool
    let missionVisibility: Int
    let missionStyle: Int
    let includesOwnMissions: Bool
    let arrivalRadius: Double?
    let isShared: Bool
    let timeZoneId: String?
}

private struct SaveAttendanceBody: Encodable {
    let status: Int
}

private struct SaveMissionBody: Encodable {
    let stationId: Int
    let content: String
    let effectType: Int
    let effectValue: Int?
    let effectStationId: Int?
}
