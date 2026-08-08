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
    @State private var showingPhotos = false

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
            .sheet(isPresented: $showingPhotos) {
                PhotoGalleryView(items: store.photoItems)
            }
        }
    }

    private func content(_ summary: JourneySummary) -> some View {
        List {
            Section {
                SummaryCard(summary: summary)
                    .listRowInsets(EdgeInsets())
            }

            // **歩いた形をここでも見せる。** 数字だけでは、その日の道のりを思い出せない
            if store.stationsInOrder.count >= 2 {
                Section {
                    JourneyTrackMapView(store: store)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 10, leading: 16,
                                                  bottom: 12, trailing: 16))
                } header: {
                    Text("歩いた道のり")
                } footer: {
                    Text(summary.isDistanceMeasured
                         ? "実際に歩いた跡から出した距離です。50mごとに速さで色を分けています。"
                         : "跡が残っていないため、通った駅を結んだ距離です。")
                }
            }

            if !summary.missionResults.isEmpty {
                Section("こなしたお題") {
                    ForEach(summary.missionResults) { result in
                        missionRow(result)
                    }
                }
            }

            if !store.photoItems.isEmpty {
                Section {
                    Button {
                        showingPhotos = true
                    } label: {
                        Label("撮った写真をまとめて見る　\(store.photoItems.count)枚",
                              systemImage: "photo.on.rectangle.angled")
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

            // **やったことの証拠。** お題と写真が離れていると、
            // どの写真がどのお題のものか後から分からなくなる
            if !result.photoFileNames.isEmpty {
                PhotoStrip(fileNames: result.photoFileNames)
                    .padding(.top, 2)
            }
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
                // **歩いた距離は、その日いちばん語られる数字。**
                // 跡が残っていれば実測、無ければ駅を結んだ長さ
                stat(summary.isDistanceMeasured ? "歩いた距離" : "距離（目安）",
                     summary.distanceText)
                stat("ターン", "\(summary.turnCount)")
                stat("写真", "\(summary.photoCount) 枚")
            }

            ProgressView(value: summary.visitedRate)
                .tint(Theme.line)

            if summary.timing.elapsedSeconds > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    Text("時間の内訳")
                        .font(.caption.weight(.semibold))

                    HStack(spacing: 0) {
                        timeStat("合計", summary.timing.elapsedSeconds)
                        timeStat("移動", summary.timing.walkingSeconds)
                        timeStat("ミッション", summary.timing.missionSeconds)
                        timeStat("その他", summary.timing.otherSeconds)
                    }

                    if let pace = summary.timing.pace.text {
                        Label("平均 \(pace)", systemImage: "gauge.with.dots.needle.50percent")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PacePalette.color(
                                minutesPerKilometer: summary.timing.pace.minutesPerKilometer))
                    }
                }
            }

            HStack(spacing: 12) {
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

    // 見出しは訳す。値は数字なのでそのまま
    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeStat(_ title: LocalizedStringKey, _ seconds: TimeInterval) -> some View {
        VStack(spacing: 2) {
            Text(DurationText.text(seconds))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
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

/// 現在の旅と保存済みの旅をまとめて見る一覧。
struct JourneyHistoryView: View {
    @Bindable var store: GameSessionStore
    @State private var showingCurrent = false

    var body: some View {
        List {
            if !(store.room?.turns.isEmpty ?? true) {
                Section("進行中") {
                    Button {
                        showingCurrent = true
                    } label: {
                        Label("いまの旅の記録", systemImage: "figure.walk.motion")
                            .font(.headline)
                    }
                }
            }

            Section("これまでの旅") {
                if store.archives.isEmpty {
                    ContentUnavailableView("保存済みの記録はありません",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("旅を終えて新しい旅を始めると、ここに追加されます"))
                }
                ForEach(store.archives) { archive in
                    NavigationLink {
                        JourneyArchiveDetailView(archive: archive)
                    } label: {
                        archiveRow(archive)
                    }
                }
                .onDelete { offsets in
                    for archive in offsets.map({ store.archives[$0] }) {
                        store.deleteArchive(archive)
                    }
                }
            }
        }
        .navigationTitle("記録")
        .sheet(isPresented: $showingCurrent) { JourneySummaryView(store: store) }
    }

    private func archiveRow(_ archive: JourneyArchive) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(archive.courseName.nilIfEmpty ?? archive.roomName).font(.headline)
                Spacer()
                if archive.isCleared {
                    Label("完走", systemImage: "flag.checkered")
                        .font(.caption).foregroundStyle(Theme.line)
                }
            }
            Text(archive.endedAt.formatted(
                .dateTime.locale(Locale(identifier: "ja_JP")).year().month().day().weekday()))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Label(DurationText.text(archive.elapsedSeconds), systemImage: "clock")
                Label("\(archive.visitedCount)駅", systemImage: "mappin.and.ellipse")
                if archive.photoCount > 0 {
                    Label("\(archive.photoCount)", systemImage: "photo")
                }
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct JourneyArchiveDetailView: View {
    let archive: JourneyArchive

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(archive.courseName.nilIfEmpty ?? archive.roomName)
                        .font(.largeTitle.bold())
                    Text(archive.endedAt.formatted(
                        .dateTime.locale(Locale(identifier: "ja_JP"))
                            .year().month().day().weekday().hour().minute()))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    archiveStat("時間", DurationText.text(archive.elapsedSeconds))
                    archiveStat("駅", "\(archive.visitedCount) / \(archive.stationCount)")
                    archiveStat("ターン", "\(archive.turnCount)")
                }

                if !archive.routeSummary.isEmpty {
                    Label(archive.routeSummary, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.subheadline)
                }

                if !archive.photoFileNames.isEmpty {
                    Text("写真").font(.headline)
                    LazyVGrid(columns: [.init(.adaptive(minimum: 96))], spacing: 8) {
                        ForEach(archive.photoFileNames, id: \.self) { name in
                            if let image = PhotoStore.load(name) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("旅の記録")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func archiveStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title3.bold()).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
