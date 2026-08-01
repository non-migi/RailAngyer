import Foundation
import RailAngyerCore

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
        let done: Bool
        let effect: EffectType
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

    var achievedMissionCount: Int { missionResults.filter(\.done).count }

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
                return MissionResult(id: turn.id,
                                     turnNo: turn.turnNo,
                                     stationName: turn.landingStation?.name ?? "-",
                                     content: mission?.content ?? "",
                                     authorName: mission?.member?.displayName ?? "-",
                                     done: turn.missionDone,
                                     effect: turn.appliedEffectType ?? .none)
            }

        let landedOrders = Set(visits.filter { $0.visitKind == .landing }
                                     .compactMap { $0.station?.orderNo })
        let orders = engine?.orderedRange ?? Array(visitedOrders).sorted()
        let allStations = room.course?.stations ?? []

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
