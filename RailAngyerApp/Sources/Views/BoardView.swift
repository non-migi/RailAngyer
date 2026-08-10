import SwiftUI
import RailAngyerCore

/// SC-04 盤面。アプリの主画面。
struct BoardView: View {
    @Bindable var store: GameSessionStore
    @Binding var showingSettings: Bool
    @State private var selectedStation: StationSelection?
    @State private var showingSummary = false
    @State private var showingCamera = false
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
        .sheet(isPresented: $showingSummary) {
            JourneySummaryView(store: store)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { store.attachPhoto($0) }
                .ignoresSafeArea()
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

    /// 盤面は歩いている最中の画面なので、**いま遊ぶのに要るものだけ**を置く。
    /// 予定とお題はホームから開く（同じ行き先のボタンを2か所に置かない）
    private var quickActions: some View {
        HStack(spacing: 8) {
            quickAction("ふりかえり", systemImage: "book.closed") {
                showingSummary = true
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
        .accessibilityLabel(title)
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
                .controlSize(.large)
                .tint(Theme.line)
                .frame(maxWidth: .infinity, minHeight: 48)
                Button("記録を保存して新しい旅へ") { store.resetProgress() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                stationAction
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
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// いま立っている駅でできること。
    ///
    /// **スタート駅も1駅目として扱う。** 旅の始めだけ「到着した」瞬間が無いと、
    /// そこだけ写真を残せない駅になってしまう（R-17 / R-19）。
    /// 一度記録したあとは、次を振るまでのあいだ何枚でも撮れる
    @ViewBuilder
    private var stationAction: some View {
        if !store.hasStartedJourney {
            Text("スタートの \(store.stationName(store.currentOrder)) も1駅目です")
                .font(.caption).foregroundStyle(.secondary)
            secondary("\(store.stationName(store.currentOrder)) に到着した",
                      systemImage: "mappin.and.ellipse") {
                store.startJourney()
            }
        } else if store.currentVisit != nil {
            secondary(CameraPicker.isCameraAvailable ? "この駅で写真を撮る" : "この駅の写真を選ぶ",
                      systemImage: "camera") {
                showingCamera = true
            }
        }
    }

    private func secondary(_ title: String, systemImage: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
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
