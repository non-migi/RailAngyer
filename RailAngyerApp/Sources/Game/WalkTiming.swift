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
        let pace: Pace
        /// 効果による移動か（出目の移動と区別して見せる）
        let isEffectMove: Bool

        var seconds: TimeInterval { arrivedAt.timeIntervalSince(departedAt) }
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
    static func legs(in room: MissionSet) -> [Leg] {
        room.turns
            .sorted { $0.rolledAt < $1.rolledAt }
            .flatMap { legs(in: $0) }
    }

    /// 1ターンぶんの区間記録。
    ///
    /// 出発時刻は**ターンを振った時刻**から始め、以降は前の駅に着いた時刻を使う。
    /// 効果による移動は、ミッションを終えた時点（＝最初の効果訪問の直前）から測る。
    static func legs(in turn: Turn) -> [Leg] {
        let ordered = turn.visits.sorted { $0.arrivedAt < $1.arrivedAt }
        guard !ordered.isEmpty else { return [] }

        var result: [Leg] = []
        var previousStation = turn.fromStation
        var previousTime = turn.rolledAt

        for visit in ordered {
            guard let to = visit.station else { continue }
            defer {
                previousStation = to
                previousTime = visit.arrivedAt
            }
            guard let from = previousStation, from.orderNo != to.orderNo else { continue }
            guard visit.arrivedAt > previousTime else { continue }   // 時刻が前後したら数えない

            let meters = Geo.distanceMeters(lat1: from.latitude, lon1: from.longitude,
                                            lat2: to.latitude, lon2: to.longitude)
            let isEffect = visit.visitKind == .effectPassing || visit.visitKind == .effectArrival

            result.append(Leg(id: visit.id,
                              turnNo: turn.turnNo,
                              fromOrder: from.orderNo,
                              toOrder: to.orderNo,
                              fromName: from.name,
                              toName: to.name,
                              departedAt: previousTime,
                              arrivedAt: visit.arrivedAt,
                              pace: Pace(meters: meters,
                                         seconds: visit.arrivedAt.timeIntervalSince(previousTime)),
                              isEffectMove: isEffect))
        }
        return result
    }

    // MARK: - ターンの内訳

    /// - Parameter now: 進行中のターンを「いままで」で測るための基準時刻
    static func breakdown(of turn: Turn, now: Date = Date()) -> TurnBreakdown {
        let ordered = turn.visits.sorted { $0.arrivedAt < $1.arrivedAt }
        let end = turn.completedAt ?? now

        // 着地してから、効果で歩き出すまで（効果が無ければターン終了まで）がミッションの時間
        let landedAt = turn.arrivedAt
        let effectStartedAt = ordered.first {
            $0.visitKind == .effectPassing || $0.visitKind == .effectArrival
        }?.arrivedAt

        let missionSeconds: TimeInterval = {
            guard let landedAt else { return 0 }
            let missionEnd = effectStartedAt ?? end
            return max(0, missionEnd.timeIntervalSince(landedAt))
        }()

        let legs = legs(in: turn)
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
        /// 最初に振ってから最後の記録まで。**待ち時間や休憩も含む**
        let elapsedSeconds: TimeInterval
        let meters: Double

        var pace: Pace { Pace(meters: meters, seconds: walkingSeconds) }

        /// 歩きにも お題にも当たらない時間（休憩・待ち合わせ・次を振るまでの間）
        var otherSeconds: TimeInterval {
            max(0, elapsedSeconds - walkingSeconds - missionSeconds)
        }
    }

    static func total(in room: MissionSet, now: Date = Date()) -> Total {
        let breakdowns = room.turns.map { breakdown(of: $0, now: now) }
        let starts = room.turns.map(\.rolledAt)
        let ends = room.turns.map { $0.completedAt ?? now }
            + room.visits.map(\.arrivedAt)

        let elapsed: TimeInterval = {
            guard let first = starts.min(), let last = ends.max(), last > first else { return 0 }
            return last.timeIntervalSince(first)
        }()

        return Total(walkingSeconds: breakdowns.reduce(0) { $0 + $1.walkingSeconds },
                     missionSeconds: breakdowns.reduce(0) { $0 + $1.missionSeconds },
                     elapsedSeconds: elapsed,
                     meters: breakdowns.reduce(0) { $0 + $1.meters })
    }
}
