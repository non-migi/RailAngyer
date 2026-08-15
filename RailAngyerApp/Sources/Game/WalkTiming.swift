import Foundation
import RailAngyerCore

/// 歩いた時間の内訳（「合計・移動・ミッション」）と、区間ごとのペース。
///
/// **時刻の記録はフェーズ1から全部残っている**（`Turn.rolledAt` / `Visit.arrivedAt` /
/// `Turn.completedAt`）ので、新しく保存するものは無い。後から数え直すだけで出せる。
enum WalkTiming {

    /// 1区間（駅から次の駅まで）の記録
    struct Leg: Identifiable {
        let id: UUID
        let turnNo: Int
        let fromOrder: Int
        let toOrder: Int
        let fromName: String
        let toName: String
        let departedAt: Date
        let arrivedAt: Date
        /// この区間と重なっていた休憩の合計。歩いた時間から差し引く
        let restSeconds: TimeInterval
        let pace: Pace
        /// 効果による移動か（出目の移動と区別して見せる）
        let isEffectMove: Bool

        /// 実際に歩いていた時間（休憩を除いたぶん）
        var seconds: TimeInterval {
            max(0, arrivedAt.timeIntervalSince(departedAt) - restSeconds)
        }
        var category: PaceCategory? { pace.category }
    }

    /// 1ターンの内訳
    struct TurnBreakdown {
        let turnNo: Int
        /// 歩いていた時間
        let walkingSeconds: TimeInterval
        /// 着地してからミッションを終えるまで
        let missionSeconds: TimeInterval
        /// 振ってからターンが終わるまで。進行中なら「いままで」
        let totalSeconds: TimeInterval
        let meters: Double
        let isCompleted: Bool

        var pace: Pace { Pace(meters: meters, seconds: walkingSeconds) }
    }

    // MARK: - 区間

    /// ルーム全体の区間記録（古い順）
    static func legs(in room: MissionSet, now: Date = Date()) -> [Leg] {
        room.turns
            .sorted { $0.rolledAt < $1.rolledAt }
            .flatMap { legs(in: $0, now: now) }
    }

    /// 1ターンぶんの区間記録。
    ///
    /// 出発時刻は**ターンを振った時刻**から始め、以降は前の駅に着いた時刻を使う。
    /// 効果による移動は、ミッションを終えた時点（＝最初の効果訪問の直前）から測る。
    ///
    /// **休んでいた時間は区間から差し引く**（`RestPeriod`）。座って休んだ10分を
    /// 歩いた時間に混ぜると、その駅間だけ不当に遅く見える。
    ///
    /// - Parameter now: 終わっていない休憩をどこまでとして数えるかの基準時刻
    static func legs(in turn: Turn, now: Date = Date()) -> [Leg] {
        let ordered = turn.visits.sorted { $0.arrivedAt < $1.arrivedAt }
        guard !ordered.isEmpty else { return [] }

        var result: [Leg] = []
        var previousStation = turn.fromStation
        var previousTime = turn.rolledAt
        let rests = turn.missionSet?.restPeriods ?? []

        for visit in ordered {
            guard let to = visit.station else { continue }
            guard let from = previousStation, from.orderNo != to.orderNo else { continue }
            guard visit.arrivedAt > previousTime else { continue }   // 時刻が前後したら数えない

            let meters = Geo.distanceMeters(lat1: from.latitude, lon1: from.longitude,
                                            lat2: to.latitude, lon2: to.longitude)
            let isEffect = visit.visitKind == .effectPassing || visit.visitKind == .effectArrival
            let rested = restSeconds(from: previousTime, to: visit.arrivedAt,
                                     rests: rests, now: now)
            let walked = max(0, visit.arrivedAt.timeIntervalSince(previousTime) - rested)

            result.append(Leg(id: visit.id,
                              turnNo: turn.turnNo,
                              fromOrder: from.orderNo,
                              toOrder: to.orderNo,
                              fromName: from.name,
                              toName: to.name,
                              departedAt: previousTime,
                              arrivedAt: visit.arrivedAt,
                              restSeconds: rested,
                              pace: Pace(meters: meters, seconds: walked),
                              isEffectMove: isEffect))
            previousStation = to
            previousTime = visit.arrivedAt
        }
        return result
    }

    // MARK: - 休憩

    /// `[start, end]` と重なっていた休憩の合計（秒）。
    ///
    /// 区間の途中から休み始めて途中で歩き出したときは、**重なったぶんだけ**を返す。
    /// 休憩が複数あれば足し合わせる（休憩は同時に1つしか始められないので、
    /// 重なり同士が二重に数えられることはない）。
    ///
    /// - Parameter now: 終わっていない休憩の終わりとみなす時刻
    static func restSeconds(from start: Date, to end: Date,
                            rests: [RestPeriod], now: Date = Date()) -> TimeInterval {
        guard end > start else { return 0 }
        return rests.reduce(0) { total, rest in
            let overlapStart = max(start, rest.startedAt)
            let overlapEnd = min(end, rest.endedAt ?? now)
            return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
    }

    // MARK: - ターンの内訳

    /// - Parameter now: 進行中のターンを「いままで」で測るための基準時刻
    ///
    /// > ⚠️ **既知の問題（効果で移動するターン）。** お題の時間は `[着地, 最初の効果訪問]`、
    /// > 効果の区間も `[着地, 効果訪問]` で、**同じ時間帯を二重に数えている**。
    /// > そのため効果のあるターンでは「移動＋お題」が合計を超えることがあり、
    /// > その窓に休憩が重なると歩きとお題の両方から引かれて二重に控除される。
    /// > 直すには**「お題を終えた時刻」を記録する**必要がある（あとから判定できるようになり、
    /// > お題の終わりは着地の何時間も後になりうるので、いまの窓の共有では表せない）。
    /// > 「お題に費やした時間」の定義を決め直す話なので、別件として残す
    static func breakdown(of turn: Turn, now: Date = Date()) -> TurnBreakdown {
        let ordered = turn.visits.sorted { $0.arrivedAt < $1.arrivedAt }
        let end = turn.completedAt ?? now

        // 着地してから、効果で歩き出すまで（効果が無ければターン終了まで）がミッションの時間
        let landedAt = turn.arrivedAt
        let effectStartedAt = ordered.first {
            $0.visitKind == .effectPassing || $0.visitKind == .effectArrival
        }?.arrivedAt

        // **お題の時間からも休憩を引く。** 着いてお題に取りかかる前に一息つくのは
        // 現地でごく普通に起きる。引かないと「移動＋お題＋休憩」が合計を超え、
        // `Total.otherSeconds` の `max(0,...)` に潰されて静かに辻褄が合わなくなる
        let missionSeconds: TimeInterval = {
            guard let landedAt else { return 0 }
            let missionEnd = effectStartedAt ?? end
            let rested = restSeconds(from: landedAt, to: missionEnd,
                                     rests: turn.missionSet?.restPeriods ?? [], now: now)
            return max(0, missionEnd.timeIntervalSince(landedAt) - rested)
        }()

        let legs = legs(in: turn, now: now)
        let walkingSeconds = legs.reduce(0) { $0 + $1.seconds }
        let meters = legs.reduce(0) { $0 + $1.pace.meters }

        return TurnBreakdown(turnNo: turn.turnNo,
                             walkingSeconds: walkingSeconds,
                             missionSeconds: missionSeconds,
                             totalSeconds: max(0, end.timeIntervalSince(turn.rolledAt)),
                             meters: meters,
                             isCompleted: turn.completedAt != nil)
    }

    // MARK: - 全体

    struct Total {
        let walkingSeconds: TimeInterval
        let missionSeconds: TimeInterval
        /// 休んでいた時間。**歩きの時間からは既に引いてある**（`Leg.seconds`）
        let restSeconds: TimeInterval
        /// 最初に振ってから最後の記録まで。**待ち時間や休憩も含む**
        let elapsedSeconds: TimeInterval
        let meters: Double

        var pace: Pace { Pace(meters: meters, seconds: walkingSeconds) }

        /// 歩きにも お題にも 休憩にも当たらない時間（待ち合わせ・次を振るまでの間）
        var otherSeconds: TimeInterval {
            max(0, elapsedSeconds - walkingSeconds - missionSeconds - restSeconds)
        }
    }

    static func total(in room: MissionSet, now: Date = Date()) -> Total {
        let breakdowns = room.turns.map { breakdown(of: $0, now: now) }
        let starts = room.turns.map(\.rolledAt)
        let ends = room.turns.map { $0.completedAt ?? now }
            + room.visits.map(\.arrivedAt)

        let first = starts.min()
        let last = ends.max()

        let elapsed: TimeInterval = {
            guard let first, let last, last > first else { return 0 }
            return last.timeIntervalSince(first)
        }()

        // 旅のあいだに休んだぶん。**歩いている間の休憩だけでなく、
        // お題の最中や次を振るまでの休憩も数える**（内訳の1枠として見せるため）
        let rested: TimeInterval = {
            guard let first, let last else { return 0 }
            return restSeconds(from: first, to: last, rests: room.restPeriods, now: now)
        }()

        return Total(walkingSeconds: breakdowns.reduce(0) { $0 + $1.walkingSeconds },
                     missionSeconds: breakdowns.reduce(0) { $0 + $1.missionSeconds },
                     restSeconds: rested,
                     elapsedSeconds: elapsed,
                     meters: breakdowns.reduce(0) { $0 + $1.meters })
    }
}
