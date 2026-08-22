import SwiftUI
import RailAngyerCore

/// ふりかえり（SC-17）。クリア後だけでなく、途中でも「いまの記録」として見られる。
///
/// 共有画像はこの画面から書き出す。歩いた記録は身内で見せ合うものなので、
/// **写真そのものではなく、数字と駅の並びを1枚にまとめる**（写真は各自の端末にある）。
struct JourneySummaryView: View {

    @Bindable var store: GameSessionStore
    /// 旅を畳む締めくくりとして開いたときだけ渡す。
    /// **やめた直後に空の盤面だけが残らないように**、ここで今日の記録を見せてから畳む
    var finish: JourneyFinish?
    /// 畳むと決めたときに呼ぶ。
    ///
    /// **畳むのはこの画面が閉じたあと。** 消したターンや訪問を掴んだまま描き直しが走ると
    /// SwiftData が落ちるので、呼ばれた側は `sheet(onDismiss:)` で片づける
    var onFinish: (() -> Void)?
    /// 「やめる」と決めた時刻。締めくくりで開いたときだけ渡す。
    ///
    /// > **旅が終わったのは歩くのをやめたときで、記録を眺め終えたときではない。**
    /// > 途中でやめるとそのターンは未完了のままなので、渡さないと
    /// > この画面を開いているあいだ合計時間もお題の時間も伸び続け、
    /// > 「どれだけ長く眺めてから確定したか」がその日の旅の長さになってしまう
    var stoppedAt: Date?
    @Environment(\.dismiss) private var dismiss
    /// 共有画像の描画に流す。`ImageRenderer` は画面の環境を継いでくれない
    @Environment(\.locale) private var locale
    @State private var sharedImage: ShareableImage?
    @State private var showingPhotos = false

    private var summary: JourneySummary? {
        guard let room = store.room else { return nil }
        // 締めくくりで開いたときは、やめると決めた時刻で数字を止める
        return JourneySummary(room: room, engine: store.engine, now: stoppedAt ?? Date())
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
            .navigationTitle(finish == nil ? "ふりかえり" : "今日のふりかえり")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 締めくくりで開いたときは、**閉じても旅は畳まれない**ことが分かる言葉にする
                    Button(finish == nil ? "閉じる" : "まだ続ける") { dismiss() }
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
                // **ここは「この旅」のふりかえり。** ホームの一覧と違い、
                // 過去の旅の写真まで混ぜると、その日の記録ではなくなる。
                // 消す操作だけはここからも効かせる（見ている場で直せるように）
                PhotoGalleryView(items: store.photoItems,
                                 title: appLocalized("この旅の写真"),
                                 onDelete: { item in
                                     if let id = item.photoId { store.deletePhoto(id: id) }
                                 },
                                 roomName: store.room?.name,
                                 onBlock: { store.block(memberId: $0) })
            }
        }
    }

    private func content(_ summary: JourneySummary) -> some View {
        List {
            Section {
                SummaryCard(summary: summary)
                    .listRowInsets(EdgeInsets())
            }

            // **やめる口は、今日の数字を見たすぐ下に置く。**
            // 押す前にその日の記録が目に入るので、畳んで空の盤面が残るだけ、ということにならない。
            // ここまで来ずに閉じれば旅は続く（畳むのは押したときだけ）
            if let finish {
                Section {
                    Button(finish.actionTitle, role: .destructive) {
                        // 畳むのは呼び出し側が、この画面が閉じたあとに行う
                        onFinish?()
                        dismiss()
                    }
                } header: {
                    Text(finish.question)
                } footer: {
                    Text(finish.note)
                }
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

    /// お題の結末の色。**進行中は「まだ途中」の色**にして、未達成の灰色と分ける
    static func color(of outcome: MissionOutcome) -> Color {
        switch outcome {
        case .done:       Theme.line
        case .inProgress: Theme.mission
        case .missed:     .secondary
        }
    }

    private func missionRow(_ result: JourneySummary.MissionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(result.turnNo)ターン目・\(result.stationName)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                // 判定前は「未達成」と区別して出す。決めていないだけで、失敗ではない
                Label(result.outcome.label, systemImage: result.outcome.symbolName)
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Self.color(of: result.outcome))
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

    /// 共有画像を作る。`ImageRenderer` に同じカードを描かせるので、画面と食い違わない。
    /// **言語は明示して渡す。** `ImageRenderer` は環境の `\.locale` を継がないため、
    /// 付けないと画像だけ端末の言語で書き出されてしまう
    @MainActor
    private func render(_ summary: JourneySummary) -> ShareableImage? {
        let renderer = ImageRenderer(content:
            SummaryCard(summary: summary, forExport: true)
                .frame(width: 600)
                .background(Color(.systemBackground))
                .environment(\.locale, locale))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return ShareableImage(image: image)
    }
}

/// 旅の締めくくり方。**同じ「畳む」でも、言葉は場面で変える。**
///
/// ゴールした人には「新しい旅へ」、日が暮れて途中でやめる人には「今日はここまで」。
/// どちらも `resetProgress()` を呼ぶが、探すときに思い浮かべる言葉が違う
enum JourneyFinish {
    /// 歩いている途中でやめる
    case quit
    /// ゴールに到達したあと畳む
    case cleared

    var question: LocalizedStringKey {
        switch self {
        case .quit:    "今日の記録を保存して旅を終えますか"
        case .cleared: "現在の旅を保存して、新しい旅を始めますか"
        }
    }

    var actionTitle: LocalizedStringKey {
        switch self {
        case .quit:    "今日はここまでにする"
        case .cleared: "記録を保存して新しい旅へ"
        }
    }

    var note: LocalizedStringKey {
        switch self {
        case .quit:
            "ゴールしていませんが、ここまでの記録は「記録」に残ります。続きは新しい旅として、また「旅をスタート」から始められます。"
        case .cleared:
            "訪問記録と写真は過去の旅として残ります。"
        }
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
                stat("着地", appLocalized("\(summary.landedCount) 駅"))
                // **歩いた距離は、その日いちばん語られる数字。**
                // 跡が残っていれば実測、無ければ駅を結んだ長さ
                stat(summary.isDistanceMeasured ? "歩いた距離" : "距離（目安）",
                     summary.distanceText)
                stat("ターン", "\(summary.turnCount)")
                stat("写真", appLocalized("\(summary.photoCount) 枚"))
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
                        // **休んでいない日に「休憩 0秒」は出さない。**
                        // 列が増えるほど1つあたりが細くなり、共有画像でも文字が詰まる
                        if summary.timing.restSeconds > 0 {
                            timeStat("休憩", summary.timing.restSeconds)
                        }
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
                // まだ決めていないお題があることを、ここでも気づけるようにする
                if summary.inProgressMissionCount > 0 {
                    Label("進行中 \(summary.inProgressMissionCount)", systemImage: "hourglass")
                        .foregroundStyle(Theme.mission)
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
/// 共有シート（`UIActivityViewController`）。
///
/// **`ShareLink` に `.simultaneousGesture` を足すと反応しなくなる。**
/// 押した瞬間に何かしたい（記録を取るなど）ときは、
/// `ShareLink` ではなくボタン＋これを使う。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 現在の旅と保存済みの旅をまとめて見る一覧。
struct JourneyHistoryView: View {
    @Bindable var store: GameSessionStore
    @Environment(\.locale) private var locale
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
        .navigationTitle("過去の旅")
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
                .dateTime.locale(locale).year().month().day().weekday()))
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
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(archive.courseName.nilIfEmpty ?? archive.roomName)
                        .font(.largeTitle.bold())
                    Text(archive.endedAt.formatted(
                        .dateTime.locale(locale)
                            .year().month().day().weekday().hour().minute()))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    archiveStat("時間", DurationText.text(archive.elapsedSeconds))
                    archiveStat("駅", "\(archive.visitedCount) / \(archive.stationCount)")
                    archiveStat("ターン", "\(archive.turnCount)")
                }

                // **畳んだあとも、その日の内訳を同じ数字で読めるようにする。**
                // 休憩の行（`RestPeriod`）は旅を畳むと消えるので、内訳はここにしか残らない。
                // 休んでいない日と、休憩を入れる前の古い記録には出さない
                if archive.walkingSeconds > 0 || archive.restSeconds > 0 {
                    HStack(spacing: 14) {
                        Label("移動 \(DurationText.text(archive.walkingSeconds))",
                              systemImage: "figure.walk")
                        if archive.restSeconds > 0 {
                            Label("休憩 \(DurationText.text(archive.restSeconds))",
                                  systemImage: "cup.and.saucer")
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
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

    private func archiveStat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title3.bold()).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
