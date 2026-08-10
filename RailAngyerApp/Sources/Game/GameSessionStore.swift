import Foundation
import SwiftData
import UIKit
import CoreLocation
import RailAngyerCore

/// ゲームの進行を担う。SwiftData への読み書きと、局面の導出を引き受ける。
///
/// ルールの計算そのものは `GameEngine` が持つ（10_アプリ設計.md AD-03）。
/// ここは「いつ何を保存するか」だけを扱う。
///
/// > ⚠️ **`@MainActor` を外さない。** `ModelContext` は画面と同じものを持っており、
/// > SwiftData のコンテキストはスレッドをまたいで触れない（`SyncService` と同じ理由）。
@Observable
@MainActor
final class GameSessionStore {

    private let context: ModelContext

    /// 送信キュー。参加していないあいだ（フェーズ1のローカル遊び）は nil のままでよい。
    /// **プレイはこれの有無に依存しない**（11_API設計.md §4）
    var sync: SyncService?

    /// 対象のルーム（フェーズ1では1件だけ）
    private(set) var room: MissionSet?
    /// 直前の操作で起きたエラー
    var lastError: String?
    /// 起動時に外した「消えた行への参照」の数。ふだんは0
    private(set) var repairedReferenceCount = 0
    /// 着地駅の告知（SC-06）を出しているか
    var showingAnnouncement = false
    /// 通り道の駅に着いたところ。写真を撮る間を置くための一時状態。
    /// 保存はしない（落ちて失われても、次の駅へ向かう画面に戻るだけで害がない）
    private(set) var pendingPassingStation: Int?

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - 準備

    /// マスタとローカルルームを用意する。初回起動時に1回だけ効く。
    func prepare(sampleMissions: Bool = false) {
        do {
            let course = try MasterSeeder.seedIfNeeded(context)
            let room = try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)
            if sampleMissions { try MasterSeeder.seedSampleMissionsIfNeeded(context, room: room) }
            try MasterSeeder.removeBundledSampleMissions(context, room: room)
            self.room = room
            repairDanglingReferences()
            reloadSchedules()
            if TestHooks.resetsProgressOnLaunch { resetProgress(archive: false) }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 消えた行を掴んだままの参照を外す（起動時に1回）。
    ///
    /// **SwiftData は、消えた行の属性を読んだ瞬間に落ちる**（`_InvalidFutureBackingData`）。
    /// ビルド2までは、コースを変えると他コースのお題を消していた。
    /// そのときターンの `selectedMission` が消えたお題を指したまま残り、
    /// **次の起動でそのターンを開くと、お題のIDを読んだところで落ちていた**
    /// （TestFlight のクラッシュ報告 2026-08-01 で判明）。
    ///
    /// 直すときも属性は読めないので、**`persistentModelID` だけで突き合わせる**。
    private func repairDanglingReferences() {
        do {
            let missions = Set(try context.fetch(FetchDescriptor<Mission>())
                .map(\.persistentModelID))
            let turns = try context.fetch(FetchDescriptor<Turn>())
            let turnIDs = Set(turns.map(\.persistentModelID))
            var repaired = 0

            for turn in turns {
                if let id = turn.selectedMission?.persistentModelID, !missions.contains(id) {
                    turn.selectedMission = nil          // 引いたお題が消えている
                    repaired += 1
                }
            }

            // ターンが消えているのに残った訪問・写真も、読まれれば同じように落ちる。
            // 進行の記録としても意味を失っているので、行ごと消す
            for visit in try context.fetch(FetchDescriptor<Visit>()) {
                guard let id = visit.turn?.persistentModelID, !turnIDs.contains(id) else { continue }
                for photo in visit.photos { context.delete(photo) }
                context.delete(visit)
                repaired += 1
            }

            repairedReferenceCount = repaired
            if repaired > 0 { try context.save() }
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - 導出

    var engine: GameEngine? { room?.engine }

    /// 区間内の駅を進む向きに並べたもの。
    ///
    /// 一周では最後にスタート駅へ戻るが、**同じ駅を二度並べない**
    /// （画面の一覧で同じ駅が重なると、SwiftUI が行を取り違える）
    var stationsInOrder: [Station] {
        guard let room, let engine else { return [] }
        let all = room.course?.stations ?? []
        var seen = Set<Int>()
        return engine.orderedRange.compactMap { position in
            let orderNo = engine.stationOrder(at: position)
            guard seen.insert(orderNo).inserted else { return nil }
            return all.first { $0.orderNo == orderNo }
        }
    }

    /// 進行中のターン（あれば1件）
    var activeTurn: Turn? { room?.turns.first { $0.isActive } }

    /// 現在位置。最後に完了したターンの終了位置。無ければスタート駅（10_アプリ設計.md §5.2）
    var currentOrder: Int {
        guard let room else { return 1 }
        let completed = room.turns
            .filter { $0.completedAt != nil }
            .max { $0.turnNo < $1.turnNo }
        // 一周では駅の通し番号が元に戻ってしまうので、記録した位置を優先する
        return completed?.endPosition
            ?? completed?.endStation?.orderNo
            ?? room.startStation?.orderNo ?? 1
    }

    /// 旅が始まっているか。始点を記録した時点で始まったとみなす（R-17）
    var hasStartedJourney: Bool { !(room?.visits.isEmpty ?? true) }

    /// 一度でも訪れた駅の数（再訪は重複して数えない。DV-06）
    var visitedCount: Int {
        Set(room?.visits.compactMap { $0.station?.orderNo } ?? []).count
    }

    /// 訪問済みの駅番号
    var visitedOrders: Set<Int> {
        Set(room?.visits.compactMap { $0.station?.orderNo } ?? [])
    }

    /// 着地したことのある駅番号
    var landedOrders: Set<Int> {
        Set(room?.visits.filter { $0.visitKind == .landing }.compactMap { $0.station?.orderNo } ?? [])
    }

    /// いまの局面
    var phase: GamePhase {
        guard let engine else { return .notReady }

        guard let turn = activeTurn else {
            return engine.isCleared(currentOrder) ? .cleared : .waiting(current: currentOrder)
        }
        // 通り道の駅に着いた直後は、写真を撮る間を置く
        if let pending = pendingPassingStation { return .arrivedPassing(station: pending) }

        let landing = turn.landingPosition ?? turn.landingStation?.orderNo ?? currentOrder

        // 出目による移動中
        if turn.arrivedAt == nil {
            let from = turn.fromPosition ?? turn.fromStation?.orderNo ?? currentOrder
            let stops = engine.path(from: from, to: landing)
            let done = visitedOrders(in: turn, kinds: [.passing, .landing])
            let remaining = stops.filter { !done.contains($0) }
            return .walking(next: remaining.first ?? landing, remaining: remaining.count)
        }

        // 効果が決まっていなければ、抽選前かミッション中
        guard let applied = turn.appliedEffectType else {
            return turn.selectedMission == nil ? .landed(station: landing) : .mission(station: landing)
        }

        // 効果による移動中
        if applied.movesPiece, let destination = effectDestination(of: turn) {
            let stops = engine.path(from: landing, to: destination)
            let done = visitedOrders(in: turn, kinds: [.effectPassing, .effectArrival])
            let remaining = stops.filter { !done.contains($0) }
            return .effectWalking(next: remaining.first ?? destination, destination: destination)
        }
        return .mission(station: landing)
    }

    // MARK: - 操作

    /// スタート駅に着いたことを記録して旅を始める（R-17）。
    ///
    /// **スタート駅も1駅目として扱う。** 振ってからまとめて記録すると、
    /// 出発する駅だけ「到着した」瞬間が無く、写真も残せなかった。
    /// サイコロを振る前にここで訪問を1行作っておけば、他の駅と同じように写真を紐づけられる。
    /// 何度押しても増えない（1回目だけ効く）
    func startJourney() {
        guard let room else { return }
        autoApplyScheduleIfNeeded()
        do {
            try recordStartVisitIfNeeded(room)
            try context.save()
            enqueueForSync()
        } catch {
            lastError = String(describing: error)
        }
    }

    /// サイコロを振る（F-01）。振った時点で `Turn` を保存するので、
    /// アプリが落ちても出目と行き先が残る。
    func roll() {
        autoApplyScheduleIfNeeded()
        guard let engine else { return }
        // サイコロを使わない予定では**いつも1**。1駅ずつ、そのまま歩くだけ
        let dice = room?.usesDice == false ? 1 : (TestHooks.fixedDice ?? engine.roll())
        roll(dice: dice)
    }

    /// 出目を指定して振る。テストで進行を再現するために分けてある
    func roll(dice: Int) {
        guard let room, let engine, activeTurn == nil else { return }
        do {
            pendingPassingStation = nil
            try recordStartVisitIfNeeded(room)   // 押さずに振った場合もここで始点を残す

            // 着地駅 = 現在位置 + 向き × 出目（R-04）。
            // **いま立っている駅は数に入れず、次の1駅目から数える**ので、出目1なら隣駅で止まる
            let landing = engine.landingOrder(from: currentOrder, dice: dice)
            let nextNo = (room.turns.map(\.turnNo).max() ?? 0) + 1

            let turn = Turn(turnNo: nextNo, diceValue: dice)
            turn.missionSet = room
            turn.fromStation = station(currentOrder)
            turn.landingStation = station(landing)
            turn.fromPosition = currentOrder
            turn.landingPosition = landing
            context.insert(turn)
            try context.save()
            enqueueForSync()
            Telemetry.diceRolled(value: dice)

            showingAnnouncement = true
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 次の駅に到着した（F-04 / F-06）。
    /// `LocationService` の到着判定からも、手動到着（E-01）からも同じ入口を通る。
    ///
    /// - Parameter expected: 到着したはずの駅。いま向かっている駅と食い違う場合は無視する。
    ///   短時間に同じ到着が二度届いても、次の駅まで進んでしまわないための保険（E-04）。
    func arriveAtNextStop(expected: Int? = nil) {
        guard let turn = activeTurn else { return }
        do {
            switch phase {
            case .walking(let next, _):
                guard expected == nil || expected == next else { return }
                let isLanding = next == (turn.landingPosition ?? turn.landingStation?.orderNo)
                try record(visit: isLanding ? .landing : .passing, at: next, turn: turn)
                if isLanding {
                    turn.arrivedAt = Date()
                } else {
                    pendingPassingStation = next   // 写真を撮る間を置く
                }
                try context.save()
                enqueueForSync()

            case .effectWalking(let next, let destination):
                guard expected == nil || expected == next else { return }
                let isArrival = next == destination
                try record(visit: isArrival ? .effectArrival : .effectPassing, at: next, turn: turn)
                if !isArrival { pendingPassingStation = next }
                try context.save()
                if isArrival { try complete(turn, at: destination) }
                enqueueForSync()

            default:
                break
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 通り道の駅での一拍を終えて、次の駅へ向かう
    func continueWalking() {
        pendingPassingStation = nil
    }

    /// 着地駅のミッション候補（R-07 / R-14 既出は除外）。
    ///
    /// 引いたお題の照合には **`persistentModelID` を使う**。
    /// 消えたお題を掴んだままのターンがあると、`id` のような**属性を読んだ瞬間に落ちる**
    /// （SwiftData の `_InvalidFutureBackingData`）。IDだけなら属性を読まずに比べられる。
    /// その駅に書かれているお題。**まだ引かれていないものも含めて全部**。
    ///
    /// 「当日までのお楽しみ」のルームでは、他人のお題は端末に届いていないので
    /// 自分のぶんしか並ばない。伏せるかどうかの判断は取り込みの側が済ませている
    func missions(at order: Int) -> [Mission] {
        guard let room else { return [] }
        return room.missions
            .filter { $0.station?.orderNo == order && $0.station?.course?.name == room.course?.name }
            .sorted { ($0.member?.displayName ?? "") < ($1.member?.displayName ?? "") }
    }

    /// 地図に添える、その駅のお題の短い見出し。
    ///
    /// **旗のピンだけでは「何かある」までしか分からない。**
    /// 一目で中身が読めるよう、1件目を短く切って出す（続きは駅を押せば読める）。
    /// 伏せる設定のルームでは、そもそも他人のお題が端末に無いので自分のぶんだけ出る
    func missionLabel(at order: Int, limit: Int = 12) -> String? {
        let missions = missions(at: order)
        guard let first = missions.first else { return nil }

        let text = first.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = text.count > limit ? text.prefix(limit) + "…" : text[...]
        return missions.count > 1 ? "\(head)　ほか\(missions.count - 1)件" : String(head)
    }

    /// お題が書かれている駅の番号（地図にピンを立てるため）
    var missionOrders: Set<Int> {
        guard let room else { return [] }
        let course = room.course?.name
        return Set(room.missions
            .filter { $0.station?.course?.name == course }
            .compactMap { $0.station?.orderNo })
    }

    func missionCandidates(at order: Int) -> [Mission] {
        guard let room, let station = station(order) else { return [] }
        // お題を使わない予定では候補を出さない。書いたお題は消さず、次の旅に残す
        guard room.usesMissions else { return [] }
        let used = Set(room.turns.compactMap { $0.selectedMission?.persistentModelID })
        return room.missions.filter {
            $0.station?.id == station.id && !used.contains($0.persistentModelID)
        }
    }

    // MARK: - ミッションの自作（SC-12）

    /// この端末の持ち主
    var me: Member? {
        room?.members.first { $0.isMe } ?? room?.members.first
    }

    /// 自分が書いたお題（駅順）
    var myMissions: [Mission] { myMissions(in: room?.course) }

    /// あるコースに書いた、自分のお題。
    ///
    /// **予定の段階から書けるようにする**ため、いま遊んでいるコース以外も指定できる。
    /// お題は駅に紐づき、駅はコースに属するので、コースが決まれば場所も決まる。
    func myMissions(in course: Course?) -> [Mission] {
        guard let me, let course else { return [] }
        return (room?.missions ?? [])
            .filter { $0.member?.id == me.id && $0.station?.course?.name == course.name }
            .sorted { ($0.station?.orderNo ?? 0) < ($1.station?.orderNo ?? 0) }
    }

    /// その駅に自分のお題が既にあるか（駅ごとに1人1個まで。UQ-05）
    func myMission(at order: Int, in course: Course? = nil) -> Mission? {
        myMissions(in: course ?? room?.course).first { $0.station?.orderNo == order }
    }

    /// お題を作る・書き換える。
    ///
    /// - Returns: 保存できなければ理由。呼び出し側はそのまま画面に出してよい
    /// - Parameter course: 書き込む先のコース。省略すると、いま遊んでいるコース。
    ///   予定の段階では、まだ始めていないコースにも書ける
    @discardableResult
    func saveMission(_ existing: Mission?, station order: Int, content: String,
                     effect: EffectType, value: Int?, jumpTo: Int?,
                     in course: Course? = nil) -> String? {
        let targetCourse = course ?? room?.course
        guard let room, let me,
              let target = station(order, in: targetCourse) else { return "ルームがありません" }

        // 同じ駅に2個目は作れない。差し替えは同じお題を編集する
        if let duplicate = myMission(at: order, in: targetCourse), duplicate.id != existing?.id {
            return "\(target.name)にはすでにあなたのお題があります"
        }

        let jumpStation = effect.needsStation
            ? jumpTo.flatMap { station($0, in: targetCourse) } : nil

        // **書き込む前に弾く。** 通してしまうとサーバーの CHECK 制約で 400 になり、
        // 圏外で書いたお題がキューから捨てられる
        if let error = Mission.validationError(content: content,
                                               effectType: effect,
                                               effectValue: effect.needsValue ? value : nil,
                                               hasEffectStation: jumpStation != nil) {
            return error
        }

        let mission = existing ?? Mission(content: content)
        mission.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        mission.effectType = effect
        mission.effectValue = effect.needsValue ? value : nil
        mission.effectStation = jumpStation
        mission.station = target
        mission.missionSet = room
        mission.member = me

        if existing == nil { context.insert(mission) }
        save()
        try? sync?.enqueueMission(mission)
        return nil
    }

    func deleteMission(_ mission: Mission) {
        let id = mission.id

        // **掴んでいるターンの参照を先に外す。** 外さずに消すと、
        // 次にそのターンを開いたときに「消えたお題」を読んで落ちる
        let target = mission.persistentModelID
        for turn in room?.turns ?? []
        where turn.selectedMission?.persistentModelID == target {
            turn.selectedMission = nil
        }

        context.delete(mission)
        save()
        try? sync?.enqueueMissionDelete(missionId: id)
    }

    /// ミッションを抽選する（F-07）。候補が0件ならミッションなしでターンを進める（R-08）
    func drawMission() {
        guard let turn = activeTurn,
              let landing = turn.landingPosition ?? turn.landingStation?.orderNo else { return }
        let candidates = missionCandidates(at: landing)
        Telemetry.missionDrawn(hadCandidates: !candidates.isEmpty)
        guard let picked = candidates.randomElement() else {
            finishMission(done: false)   // 候補0件。効果なしとして扱う
            return
        }
        turn.selectedMission = picked
        save()
        enqueueForSync()
    }

    /// ミッションを終える（F-08 → F-09）。
    /// 暫定では達成の可否にかかわらず効果を発動する（R-09 / Q-10）。
    func finishMission(done: Bool) {
        guard let turn = activeTurn, let engine else { return }
        turn.missionDone = done

        let mission = turn.selectedMission
        let effect = mission?.effectType ?? .none
        turn.appliedEffectType = effect

        let landing = turn.landingPosition ?? turn.landingStation?.orderNo ?? currentOrder
        let destination = engine.endOrder(landing: landing,
                                          effect: effect,
                                          value: mission?.effectValue,
                                          jumpTo: mission?.effectStation?.orderNo)
        do {
            if effect.movesPiece && destination != landing {
                try context.save()      // 移動はこのあと歩いて行う
            } else {
                try complete(turn, at: landing)
            }
            enqueueForSync()
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - 予定（SC-21 / フェーズ3）

    /// 予定（開催が近い順）。過ぎたものは後ろに回す。
    ///
    /// **保持した配列を返す。** その場で `fetch` すると、
    /// 予定を足しても `@Observable` が変化に気づかず、画面が描き直されない
    /// （追加したのに一覧に出ない、という見え方になる）。
    private(set) var schedules: [Schedule] = []

    /// 予定を読み直す。予定を触ったあとと、サーバーから取り込んだあとに呼ぶ
    func reloadSchedules() {
        let all = (try? context.fetch(FetchDescriptor<Schedule>())) ?? []
        let now = Date()
        schedules = all.sorted { lhs, rhs in
            let lhsPast = lhs.startAt < now, rhsPast = rhs.startAt < now
            if lhsPast != rhsPast { return !lhsPast }
            return lhsPast ? lhs.startAt > rhs.startAt : lhs.startAt < rhs.startAt
        }
    }

    /// 次に開催される予定。
    var nextSchedule: Schedule? { schedules.first { $0.startAt >= Date() } }

    /// いまの旅に効かせている予定。旅をリセットしたら外れる
    private(set) var activeSchedule: Schedule?

    /// 予定のルール（コース・区間・一周・サイコロ・お題・見え方）をいまのルームに取り込む。
    /// 歩き出す前だけ有効。始まってから入れ替えると、すでに進んだ盤面と食い違う。
    /// - Returns: 適用できなければ理由
    @discardableResult
    func applySchedule(_ schedule: Schedule) -> String? {
        guard let room else { return "ルームがありません" }
        if hasStartedJourney || !room.turns.isEmpty {
            return "すでに歩き始めています。予定の「記録を保存して新しい旅へ」を押すと、この予定で始められます。"
        }

        // コースは予定に決めたものへ切り替える。
        // **サーバー未参加では serverId が無い**（同梱マスタは nil のまま）ので、名前でも引き当てる
        let planned = schedule.courseServerId.flatMap { id in courses.first { $0.serverId == id } }
            ?? (schedule.courseName.isEmpty ? nil : courses.first { $0.name == schedule.courseName })
        if !schedule.courseName.isEmpty && planned == nil {
            // 手元に無い路線へ半端に合わせるより、何もしない方が壊れない
            return "この予定のコース（\(schedule.courseName)）が端末にありません"
        }

        // コースが違うなら先に切り替える（区間とお題の後始末は updateCourse が引き受ける）
        if let planned, room.course !== planned {
            guard updateCourse(planned) else { return "コースを切り替えられませんでした" }
        }

        let stations = room.course?.stations ?? []
        if let start = stations.first(where: { $0.orderNo == schedule.startOrder }) {
            room.startStation = start
            // 一周はスタートとゴールが同じ駅（MissionSet.isLap はこの一致で決まる）
            room.goalStation = schedule.isLap
                ? start
                : stations.first { $0.orderNo == schedule.goalOrder } ?? room.goalStation
        }
        room.diceMax = min(max(schedule.diceMax, 1), 9)
        room.loopDirectionRaw = schedule.loopDirectionRaw >= 0 ? 1 : -1
        room.usesDice = schedule.usesDice
        room.usesMissions = schedule.usesMissions
        // **選んだ予定の名前を旅の名前にする。** 盤面の見出しがルーム名のままだと、
        // どの予定で歩いているのかが画面から分からない
        room.name = schedule.title
        // 予定とルームでは**0と1の意味が逆**。必ず変換を通す。
        // updateMissionVisibility が「お楽しみへ戻したら他人のお題を消す」後始末までやる
        let visibility = MissionVisibility(scheduleVisibility: schedule.missionVisibility)
        if room.missionVisibility != visibility {
            updateMissionVisibility(visibility)
            // サーバーの取り決めも合わせる（お題を伏せる/見せるはサーバーが実際に絞る）
            Task { [sync] in await sync?.updateMissionVisibility(visibility) }
        }
        activeSchedule = schedule
        save()
        return nil
    }

    /// 歩き出す時点でまだ予定を取り込んでいなければ、直近の予定を自動で効かせる。
    /// ホームの「旅をスタート」を通らず、盤面から直接始めた場合の取りこぼしを防ぐ
    private func autoApplyScheduleIfNeeded() {
        guard activeSchedule == nil, !hasStartedJourney,
              let candidate = schedules.first(where: { !$0.isFinished() }) else { return }
        applySchedule(candidate)
    }

    /// 予定を立てる・書き換える。
    /// - Returns: 保存できなければ理由
    @discardableResult
    func saveSchedule(_ existing: Schedule?, title: String,
                      startAt: Date, meetPlace: String?,
                      course: Course? = nil, startOrder: Int? = nil,
                      goalOrder: Int? = nil, diceMax: Int? = nil,
                      isLap: Bool? = nil, loopDirection: Int? = nil,
                      usesDice: Bool? = nil, usesMissions: Bool? = nil,
                      missionVisibility: Int? = nil, arrivalRadius: Double? = nil,
                      isShared: Bool? = nil, timeZoneIdentifier: String? = nil) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "予定の名前を入力してください" }
        if trimmed.count > 100 { return "予定の名前は100文字までです" }

        // サーバーでも同じ判定をしているが、圏外で書いたものが後から弾かれると分かりにくい
        if let existing, let owner = existing.createdById,
           let me = me?.id, owner != me {
            return "予定を立てた人だけが変更できます"
        }

        let selectedCourse = course ?? room?.course
        let selectedStart = startOrder ?? room?.startStation?.orderNo ?? 0
        let selectedGoal = goalOrder ?? room?.goalStation?.orderNo ?? 0
        guard let selectedCourse else { return "コースを選んでください" }

        // **一周は同じ駅で始まって同じ駅で終わる。** 山手線を東京から出て東京へ戻る形。
        // 一周でないときだけ「別の駅」を求める
        let lapping = isLap ?? existing?.isLap ?? false
        if lapping && !selectedCourse.isLoop {
            return "このコースは一周できません"
        }
        if !lapping && selectedStart == selectedGoal {
            return "スタートとゴールは別の駅にしてください"
        }

        let schedule = existing ?? Schedule(title: trimmed, startAt: startAt)
        schedule.title = trimmed
        schedule.startAt = startAt
        schedule.meetPlace = meetPlace?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        schedule.courseServerId = selectedCourse.serverId
        schedule.courseName = selectedCourse.name
        schedule.startOrder = selectedStart
        // 一周では出発した駅へ戻る。ゴールはスタートと同じ駅にそろえる
        schedule.goalOrder = lapping ? selectedStart : selectedGoal
        schedule.diceMax = min(max(diceMax ?? room?.diceMax ?? 6, 1), 9)
        schedule.isLap = lapping
        if let loopDirection { schedule.loopDirectionRaw = loopDirection >= 0 ? 1 : -1 }
        if let usesDice { schedule.usesDice = usesDice }
        if let usesMissions { schedule.usesMissions = usesMissions }
        if let missionVisibility { schedule.missionVisibilityRaw = missionVisibility }
        if let arrivalRadius {
            schedule.arrivalRadius = min(max(arrivalRadius, ArrivalRule.radiusRange.lowerBound),
                                         ArrivalRule.radiusRange.upperBound)
        }
        if let isShared { schedule.isShared = isShared }
        schedule.timeZoneIdentifier = timeZoneIdentifier
        if existing == nil {
            Telemetry.scheduleCreated(course: selectedCourse.name, isLap: lapping)
        }

        if existing == nil {
            schedule.missionSet = room
            schedule.createdById = me?.id
            context.insert(schedule)
        }
        save()
        reloadSchedules()               // 追加した予定をその場で一覧に出す
        try? sync?.enqueueSchedule(schedule)
        return nil
    }

    func deleteSchedule(_ schedule: Schedule) {
        let id = schedule.id
        context.delete(schedule)
        save()
        reloadSchedules()
        try? sync?.enqueueScheduleDelete(scheduleId: id)
    }

    /// 自分の出欠を答える。**他人のぶんは動かせない**
    func answerAttendance(_ schedule: Schedule, status: AttendanceStatus) {
        guard let me else { return }

        if let mine = schedule.attendees.first(where: { $0.memberId == me.id }) {
            mine.status = status
        } else {
            let created = Attendance(memberId: me.id, displayName: me.displayName, status: status)
            created.schedule = schedule
            context.insert(created)
        }
        save()
        try? sync?.enqueueAttendance(scheduleId: schedule.id, status: status)
    }

    func myAttendance(_ schedule: Schedule) -> AttendanceStatus {
        guard let me else { return .undecided }
        return schedule.attendees.first { $0.memberId == me.id }?.status ?? .undecided
    }

    // MARK: - 写真

    /// いま写真を紐づけるべき訪問。
    /// 進行中ターンの最後の訪問（＝いる駅）に付ける。
    ///
    /// ターンの外や、振った直後でまだどこにも着いていないあいだは、
    /// **最後に着いた駅の訪問**に付ける。こうするとスタート駅や、
    /// ターンを終えて次を振るまでのあいだでも写真を残せる（R-19）
    var currentVisit: Visit? {
        if let turn = activeTurn,
           let latest = turn.visits.max(by: { $0.arrivedAt < $1.arrivedAt }) {
            return latest
        }
        return room?.visits.max { $0.arrivedAt < $1.arrivedAt }
    }

    /// 撮った写真を保存し、いる駅の訪問に紐づける（F-05）
    func attachPhoto(_ image: UIImage) {
        guard let room else { return }
        // スタート駅でまだ何も記録していなければ、ここで始点を作って紐づけ先にする
        try? recordStartVisitIfNeeded(room)
        guard let visit = currentVisit else { return }
        do {
            let fileName = try PhotoStore.save(image)
            Telemetry.photoTaken()
            let photo = Photo(localFileName: fileName)
            photo.visit = visit
            photo.member = room.members.first { $0.isMe } ?? room.members.first
            context.insert(photo)
            try context.save()
            enqueueForSync()      // 始点をここで作った場合に備えて積み直す
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - 時間とペース

    /// 歩いた時間の内訳（合計・移動・ミッション）
    var timing: WalkTiming.Total {
        guard let room else { return .init(walkingSeconds: 0, missionSeconds: 0,
                                           elapsedSeconds: 0, meters: 0) }
        return WalkTiming.total(in: room)
    }

    /// 区間ごとの記録（古い順）。地図の色分けにも使う
    var legs: [WalkTiming.Leg] {
        guard let room else { return [] }
        return WalkTiming.legs(in: room)
    }

    /// 進行中のターンの内訳。振ってからの経過を画面に出すために使う
    var currentTurnBreakdown: WalkTiming.TurnBreakdown? {
        activeTurn.map { WalkTiming.breakdown(of: $0) }
    }

    /// ある駅に着いた区間の記録（複数回訪れていれば複数件）
    func legs(arrivingAt order: Int) -> [WalkTiming.Leg] {
        legs.filter { $0.toOrder == order }
    }

    /// 写真が1枚でもある駅の番号。地図にピンを出す
    var photographedOrders: Set<Int> {
        Set((room?.visits ?? [])
            .filter { !$0.photos.isEmpty }
            .compactMap { $0.station?.orderNo })
    }

    /// ある駅で撮った写真のファイル名（新しい順）
    func photoFileNames(at order: Int) -> [String] {
        (room?.visits ?? [])
            .filter { $0.station?.orderNo == order }
            .flatMap(\.photos)
            .sorted { $0.takenAt > $1.takenAt }
            .map(\.localFileName)
    }

    /// ある駅への訪問記録（古い順）。再訪していれば複数件
    func visits(at order: Int) -> [Visit] {
        (room?.visits ?? [])
            .filter { $0.station?.orderNo == order }
            .sorted { $0.arrivedAt < $1.arrivedAt }
    }

    // MARK: - 保存済みの旅

    /// 終えた旅（新しい順）。現在の旅とは別に何件でも残る。
    var archives: [JourneyArchive] {
        ((try? context.fetch(FetchDescriptor<JourneyArchive>())) ?? [])
            .sorted { $0.endedAt > $1.endedAt }
    }

    /// 記録を保存して最初からやり直す（SC-20）。
    /// `archive` が true なら写真ファイルも履歴から参照するため残す。
    func resetProgress(archive: Bool = true) {
        guard let room else { return }
        do {
            if archive { try archiveCurrentJourney(room) }

            // 画面に残る一時状態を先に落とす。消したターンや訪問を掴んだまま
            // 描き直しが走ると、SwiftData が「元のデータが無い」と言って落ちる
            pendingPassingStation = nil
            showingAnnouncement = false

            // 関係をたどりながら消すと途中で配列が変わる。**先に控えを取ってから消す**
            let visits = Array(room.visits)
            let turns = Array(room.turns)
            let photos = visits.flatMap(\.photos)
            let photoFileNames = photos.map(\.localFileName)

            // 参照を外してから消す。cascade の順序に任せると、
            // 消えた行を別の行が指したままになることがある
            for photo in photos {
                photo.visit = nil
                photo.member = nil
                context.delete(photo)
            }
            for visit in visits {
                visit.turn = nil
                visit.station = nil
                visit.missionSet = nil
                context.delete(visit)
            }
            for turn in turns {
                turn.selectedMission = nil
                turn.fromStation = nil
                turn.landingStation = nil
                turn.endStation = nil
                turn.missionSet = nil
                context.delete(turn)
            }
            // 歩いた跡も前の旅のもの。残すと次の旅の地図に他人の線が出る
            for point in Array(room.trackPoints) {
                point.missionSet = nil
                context.delete(point)
            }
            try context.save()

            // 記録として残すなら実体は消さない。破棄するときだけ消す
            if !archive {
                for fileName in photoFileNames { PhotoStore.delete(fileName) }
            }

            try sync?.enqueueReset()
        } catch {
            lastError = String(describing: error)
        }
    }

    func deleteArchive(_ archive: JourneyArchive) {
        for fileName in archive.photoFileNames { PhotoStore.delete(fileName) }
        context.delete(archive)
        save()
    }

    private func archiveCurrentJourney(_ room: MissionSet) throws {
        guard !room.turns.isEmpty else { return }
        let summary = JourneySummary(room: room, engine: engine)
        let startedAt = room.turns.map(\.rolledAt).min() ?? Date()
        let endedAt = room.turns.compactMap(\.completedAt).max()
            ?? room.visits.map(\.arrivedAt).max() ?? Date()
        let archive = JourneyArchive(roomName: summary.roomName,
                                     courseName: room.course?.name ?? "",
                                     startedAt: startedAt,
                                     endedAt: endedAt)
        archive.elapsedSeconds = summary.timing.elapsedSeconds
        archive.walkingSeconds = summary.timing.walkingSeconds
        archive.meters = summary.timing.meters
        archive.visitedCount = summary.visitedCount
        archive.stationCount = summary.stationCount
        archive.turnCount = summary.turnCount
        archive.photoCount = summary.photoCount
        archive.isCleared = summary.isCleared
        archive.routeSummary = summary.stations.filter { $0.visitCount > 0 }
            .map(\.name).joined(separator: " → ")
        archive.photoFileNamesText = summary.stations.flatMap(\.photoFileNames)
            .joined(separator: "\n")
        context.insert(archive)
    }

    /// 選べるコース（フェーズ4）
    var courses: [Course] {
        ((try? context.fetch(FetchDescriptor<Course>())) ?? [])
            .sorted { $0.stations.count > $1.stations.count }
    }

    /// 遊ぶコースを変える。進行中は変えられない（T-06）。
    ///
    /// **区間は新しいコースの両端に置き直す。** 前のコースの駅を指したままだと、
    /// 区間の外を指す設定になって進行が破綻する。
    @discardableResult
    func updateCourse(_ course: Course) -> Bool {
        guard let room, room.turns.isEmpty else { return false }

        let sorted = course.stations.sorted { $0.orderNo < $1.orderNo }
        guard let first = sorted.first, let last = sorted.last else { return false }

        // 別のコースに書いたお題は**消さない**。予定の段階から書けるようにしたので、
        // コースを変えるたびに消すと、次の旅のために用意したお題まで失われる。
        // 抽選は着地した駅（＝いまのコースの駅）で引くため、混ざる心配はない
        room.course = course
        room.startStation = first
        room.goalStation = last
        save()
        return true
    }

    /// この旅で撮った写真を、撮った順に。**どこからでも見られるようにするため**
    var photoItems: [PhotoGalleryView.Item] {
        (room?.visits ?? [])
            .flatMap { visit in
                visit.photos.map { photo in
                    PhotoGalleryView.Item(fileName: photo.localFileName,
                                          stationName: visit.station?.name ?? "-",
                                          takenAt: photo.takenAt)
                }
            }
            .sorted { $0.takenAt < $1.takenAt }
    }

    /// このターンで通る駅（着地は含まない）。
    ///
    /// **駅の通し番号ではなく「位置」で数える。** 一周では番号が一巡して元に戻るため、
    /// 番号のまま経路を出すと逆向きに路線をほぼ一周ぶん並べてしまう
    /// （札幌市電で「途中の◯◯も1駅ずつ歩いて訪れます」が大量に出た原因）。
    ///
    /// - Returns: 位置の並び。名前は `stationName(_:)` で引ける
    func passingPositions(of turn: Turn) -> [Int] {
        guard let engine else { return [] }
        let from = turn.fromPosition ?? turn.fromStation?.orderNo ?? currentOrder
        let landing = turn.landingPosition ?? turn.landingStation?.orderNo ?? currentOrder
        return Array(engine.path(from: from, to: landing).dropLast())
    }

    /// このターンの着地位置
    func landingPosition(of turn: Turn) -> Int {
        turn.landingPosition ?? turn.landingStation?.orderNo ?? currentOrder
    }

    // MARK: - 歩いた跡

    /// 跡を残す間隔。これより近い点は捨てる。
    ///
    /// **色を50mごとに変えるので、点はそれより細かく要る。**
    /// 20mおきだと1区切りに2点しか入らず、GPSの誤差がそのまま色に出る。
    /// 測位そのものは動きっぱなしなので、ここを詰めても電池はほとんど変わらない
    /// （増えるのは保存の回数）
    private static let trackMinimumDistance: CLLocationDistance = 10
    /// これより粗い点は跡に混ぜない。地下や高層ビルの谷間では大きく飛ぶ
    private static let trackWorstAccuracy: CLLocationDistance = 60

    /// 実際に歩いた位置を残す。
    ///
    /// **歩いている間だけ残す。** 待っている間の点まで拾うと、
    /// 駅で立ち止まっているところが団子になって線が汚れる。
    /// サーバーへは送らない（生のGPS座標は端末の外へ出さない約束）
    func recordTrackPoint(_ location: CLLocation) {
        guard let room else { return }
        switch phase {
        case .walking, .effectWalking: break
        default: return
        }
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= Self.trackWorstAccuracy else { return }

        if let last = room.trackPoints.max(by: { $0.recordedAt < $1.recordedAt }) {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            guard location.distance(from: previous) >= Self.trackMinimumDistance else { return }
        }

        let point = TrackPoint(latitude: location.coordinate.latitude,
                               longitude: location.coordinate.longitude,
                               accuracy: location.horizontalAccuracy,
                               recordedAt: location.timestamp)
        point.missionSet = room
        context.insert(point)
        save()
    }

    /// 歩いた跡（古い順）
    var trackPoints: [TrackPoint] {
        (room?.trackPoints ?? []).sorted { $0.recordedAt < $1.recordedAt }
    }

    // MARK: - 予定から始める

    /// これから歩ける予定。**始めるときに選ばせるためのもの**。
    ///
    /// 終わった予定は出さない（当日を過ぎたら選ぶ意味がない）。
    /// コースが端末に無い予定も出さない（選んでもルールを移せない）。
    /// 集合が近い順に並べる
    var startableSchedules: [Schedule] {
        let now = Date()
        return schedules
            .filter { $0.startAt >= Calendar.current.startOfDay(for: now) }
            .filter { schedule in
                !schedule.courseName.isEmpty
                    && courses.contains { $0.name == schedule.courseName }
            }
            .sorted { $0.startAt < $1.startAt }
    }

    /// お題の見え方を変える。**プレイ中でも変えられる**
    /// （区間や出目と違い、すでにある記録の整合を壊さない）。
    ///
    /// お楽しみへ戻したときは、端末に残っている他人のお題を消す。
    /// 残すと「戻したのに見えたまま」になる
    func updateMissionVisibility(_ visibility: MissionVisibility) {
        guard let room else { return }
        Telemetry.missionVisibilityChanged(to: visibility)
        room.missionVisibility = visibility

        if visibility == .surprise, let me {
            for mission in room.missions where mission.member?.id != me.id {
                deleteMission(mission)       // 掴んでいるターンの参照も外してくれる
            }
        }
        save()
    }

    /// 一周する／しないを切り替える（環状コースだけ）。
    /// 一周のときはスタートとゴールを同じ駅にする
    @discardableResult
    func updateLap(_ on: Bool) -> Bool {
        guard let room, room.turns.isEmpty, room.course?.isLoop == true else { return false }
        let sorted = (room.course?.stations ?? []).sorted { $0.orderNo < $1.orderNo }
        guard let first = sorted.first, let last = sorted.last else { return false }

        if on {
            room.goalStation = room.startStation ?? first
            room.startStation = room.goalStation
        } else {
            room.startStation = first
            room.goalStation = last
        }
        save()
        return true
    }

    /// まわる向きを変える（`1` = 通し番号が増える向き / `-1` = 減る向き）
    @discardableResult
    func updateLoopDirection(_ direction: Int) -> Bool {
        guard let room, room.turns.isEmpty else { return false }
        room.loopDirectionRaw = direction >= 0 ? 1 : -1
        save()
        return true
    }

    /// 一周の出発駅を変える。ゴールも同じ駅にそろえる
    @discardableResult
    func updateLapStart(orderNo: Int) -> Bool {
        guard let room, room.turns.isEmpty, room.isLap,
              let station = station(orderNo, in: room.course) else { return false }
        room.startStation = station
        room.goalStation = station
        save()
        return true
    }

    /// 到着判定の半径。**予定に決めた値 > 路線ごとの値**の順で、先に決まっているものを使う
    var arrivalRadius: Double? { activeSchedule?.arrivalRadius ?? room?.course?.arrivalRadius }

    /// 区間と最大出目を変更する。進行中は変えられない（T-06）
    func updateRule(start: Station?, goal: Station?, diceMax: Int) -> Bool {
        guard let room, room.turns.isEmpty else { return false }
        if let start { room.startStation = start }
        if let goal { room.goalStation = goal }
        room.diceMax = min(max(diceMax, 1), 9)
        save()
        return true
    }

    // MARK: - 補助

    /// 位置の番号から駅を引く。
    /// **環状の一周では番号が駅数を超える**ので、engine を通して実際の駅に直す
    func station(_ order: Int) -> Station? {
        station(engine?.stationOrder(at: order) ?? order, in: room?.course)
    }

    func station(_ order: Int, in course: Course?) -> Station? {
        course?.stations.first { $0.orderNo == order }
    }

    func stationName(_ order: Int) -> String { station(order)?.name ?? "-" }

    /// 効果による移動先
    private func effectDestination(of turn: Turn) -> Int? {
        guard let engine, let effect = turn.appliedEffectType, effect.movesPiece else { return nil }
        let landing = turn.landingPosition ?? turn.landingStation?.orderNo ?? currentOrder
        let destination = engine.endOrder(landing: landing,
                                          effect: effect,
                                          value: turn.selectedMission?.effectValue,
                                          jumpTo: turn.selectedMission?.effectStation?.orderNo)
        return destination == landing ? nil : destination
    }

    private func visitedOrders(in turn: Turn, kinds: Set<VisitKind>) -> Set<Int> {
        Set(turn.visits
            .filter { kinds.contains($0.visitKind) }
            .compactMap { $0.position ?? $0.station?.orderNo })
    }

    private func record(visit kind: VisitKind, at order: Int, turn: Turn?) throws {
        guard let room, let station = station(order) else { return }
        let visit = Visit(kind: kind)
        visit.missionSet = room
        visit.turn = turn
        visit.station = station
        visit.position = order            // 一周では駅の通し番号と食い違う
        context.insert(visit)
    }

    /// 始点を記録する（R-17）。踏破率の分子に含めるため
    private func recordStartVisitIfNeeded(_ room: MissionSet) throws {
        guard room.visits.isEmpty, let start = room.startStation?.orderNo else { return }
        try record(visit: .start, at: start, turn: nil)
    }

    private func complete(_ turn: Turn, at order: Int) throws {
        turn.endStation = station(order)
        turn.endPosition = order
        turn.completedAt = Date()
        pendingPassingStation = nil
        try context.save()
    }

    private func save() {
        do { try context.save() } catch { lastError = String(describing: error) }
    }

    /// 直近のターンと訪問を送信キューへ積み直す。
    ///
    /// 同じ対象はキュー側で最新の1件にまとまるので、積みすぎても害はない。
    /// **積めなくてもプレイは止めない。** ローカルの記録が正で、送信は後から追いつけばよい。
    private func enqueueForSync() {
        guard let sync, let room else { return }
        do {
            // 始点はどのターンにも属さないので先に積む
            for visit in room.visits where visit.turn == nil {
                try sync.enqueueVisit(visit)
            }
            guard let turn = room.turns.max(by: { $0.rolledAt < $1.rolledAt }) else { return }
            // ターンより先に訪問が届くと、まだ無いターンに紐づけようとして弾かれる
            try sync.enqueueTurn(turn)
            for visit in turn.visits.sorted(by: { $0.arrivedAt < $1.arrivedAt }) {
                try sync.enqueueVisit(visit)
            }
        } catch {
            lastError = String(describing: error)
        }
    }
}
