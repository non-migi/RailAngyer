import Foundation
import SwiftData
import RailAngyerCore

/// 送信と取り込み（11_API設計.md §4 / 実装順 8）。
///
/// <para>方針は「**ローカルが正、サーバーは共有の場**」。
/// 送れていなくてもプレイは最後まで続けられる。</para>
@Observable
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

        let body = SaveTurnBody(
            fromStationId: from,
            diceValue: turn.diceValue,
            landingStationId: landing,
            rolledAt: turn.rolledAt,
            arrivedAt: turn.arrivedAt,
            selectedMissionId: turn.selectedMission?.id,
            missionDone: turn.missionDone,
            appliedEffectType: turn.appliedEffectType?.rawValue,
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
            } catch {
                lastError = String(describing: error)
                break
            }
        }

        pendingCount = (try? queue.count()) ?? 0
        if sent > 0 { lastSyncedAt = Date() }
        return sent
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

    private func applyRoom(_ remote: RoomResponse, meId: UUID) throws {
        guard let room = try localRoom() else { return }

        // ローカルのルームをサーバーのものと同じIDにしておく。
        // 別々のIDのままだと、どの記録がどのルームのものか後から追えなくなる
        room.id = remote.roomId
        room.name = remote.name
        room.inviteCode = remote.inviteCode
        room.diceMax = remote.diceMax
        room.syncStateRaw = SyncState.synced.rawValue

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
        // ただしお題を書いた人は消さない（書いた人が辿れなくなる）
        let serverIds = Set(remote.members.map(\.memberId))
        let authors = Set(room.missions.compactMap { $0.member?.id })
        for stale in room.members where !serverIds.contains(stale.id) && !authors.contains(stale.id) {
            context.delete(stale)
        }

        try context.save()
    }

    // MARK: - ミッション

    /// 自分のお題を取り込む（機種変更や再インストールの後で書き直さずに済む）。
    /// 他人のお題はサーバーが伏せるので、ここに降りてこない
    @discardableResult
    func pullMyMissions() async -> Bool {
        guard let saved = credentials.load() else { return false }
        do {
            let remote = try await client.missions(roomId: saved.roomId)
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

    /// 駅ごとの準備状況。**内容は取らない**ので、当日まで中身は伏せたまま数だけ見せられる
    func missionSummary() async -> [MissionSummaryResponse] {
        guard let saved = credentials.load() else { return [] }
        do {
            return try await client.missionSummary(roomId: saved.roomId)
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
        let me = room.members.first { $0.id == meId }

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
            mission.effectTypeRaw = incoming.effectType
            mission.effectValue = incoming.effectValue
            mission.effectStation = incoming.effectStationId
                .flatMap { id in stations.first { $0.serverId == id } }
            mission.station = station
            mission.member = me ?? mission.member
            mission.syncStateRaw = SyncState.synced.rawValue
        }

        try context.save()
    }

    // MARK: - 予定（フェーズ3）

    /// 予定を積む
    func enqueueSchedule(_ schedule: Schedule) throws {
        guard let room = credentials.load()?.roomId else { return }
        let body = SaveScheduleBody(title: schedule.title,
                                    startAt: schedule.startAt,
                                    meetPlace: schedule.meetPlace)
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

        if let active = state.activeTurn, !room.turns.contains(where: { $0.id == active.turnId }) {
            let turn = Turn(turnNo: active.turnNo, diceValue: active.diceValue)
            turn.id = active.turnId
            turn.missionSet = room
            turn.fromStation = station(active.fromStationId)
            turn.landingStation = station(active.landingStationId)
            turn.rolledAt = active.rolledAt
            turn.arrivedAt = active.arrivedAt
            turn.missionDone = active.missionDone
            turn.appliedEffectTypeRaw = active.appliedEffectType
            turn.syncStateRaw = SyncState.synced.rawValue
            context.insert(turn)
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
