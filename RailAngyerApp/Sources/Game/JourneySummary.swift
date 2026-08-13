import Foundation
import RailAngyerCore

/// お題の結末。
///
/// **「まだ決めていない」を「できなかった」と混ぜない。**
/// 引いたお題は、その場で決めずに「あとで」にできる（歩きながら続けられるお題のため）。
/// 判定前かどうかは**効果が決まっているか**で分かる。
/// `finishMission` は必ず効果まで決めるので、済んだお題と取り違えられない
enum MissionOutcome: Equatable {
    /// 引いたまま、まだ達成を決めていない
    case inProgress
    case done
    case missed

    init(_ turn: Turn) {
        guard turn.appliedEffectType != nil else { self = .inProgress; return }
        self = turn.missionDone ? .done : .missed
    }

    var label: String {
        switch self {
        case .inProgress: appLocalized("進行中")
        case .done:       appLocalized("達成")
        case .missed:     appLocalized("未達成")
        }
    }

    var symbolName: String {
        switch self {
        case .inProgress: "hourglass"
        case .done:       "checkmark.circle.fill"
        case .missed:     "circle"
        }
    }
}

/// ふりかえりの集計（SC-17 / フェーズ3）。
///
/// **画面から切り離した値にしておく。** 見た目より先に「何を数えるか」が決まっていないと、
/// 踏破率のように数え方で食い違うものがぶれる（DV-06）。
struct JourneySummary {

    struct MissionResult: Identifiable {
        let id: UUID
        let turnNo: Int
        let stationName: String
        let content: String
        let authorName: String
        /// 達成・未達成・進行中（判定前）
        let outcome: MissionOutcome
        let effect: EffectType
        /// その駅で撮った写真。**やったことの証拠**なので、お題と並べて出す
        let photoFileNames: [String]
    }

    struct StationRecord: Identifiable {
        var id: Int { orderNo }
        let orderNo: Int
        let name: String
        /// 何度訪れたか（再訪を含む）
        let visitCount: Int
        let landed: Bool
        let photoFileNames: [String]
    }

    let roomName: String
    /// 区間の駅数
    let stationCount: Int
    /// 一度でも訪れた駅の数（再訪は重複して数えない。DV-06）
    let visitedCount: Int
    let landedCount: Int
    let turnCount: Int
    let photoCount: Int
    /// 合計・移動・ミッション・その他と平均ペース。
    /// 画面と共有画像は必ずこの同じ集計値を使う。
    let timing: WalkTiming.Total
    let isCleared: Bool
    let missionResults: [MissionResult]
    let stations: [StationRecord]
    /// 実際に歩いた跡（古い順）。地図と距離に使う
    let track: [TrackSegments.Fix]
    /// 駅と駅を直線でつないだときの道のり。跡が無いときの代わり
    let straightMeters: Double

    var visitedRate: Double {
        stationCount > 0 ? Double(visitedCount) / Double(stationCount) : 0
    }

    /// 最初に振ってから最後の記録まで。進行中なら現在まで。
    var elapsed: TimeInterval? {
        timing.elapsedSeconds > 0 ? timing.elapsedSeconds : nil
    }

    var elapsedText: String? {
        guard let elapsed else { return nil }
        return DurationText.text(elapsed)
    }

    /// 達成できたお題の数。**進行中（判定前）は数えない**
    var achievedMissionCount: Int { missionResults.filter { $0.outcome == .done }.count }

    /// まだ達成を決めていないお題の数
    var inProgressMissionCount: Int { missionResults.filter { $0.outcome == .inProgress }.count }

    /// 実際に歩いた距離（m）。**跡が残っていればその長さ、無ければ駅間の直線の合計**
    var walkedMeters: Double {
        let tracked = TrackSegments.totalMeters(track)
        return tracked >= 100 ? tracked : straightMeters
    }

    /// 跡から出した距離か（＝実測か目安か）
    var isDistanceMeasured: Bool { TrackSegments.totalMeters(track) >= 100 }

    var distanceText: String {
        let meters = walkedMeters
        guard meters >= 1 else { return "—" }
        return meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }

    // MARK: - 組み立て

    /// ルームの記録から集計する。
    /// 途中でも呼べる（クリアしていなくても「いまの記録」を見せられる）
    init(room: MissionSet, engine: GameEngine?, now: Date = Date()) {
        roomName = room.name
        // 一周では、戻ってくる1駅を二重に数えない
        stationCount = engine?.distinctStationCount ?? (room.course?.stations.count ?? 0)

        let visits = room.visits
        let visitedOrders = Set(visits.compactMap { $0.station?.orderNo })
        visitedCount = visitedOrders.count
        landedCount = Set(visits.filter { $0.visitKind == .landing }
                                .compactMap { $0.station?.orderNo }).count

        let completedTurns = room.turns.filter { $0.completedAt != nil }
        turnCount = completedTurns.count
        photoCount = visits.reduce(0) { $0 + $1.photos.count }
        timing = WalkTiming.total(in: room, now: now)

        let current = completedTurns
            .max { $0.rolledAt < $1.rolledAt }?
            .endStation?.orderNo ?? room.startStation?.orderNo
        isCleared = current != nil && current == room.goalStation?.orderNo

        missionResults = room.turns
            .filter { $0.selectedMission != nil }
            .sorted { $0.turnNo < $1.turnNo }
            .map { turn in
                let mission = turn.selectedMission
                // 着地した訪問に紐づく写真。**そのお題をやったときに撮ったもの**
                let photos = room.visits
                    .filter { $0.turn?.id == turn.id && $0.visitKind == .landing }
                    .flatMap(\.photos)
                    .sorted { $0.takenAt < $1.takenAt }
                    .map(\.localFileName)

                return MissionResult(id: turn.id,
                                     turnNo: turn.turnNo,
                                     stationName: turn.landingStation?.name ?? "-",
                                     content: mission?.content ?? "",
                                     authorName: mission?.member?.displayName ?? "-",
                                     outcome: MissionOutcome(turn),
                                     effect: turn.appliedEffectType ?? .none,
                                     photoFileNames: photos)
            }

        let landedOrders = Set(visits.filter { $0.visitKind == .landing }
                                     .compactMap { $0.station?.orderNo })
        let orders = engine?.orderedRange ?? Array(visitedOrders).sorted()
        let allStations = room.course?.stations ?? []

        track = room.trackPoints
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { TrackSegments.Fix(latitude: $0.latitude, longitude: $0.longitude,
                                     time: $0.recordedAt) }

        // 跡が無いときのために、通った駅を順につないだ長さも出しておく
        let visitedInOrder = visits
            .sorted { $0.arrivedAt < $1.arrivedAt }
            .compactMap { $0.station }
        straightMeters = WalkEstimator.estimate(points: visitedInOrder).straightMeters

        stations = orders.compactMap { order in
            guard let station = allStations.first(where: { $0.orderNo == order }) else { return nil }
            let mine = visits.filter { $0.station?.orderNo == order }
            return StationRecord(orderNo: order,
                                 name: station.name,
                                 visitCount: mine.count,
                                 landed: landedOrders.contains(order),
                                 photoFileNames: mine.flatMap(\.photos)
                                     .sorted { $0.takenAt < $1.takenAt }
                                     .map(\.localFileName))
        }
    }
}
