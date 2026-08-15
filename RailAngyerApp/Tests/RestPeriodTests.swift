import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 休憩（`RestPeriod`）。
///
/// 現地で座って休んだ時間を、歩いた時間から差し引く。
/// **休憩を終え忘れても記録が壊れない**ことと、
/// 前の旅の休憩が次の旅に残らないことを確かめる。
@MainActor
struct RestPeriodTests {

    private let context: ModelContext
    private let store: GameSessionStore
    /// 2023-11-14。**`Date()` より前**にしておく。
    /// 終わっていない休憩は「いま」までとして数えるので、未来を基準にすると測れない
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    /// 着地または効果移動の終了まで歩かせる
    private func walk() {
        for _ in 0..<40 {
            switch store.phase {
            case .walking, .effectWalking: store.arriveAtNextStop()
            case .arrivedPassing:          store.continueWalking()
            default:                       return
            }
        }
    }

    /// 1ターン歩ききって、時刻を `base` からの秒数で置き直す。
    /// 出発が `base`、着地が `base + arrivedAfter`
    ///
    /// - Parameter drawsMission: false なら着いたところで止める。
    ///   お題の無いルームでは `drawMission()` がそのままターンを終わらせてしまい、
    ///   **「途中でやめる」場面（終わっていないターンが残る）を再現できない**
    private func playTurn(dice: Int, arrivedAfter: TimeInterval,
                          drawsMission: Bool = true) throws -> Turn {
        store.roll(dice: dice)
        walk()
        if drawsMission { store.drawMission() }

        let turn = try #require(store.room?.turns.max { $0.turnNo < $1.turnNo })
        turn.rolledAt = base
        // スタート駅の訪問は「旅を始めた実時刻」で入る。集計の終わりを拾うときに
        // 混ざるので、こちらも `base` に揃えておく
        for visit in store.room?.visits ?? [] where visit.turn == nil {
            visit.arrivedAt = base
        }
        let visits = turn.visits
            .filter { $0.visitKind == .passing || $0.visitKind == .landing }
            .sorted { ($0.station?.orderNo ?? 0) < ($1.station?.orderNo ?? 0) }
        for (index, visit) in visits.enumerated() {
            visit.arrivedAt = base.addingTimeInterval(arrivedAfter / Double(visits.count)
                                                        * Double(index + 1))
        }
        turn.arrivedAt = visits.last?.arrivedAt
        return turn
    }

    /// `base` からの秒数で休憩を1件作る。`to` が nil なら休憩中のまま
    @discardableResult
    private func addRest(from: TimeInterval, to: TimeInterval?) throws -> RestPeriod {
        let room = try #require(store.room)
        let rest = RestPeriod(startedAt: base.addingTimeInterval(from))
        rest.endedAt = to.map { base.addingTimeInterval($0) }
        rest.missionSet = room
        context.insert(rest)
        return rest
    }

    // MARK: - 区間から差し引く

    @Test("休んでいたぶんを区間の時間から差し引く")
    func subtractsRestFromLeg() throws {
        let turn = try playTurn(dice: 1, arrivedAfter: 600)
        try addRest(from: 100, to: 300)

        let leg = try #require(WalkTiming.legs(in: turn).first)
        #expect(leg.restSeconds == 200)
        #expect(leg.seconds == 400, "10分かかった区間のうち、休んだ200秒は歩いていない")
        #expect(leg.pace.seconds == 400, "ペースも休憩を除いたぶんで測る")
    }

    @Test("区間に半分だけかかった休憩は、重なったぶんだけ引く")
    func subtractsOnlyTheOverlappingPart() throws {
        let turn = try playTurn(dice: 1, arrivedAfter: 600)
        try addRest(from: -100, to: 100)   // 振る前から休んでいて、100秒で歩き出した
        try addRest(from: 500, to: 900)    // 着く100秒前から休み、着いてからも休んでいた

        let leg = try #require(WalkTiming.legs(in: turn).first)
        #expect(leg.restSeconds == 200, "はみ出したぶんは数えない")
        #expect(leg.seconds == 400)
    }

    @Test("重なっていない休憩は区間から引かない")
    func ignoresRestOutsideTheLeg() throws {
        let turn = try playTurn(dice: 1, arrivedAfter: 600)
        try addRest(from: 900, to: 1_500)  // 着いたあとに休んだ

        let leg = try #require(WalkTiming.legs(in: turn).first)
        #expect(leg.restSeconds == 0)
        #expect(leg.seconds == 600)
    }

    @Test("通り道をまたぐときは、休憩がかかった区間だけが短くなる")
    func subtractsFromTheOverlappingLegOnly() throws {
        let turn = try playTurn(dice: 3, arrivedAfter: 1_800)   // 600秒ずつ3区間
        try addRest(from: 700, to: 1_000)                        // 2区間目のまん中で休む

        let legs = WalkTiming.legs(in: turn)
        #expect(legs.count == 3)
        #expect(legs.map(\.restSeconds) == [0, 300, 0])
        #expect(legs.map(\.seconds) == [600, 300, 600])
    }

    @Test("終わっていない休憩は、基準時刻までとして数える")
    func countsOngoingRestUntilNow() throws {
        let turn = try playTurn(dice: 1, arrivedAfter: 600)
        try addRest(from: 200, to: nil)    // 休んだまま終えていない

        let leg = try #require(WalkTiming.legs(in: turn, now: base.addingTimeInterval(400)).first)
        #expect(leg.restSeconds == 200)
        #expect(leg.seconds == 400)
    }

    @Test("休憩を内訳の1枠として切り出し、その他から外す")
    func reportsRestAsItsOwnBucket() throws {
        let turn = try playTurn(dice: 1, arrivedAfter: 600)
        turn.completedAt = base.addingTimeInterval(1_200)
        try addRest(from: 100, to: 300)

        let room = try #require(store.room)
        let total = WalkTiming.total(in: room, now: base.addingTimeInterval(1_200))
        #expect(total.elapsedSeconds == 1_200)
        #expect(total.restSeconds == 200)
        #expect(total.walkingSeconds == 400, "歩きの時間からは休憩を引いてある")
        #expect(total.missionSeconds == 600, "着地してからターンが終わるまで")
        #expect(total.otherSeconds == 0, "1200 = 歩き400 + お題600 + 休憩200")
    }

    @Test("お題の最中に休んでも、内訳の合計が旅の長さと一致する")
    func subtractsRestFromMissionTime() throws {
        let turn = try playTurn(dice: 1, arrivedAfter: 600)
        turn.completedAt = base.addingTimeInterval(1_200)
        try addRest(from: 700, to: 900)   // 着いてから、お題に取りかかる前に一息

        let breakdown = WalkTiming.breakdown(of: turn, now: base.addingTimeInterval(1_200))
        #expect(breakdown.walkingSeconds == 600, "歩いている間は休んでいない")
        #expect(breakdown.missionSeconds == 400, "お題の10分のうち200秒は休んでいた")

        let room = try #require(store.room)
        let total = WalkTiming.total(in: room, now: base.addingTimeInterval(1_200))
        #expect(total.restSeconds == 200)
        #expect(total.otherSeconds == 0)
        #expect(total.walkingSeconds + total.missionSeconds
                    + total.restSeconds + total.otherSeconds == total.elapsedSeconds,
                "移動＋お題＋休憩＋その他 = 合計。崩れると max(0,...) に潰されて静かに食い違う")
    }

    // MARK: - 開始と終了

    @Test("休憩を始めて終えると、その区間が残る")
    func startsAndEndsRest() throws {
        store.startRest()
        let rest = try #require(store.activeRest)
        #expect(rest.endedAt == nil)

        store.startRest()   // 二度押しても増えない
        #expect(store.room?.restPeriods.count == 1)

        store.endRest()
        #expect(store.activeRest == nil)
        #expect(rest.endedAt != nil)
        #expect(store.lastError == nil)
    }

    @Test("サイコロを振ったら休憩は自動で終わる")
    func rollingDiceEndsRest() throws {
        store.startRest()
        let rest = try #require(store.activeRest)

        store.roll(dice: 1)

        #expect(store.activeRest == nil, "振った＝もう歩き出している")
        #expect(rest.endedAt != nil, "終え忘れると以降の時間が丸ごと歩行時間から引かれてしまう")
        #expect(store.activeTurn != nil)
    }

    // MARK: - 旅を畳む

    @Test("旅を畳むと休憩も消える")
    func resetRemovesRestPeriods() throws {
        store.roll(dice: 1)
        walk()
        store.drawMission()
        store.finishMission(done: true)
        store.startRest()

        store.resetProgress()

        #expect(store.activeRest == nil)
        #expect(store.room?.restPeriods.isEmpty == true, "前の旅の休憩が次の旅から引かれてしまう")
        #expect(store.lastError == nil)
        #expect(try context.fetch(FetchDescriptor<RestPeriod>()).isEmpty)
    }

    @Test("畳んだあとの記録にも休んだ時間が残る")
    func archiveKeepsRestSeconds() throws {
        let turn = try playTurn(dice: 1, arrivedAfter: 600)
        turn.completedAt = base.addingTimeInterval(1_200)
        try addRest(from: 100, to: 300)

        store.resetProgress()

        let archive = try #require(store.archives.first)
        #expect(archive.restSeconds == 200, "休憩の行は消えるので、内訳はここにしか残らない")
        #expect(archive.walkingSeconds == 400, "歩きの時間からは既に引いてある")
        #expect(try context.fetch(FetchDescriptor<RestPeriod>()).isEmpty)
    }

    @Test("途中でやめた旅は、ふりかえりを眺めていた時間で記録が変わらない")
    func freezesTheClockWhenQuittingMidJourney() throws {
        // 着いてお題を引いたところでやめる。**最後のターンは終わっていない**ので、
        // 集計はそのターンを「いままで」で測る＝基準時刻しだいで数字が動く
        _ = try playTurn(dice: 1, arrivedAfter: 600, drawsMission: false)
        #expect(store.activeTurn != nil, "終わっていないターンが残っている状態")

        // やめると決めた瞬間（＝ふりかえりを開いた時刻）。
        // 実時間は `base` から何年も進んでいるので、凍結できていなければ桁が変わる
        let decidedAt = base.addingTimeInterval(1_800)
        store.resetProgress(now: decidedAt)

        let archive = try #require(store.archives.first)
        #expect(archive.elapsedSeconds == 1_800, "眺めた時間は旅の長さに入らない")
        #expect(archive.startedAt == base)
        #expect(archive.endedAt == decidedAt)
        #expect(archive.endedAt.timeIntervalSince(archive.startedAt) == archive.elapsedSeconds,
                "終わり − 始まり = 合計")
    }

    @Test("やめると決めた時刻で休憩を閉じられる")
    func endsRestAtTheFrozenMoment() throws {
        _ = try playTurn(dice: 1, arrivedAfter: 600, drawsMission: false)

        store.startRest()
        let rest = try #require(store.activeRest)
        rest.startedAt = base.addingTimeInterval(300)   // 歩いている途中で休み始めた

        let decidedAt = base.addingTimeInterval(1_800)
        store.endRest(at: base.addingTimeInterval(1_200))
        #expect(rest.endedAt == base.addingTimeInterval(1_200))

        store.resetProgress(now: decidedAt)

        let archive = try #require(store.archives.first)
        #expect(archive.restSeconds == 900, "休んだのは15分。眺めていたぶんは足されない")
        #expect(archive.walkingSeconds == 300, "10分の区間のうち、後半5分は休んでいた")
        #expect(archive.elapsedSeconds == 1_800)
    }

    @Test("一度も歩いていない旅は記録に残さない")
    func doesNotArchiveAnEmptyJourney() throws {
        store.resetProgress()
        #expect(store.archives.isEmpty, "始めてもいない旅")

        store.startJourney()            // 押しただけで、まだ振っていない
        store.resetProgress()
        #expect(store.archives.isEmpty, "間違えて始めただけの旅は並べない")
        #expect(store.lastError == nil)
    }

    @Test("一度でも振った旅は記録に残す")
    func archivesAJourneyThatStarted() throws {
        store.roll(dice: 1)
        walk()

        store.resetProgress()
        #expect(store.archives.count == 1)
    }
}
