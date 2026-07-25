import SwiftUI
import SwiftData
import RailAngyerCore

/// フェーズ1の足場となる画面。
///
/// 現時点では「マスタの投入 → 盤面の描画 → サイコロを振って道のりを出す」までを確認するためのもの。
/// 本来の盤面（SC-04）は 08_画面仕様.html に従って作り込む。
struct RootView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \Station.orderNo) private var stations: [Station]
    @Query private var rooms: [MissionSet]

    @State private var seedError: String?
    @State private var plan: GameEngine.TurnPlan?

    private var room: MissionSet? { rooms.first }
    private var engine: GameEngine? { room?.engine }

    /// 現在位置（10_アプリ設計.md §5.2）。
    /// 最後に完了したターンの終了位置。無ければスタート駅。
    private var currentOrder: Int {
        guard let room else { return 1 }
        let completed = room.turns
            .filter { $0.completedAt != nil }
            .max { $0.turnNo < $1.turnNo }
        return completed?.endStation?.orderNo ?? room.startStation?.orderNo ?? 1
    }

    var body: some View {
        NavigationStack {
            Group {
                if let seedError {
                    ContentUnavailableView("マスタを読み込めません", systemImage: "exclamationmark.triangle",
                                           description: Text(seedError))
                } else if let engine {
                    board(engine)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(room?.name ?? "レイルアンギャー")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { seed() }
    }

    // MARK: - 盤面

    @ViewBuilder
    private func board(_ engine: GameEngine) -> some View {
        VStack(spacing: 0) {
            header(engine)
            Divider()
            List {
                ForEach(stationsInRange(engine)) { station in
                    row(station, engine: engine)
                }
            }
            .listStyle(.plain)
            footer(engine)
        }
    }

    private func header(_ engine: GameEngine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(engine.stationCount) 駅の区間 ／ サイコロは 1〜\(engine.diceMax)")
                .font(.footnote).foregroundStyle(.secondary)
            if let plan {
                Text("出目 \(plan.dice) → \(name(plan.landing) ?? "?") まで")
                    .font(.headline)
                Text(plan.passing.isEmpty
                     ? "通り道はありません"
                     : "途中: " + plan.passing.compactMap(name).joined(separator: " → "))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("現在地: \(name(currentOrder) ?? "-")").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func row(_ station: Station, engine: GameEngine) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(station.orderNo == currentOrder ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: station.orderNo == currentOrder ? 14 : 9,
                       height: station.orderNo == currentOrder ? 14 : 9)
            Text(String(format: "%02d", station.orderNo))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(station.name)
                .fontWeight(station.orderNo == currentOrder ? .semibold : .regular)
            Spacer()
            if station.orderNo == engine.goalOrder {
                Image(systemName: "flag.fill").foregroundStyle(.green)
            }
        }
    }

    private func footer(_ engine: GameEngine) -> some View {
        Button {
            plan = engine.plan(from: currentOrder, dice: engine.roll())
        } label: {
            Text("サイコロを振る")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .disabled(engine.isCleared(currentOrder))
    }

    // MARK: - 補助

    private func stationsInRange(_ engine: GameEngine) -> [Station] {
        let ordered = engine.orderedRange
        return ordered.compactMap { order in stations.first { $0.orderNo == order } }
    }

    private func name(_ order: Int) -> String? {
        stations.first { $0.orderNo == order }?.name
    }

    private func seed() {
        do {
            let course = try MasterSeeder.seedIfNeeded(context)
            try MasterSeeder.seedLocalRoomIfNeeded(context, course: course)
        } catch {
            seedError = String(describing: error)
        }
    }
}
