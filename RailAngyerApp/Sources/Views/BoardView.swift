import SwiftUI
import RailAngyerCore

/// SC-04 盤面。アプリの主画面。
struct BoardView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Binding var showingSettings: Bool
    @State private var selectedStation: StationSelection?
    @State private var showingMissions = false
    @State private var showingSummary = false
    @State private var showingSchedules = false
    /// 既定は地図。全体の進捗と、マスタ座標のズレを一目で見るため
    @AppStorage("boardShowsMap") private var showsMap = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showsMap {
                BoardMapView(store: store, selectedStation: $selectedStation)
            } else {
                route
            }
            footer
        }
        .sheet(item: $selectedStation) { selection in
            StationDetailView(store: store, order: selection.id)
        }
        .sheet(isPresented: $showingMissions) {
            MissionEditorView(store: store, sync: sync)
        }
        .sheet(isPresented: $showingSummary) {
            JourneySummaryView(store: store)
        }
        .sheet(isPresented: $showingSchedules) {
            ScheduleListView(store: store, sync: sync)
        }
        .navigationTitle(store.room?.name ?? "レイルアンギャー")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsMap.toggle()
                } label: {
                    Image(systemName: showsMap ? "list.bullet" : "map")
                }
                .accessibilityLabel(showsMap ? "一覧で見る" : "地図で見る")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSchedules = true } label: { Image(systemName: "calendar") }
                    .accessibilityLabel("予定")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSummary = true } label: { Image(systemName: "book.closed") }
                    .accessibilityLabel("ふりかえり")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingMissions = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("お題を書く")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
    }

    // MARK: - 上部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let engine = store.engine {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("踏破").font(.caption).foregroundStyle(.secondary)
                    Text("\(store.visitedCount) / \(engine.stationCount)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.line)
                    Spacer()
                    Text("サイコロ 1〜\(engine.diceMax)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(store.visitedCount), total: Double(engine.stationCount))
                    .tint(Theme.line)
                Text("現在地　\(store.stationName(store.currentOrder))")
                    .font(.subheadline)
                timingRow
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    /// かかった時間とペース。歩いている最中にいちばん知りたい数字なので、盤面に出す
    @ViewBuilder
    private var timingRow: some View {
        let timing = store.timing
        if timing.elapsedSeconds > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Label("合計 \(DurationText.text(timing.elapsedSeconds))", systemImage: "clock")
                    Label("移動 \(DurationText.text(timing.walkingSeconds))", systemImage: "figure.walk")
                    if timing.missionSeconds > 0 {
                        Label("ミッション \(DurationText.text(timing.missionSeconds))",
                              systemImage: "checkmark.seal")
                    }
                    Spacer(minLength: 0)
                }
                if let pace = timing.pace.text {
                    Label("平均 \(pace)", systemImage: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(paceColor(timing.pace.category))
                }
            }
            .font(.caption.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.secondary)
        }
    }

    private func paceColor(_ category: PaceCategory?) -> Color {
        switch category {
        case .fast:   return .blue
        case .normal: return Theme.line
        case .slow:   return .red
        case nil:     return .secondary
        }
    }

    // MARK: - 路線図

    private var route: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.stationsInOrder) { station in
                    Button {
                        selectedStation = StationSelection(id: station.orderNo)
                    } label: {
                        StationRow(station: station,
                                   isCurrent: station.orderNo == store.currentOrder,
                                   isVisited: store.visitedOrders.contains(station.orderNo),
                                   isLanded: store.landedOrders.contains(station.orderNo),
                                   isGoal: station.orderNo == store.engine?.goalOrder,
                                   isStart: station.orderNo == store.engine?.startOrder,
                                   missionCount: store.missionCandidates(at: station.orderNo).count,
                                   photoCount: store.photoFileNames(at: station.orderNo).count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 下部

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if case .cleared = store.phase {
                Text("ゴールに到達しました")
                    .font(.headline).foregroundStyle(Theme.line)
                Button("ふりかえりを見る") { showingSummary = true }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                Button("記録をリセットしてもう一度") { store.resetProgress() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                Button {
                    store.roll()
                } label: {
                    Text("サイコロを振る")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.line)
            }
        }
        .padding()
        .background(.bar)
    }
}

/// 路線図の1駅ぶん。地下鉄の路線図の見立てで、線とドットで表す。
private struct StationRow: View {
    let station: Station
    let isCurrent: Bool
    let isVisited: Bool
    let isLanded: Bool
    let isGoal: Bool
    let isStart: Bool
    let missionCount: Int
    let photoCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(isVisited ? Theme.line : Theme.line.opacity(0.25))
                    .frame(width: 4)
                Circle()
                    .fill(Color(.systemBackground))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: isCurrent ? 5 : 3))
                    .frame(width: dotSize, height: dotSize)
                    .opacity(isVisited || isCurrent ? 1 : 0.45)
            }
            .frame(width: 28)

            Text(String(format: "%02d", station.orderNo))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(station.name)
                .font(isCurrent ? .body.weight(.semibold) : .body)

            if isLanded {
                Image(systemName: "flag.checkered")
                    .font(.caption2).foregroundStyle(Theme.mission)
            }
            Spacer()
            if photoCount > 0 {
                Label("\(photoCount)", systemImage: "photo")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if missionCount > 0 {
                Text("\(missionCount)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.mission.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.mission)
            }
            if isStart { badge("スタート") }
            if isGoal { badge("ゴール") }
        }
        .padding(.horizontal)
        .frame(height: 44)
    }

    private var dotSize: CGFloat { isCurrent ? 20 : 12 }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.line.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.line)
    }
}

/// `sheet(item:)` に渡すための包み。
/// `Int` に直接 `Identifiable` を後付けすると、他のライブラリと衝突しうるため避ける
struct StationSelection: Identifiable, Equatable {
    let id: Int
}
