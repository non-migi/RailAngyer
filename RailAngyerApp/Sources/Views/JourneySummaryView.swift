import SwiftUI
import RailAngyerCore

/// ふりかえり（SC-17）。クリア後だけでなく、途中でも「いまの記録」として見られる。
///
/// 共有画像はこの画面から書き出す。歩いた記録は身内で見せ合うものなので、
/// **写真そのものではなく、数字と駅の並びを1枚にまとめる**（写真は各自の端末にある）。
struct JourneySummaryView: View {

    @Bindable var store: GameSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var sharedImage: ShareableImage?

    private var summary: JourneySummary? {
        guard let room = store.room else { return nil }
        return JourneySummary(room: room, engine: store.engine)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    content(summary)
                } else {
                    ContentUnavailableView("記録がありません", systemImage: "figure.walk")
                }
            }
            .navigationTitle("ふりかえり")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let summary {
                        Button {
                            sharedImage = render(summary)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("共有画像を書き出す")
                    }
                }
            }
            .sheet(item: $sharedImage) { shared in
                ShareSheet(items: [shared.image])
            }
        }
    }

    private func content(_ summary: JourneySummary) -> some View {
        List {
            Section {
                SummaryCard(summary: summary)
                    .listRowInsets(EdgeInsets())
            }

            if !summary.missionResults.isEmpty {
                Section("こなしたお題") {
                    ForEach(summary.missionResults) { result in
                        missionRow(result)
                    }
                }
            }

            Section("歩いた駅") {
                ForEach(summary.stations) { station in
                    stationRow(station)
                }
            }
        }
    }

    private func missionRow(_ result: JourneySummary.MissionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(result.turnNo)ターン目・\(result.stationName)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: result.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(result.done ? Theme.line : .secondary)
            }
            Text(result.content)
            Text("\(result.authorName)のお題")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func stationRow(_ station: JourneySummary.StationRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(station.name)
                    .font(.subheadline.weight(station.landed ? .bold : .regular))
                    .foregroundStyle(station.visitCount > 0 ? .primary : .secondary)
                if station.landed {
                    Text("着地").font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Theme.line.opacity(0.15), in: Capsule())
                }
                if station.visitCount > 1 {
                    Text("\(station.visitCount)回").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !station.photoFileNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(station.photoFileNames, id: \.self) { name in
                            if let image = PhotoStore.load(name) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 共有画像を作る。`ImageRenderer` に同じカードを描かせるので、画面と食い違わない
    @MainActor
    private func render(_ summary: JourneySummary) -> ShareableImage? {
        let renderer = ImageRenderer(content:
            SummaryCard(summary: summary, forExport: true)
                .frame(width: 600)
                .background(Color(.systemBackground)))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return ShareableImage(image: image)
    }
}

/// 数字のまとめ。画面にも共有画像にも同じものを使う
private struct SummaryCard: View {
    let summary: JourneySummary
    var forExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.roomName).font(.headline)

            HStack(spacing: 0) {
                stat("踏破", "\(summary.visitedCount) / \(summary.stationCount)")
                stat("着地", "\(summary.landedCount) 駅")
                stat("ターン", "\(summary.turnCount)")
                stat("写真", "\(summary.photoCount) 枚")
            }

            ProgressView(value: summary.visitedRate)
                .tint(Theme.line)

            HStack(spacing: 12) {
                if let elapsed = summary.elapsedText {
                    Label(elapsed, systemImage: "clock")
                }
                if !summary.missionResults.isEmpty {
                    Label("お題 \(summary.achievedMissionCount) / \(summary.missionResults.count)",
                          systemImage: "checkmark.seal")
                }
                if summary.isCleared {
                    Label("ゴール", systemImage: "flag.checkered")
                        .foregroundStyle(Theme.line)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if forExport {
                // 書き出した画像だけを見た人に、何の記録か分かるようにする
                Text(summary.stations.filter { $0.visitCount > 0 }.map(\.name).joined(separator: " → "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("レイルアンギャー").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// `sheet(item:)` に渡すための包み
private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 共有シート。ShareLink は UIImage を直接扱えないため UIKit のものを包む
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
