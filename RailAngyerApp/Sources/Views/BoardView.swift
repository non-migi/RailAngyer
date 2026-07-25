import SwiftUI
import RailAngyerCore

/// SC-04 盤面。アプリの主画面。
struct BoardView: View {
    @Bindable var store: GameSessionStore
    @Binding var showingSettings: Bool
    @State private var selectedStation: Int?
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
        .sheet(item: $selectedStation) { order in
            StationDetailView(store: store, order: order)
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
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - 路線図

    private var route: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.stationsInOrder) { station in
                    Button {
                        selectedStation = station.orderNo
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

/// `sheet(item:)` に使うため
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

/// ロゴから取った配色（assets/logo.png）
enum Theme {
    static let line = Color(red: 0.16, green: 0.48, blue: 0.25)     // 濃い緑
    static let ink = Color(red: 0.09, green: 0.15, blue: 0.25)      // 濃紺
    static let mission = Color(red: 0.66, green: 0.33, blue: 0.11)  // 焦茶
}
