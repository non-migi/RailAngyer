import SwiftUI
import RailAngyerCore

/// SC-04 盤面。アプリの主画面。
struct BoardView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Binding var showingSettings: Bool
    /// ターンの画面をしまって盤面を見ているとき、戻るための操作
    var onResumeTurn: (() -> Void)?
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
        }
    }

    // MARK: - 上部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let engine = store.engine {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("踏破").font(.caption).foregroundStyle(.secondary)
                    Text("\(store.visitedCount) / \(engine.distinctStationCount)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.line)
                    Spacer()
                    Text("サイコロ 1〜\(engine.diceMax)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(store.visitedCount), total: Double(engine.distinctStationCount))
                    .tint(Theme.line)
                Text("現在地　\(store.stationName(store.currentOrder))")
                    .font(.subheadline)
                timingRow
                quickActions
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background {
            LinearGradient(
                colors: [Theme.paper, Theme.line.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
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
                        .foregroundStyle(PacePalette.color(
                            minutesPerKilometer: timing.pace.minutesPerKilometer))
                }
            }
            .font(.caption.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.secondary)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quickAction("予定", systemImage: "calendar") {
                showingSchedules = true
            }
            quickAction("記録", systemImage: "book.closed", accessibilityLabel: "ふりかえり") {
                showingSummary = true
            }
            quickAction("お題", systemImage: "square.and.pencil") {
                showingMissions = true
            }
            quickAction("設定", systemImage: "gearshape") {
                showingSettings = true
            }
        }
        .padding(.top, 5)
    }

    private func quickAction(
        _ title: String,
        systemImage: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .accessibilityLabel(accessibilityLabel ?? title)
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

    private var isTurnInProgress: Bool {
        store.phase.isInTurn || store.showingAnnouncement
    }

    /// 戻る口の文言。いま何の途中なのかが分かるようにする
    private var resumeTitle: String {
        switch store.phase {
        case .walking(let next, _):        "\(store.stationName(next)) へ歩く"
        case .effectWalking(let next, _):  "\(store.stationName(next)) へ歩く"
        case .landed:                      "お題を引く"
        case .mission:                     "お題を続ける"
        case .arrivedPassing:              "次の駅へ"
        default:                           "旅を続ける"
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if case .cleared = store.phase {
                Text("ゴールに到達しました")
                    .font(.headline).foregroundStyle(Theme.line)
                Button("ふりかえりを見る") { showingSummary = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.line)
                .frame(maxWidth: .infinity, minHeight: 48)
                Button("記録を保存して新しい旅へ") { store.resetProgress() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else if isTurnInProgress, let onResumeTurn {
                // **進行中は「振る」を出さない。** 押しても何も起きない飾りになるうえ、
                // 戻る口をその上に重ねると、どちらを押すのか分からなくなる
                Button(action: onResumeTurn) {
                    Label(resumeTitle, systemImage: "figure.walk.motion")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.line)
                .accessibilityIdentifier("resumeTurn")
            } else {
                Button {
                    store.roll()
                } label: {
                    Text("サイコロを振る")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.line)
                .disabled(isTurnInProgress)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
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
