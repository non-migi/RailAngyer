import SwiftUI
import RailAngyerCore

/// SC-04 盤面。アプリの主画面。
struct BoardView: View {
    @Bindable var store: GameSessionStore
    @Binding var showingSettings: Bool
    /// ターンの画面をしまって盤面を見ているとき、戻るための操作
    var onResumeTurn: (() -> Void)?
    @State private var selectedStation: StationSelection?
    @State private var showingSummary = false
    @State private var showingCamera = false
    @State private var showingJourneyMissions = false
    /// ゴールしたあとの締めくくり。**畳む前に今日の記録を見せる**
    @State private var showingFinishSummary = false
    /// 締めくくりの画面で「畳む」と決めたか。畳むのは画面が閉じたあと
    @State private var finishesOnDismiss = false
    /// 終わりにすると決めた時刻。開いた瞬間に凍らせ、表示と保存で同じ値を使う
    @State private var stoppedAt: Date?
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
        .sheet(isPresented: $showingJourneyMissions) {
            JourneyMissionsView(store: store)
        }
        // ゴールしたときも締めくくりを挟む。**途中でやめるときと扱いを揃える。**
        // 押した瞬間に旅が畳まれると、その日の記録を見る前に消したことになる
        .sheet(isPresented: $showingFinishSummary, onDismiss: finishIfDecided) {
            JourneySummaryView(store: store, finish: .cleared,
                               onFinish: { finishesOnDismiss = true },
                               stoppedAt: stoppedAt)
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
        // **地は淡く保つ。** 濃い緑を敷いていたころは、その上の
        // 「踏破 0 / 16」が緑の文字と灰の文字で、どちらも読めなかった。
        // 乗換案内の類と同じく、色は路線と要点だけに使う
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.separator).frame(height: 0.5)
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
                    // **合計と移動の差が休憩のせいだと分かるようにする。**
                    // 合計には休憩が入り、移動からは引かれているので、
                    // 出さないと数え損ないに見える。休んでいない日は出さない
                    if timing.restSeconds > 0 {
                        Label("休憩 \(DurationText.text(timing.restSeconds))",
                              systemImage: "cup.and.saucer")
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // ホームの「お題」は**書く**ための入口。こちらは**この旅で引いたお題**を見るところで、
                // 行き先が違うので同じ導線の重複にはならない
                quickAction(appLocalized("旅のお題"), systemImage: "checkmark.circle",
                            badge: store.unresolvedMissionTurns.count) {
                    showingJourneyMissions = true
                }
                .accessibilityIdentifier("journeyMissions")
                quickAction(appLocalized("ふりかえり"), systemImage: "book.closed") {
                    showingSummary = true
                }
                .accessibilityIdentifier("openSummary")
                quickAction(appLocalized("設定"), systemImage: "gearshape") {
                    showingSettings = true
                }
            }
            // **休むこととやめることは、旅が始まっていれば常に要る。**
            // ゴールしたときだけの操作にすると、日が暮れて途中でやめる場面で
            // 予定の画面の底まで探しに行かせることになる。
            // ゴールしたあとだけは出さない。下に「記録を保存して新しい旅へ」があり、
            // 着いたのに「今日はここまで」と言うのも筋が通らない
            if store.hasStartedJourney, !isCleared {
                JourneyPauseBar(store: store)
            }
        }
        .padding(.top, 5)
    }

    /// - Parameter badge: 0 より大きいときだけ数を添える（進行中のお題の件数）。
    /// - Parameter title: 訳し済みの文字列を渡す（数を添えて組むため `String` で受ける）
    private func quickAction(
        _ title: String,
        systemImage: String,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(badge > 0 ? "\(title) \(badge)" : title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .accessibilityLabel(badge > 0 ? appLocalized("\(title)　進行中 \(badge) 件") : title)
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

    /// ゴールに到達しているか
    private var isCleared: Bool {
        if case .cleared = store.phase { return true }
        return false
    }

    /// 締めくくりの画面で決めたとおりに旅を畳む。
    ///
    /// **畳むのは画面が閉じきってから。** 開いたまま消すと、消えたターンや訪問を
    /// 掴んだ画面が描き直され、SwiftData が「元のデータが無い」と言って落ちる
    private func finishIfDecided() {
        guard finishesOnDismiss else { return }
        finishesOnDismiss = false
        // **画面に出した数字と、記録に残す数字を同じにする。**
        // 開いた瞬間の時刻で数え、眺めていたあいだのぶんは入れない
        let now = stoppedAt ?? Date()
        stoppedAt = nil
        // 終わりにすると決めた＝休憩も終わり
        store.endRest(at: now)
        store.resetProgress(now: now)
    }

    /// 戻る口の文言。いま何の途中なのかが分かるようにする
    private var resumeTitle: String {
        switch store.phase {
        case .walking(let next, _):        appLocalized("\(store.stationName(next)) へ歩く")
        case .effectWalking(let next, _):  appLocalized("\(store.stationName(next)) へ歩く")
        case .landed:                      appLocalized("お題を引く")
        case .mission:                     appLocalized("お題を続ける")
        case .arrivedPassing:              appLocalized("次の駅へ")
        default:                           appLocalized("旅を続ける")
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if case .cleared = store.phase {
                Text("ゴールに到達しました")
                    .font(.headline).foregroundStyle(Theme.line)
                // **ゴールしたあとは一本道。** 「ふりかえりを見る」と
                // 「記録を保存して新しい旅へ」が同じ画面を開くのに名前が違うと、
                // 押す前に違いが分からない。畳む口はふりかえりの中に置き、
                // 旅の途中の「今日はここまでにする」と構造を揃える
                Button("ふりかえりを見る") {
                    stoppedAt = Date()
                    showingFinishSummary = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.line)
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
                stationAction
                Button {
                    store.roll()
                } label: {
                    Text("サイコロを振る")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                // 文字は9言語で変わる。言語ごとに撮るときはこの名前で探す
                .accessibilityIdentifier("rollDice")
                .controlSize(.large)
                .tint(Theme.line)
                .disabled(isTurnInProgress)
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
            secondary(appLocalized("\(store.stationName(store.currentOrder)) に到着した"),
                      systemImage: "mappin.and.ellipse") {
                store.startJourney()
            }
        } else if store.currentVisit != nil {
            secondary(CameraPicker.isCameraAvailable
                          ? appLocalized("この駅で写真を撮る")
                          : appLocalized("この駅の写真を選ぶ"),
                      systemImage: "camera") {
                showingCamera = true
            }
        }
    }

    /// - Parameter title: 訳し済みの文字列を渡す（駅名を差し込んで組むため `String` で受ける）
    /// 盤面の補助操作。文字は9言語で変わるので、識別子で探せるようにしておく
    private func secondary(_ title: String, systemImage: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("boardSecondaryAction")
    }
}

/// 休憩と「今日はここまでにする」。
///
/// **歩いている場所から届くところに置く。** 現地で疲れて休みたい、日が暮れたので
/// 途中でやめたい、というのは歩いている最中に起きる。盤面（`BoardView`）と
/// ターンの画面（`TurnFlowView`）の両方に同じ形で出し、どちらからでも同じ操作で済ませる。
///
/// > **「記録を保存して新しい旅へ」とは別の言葉にする。**
/// > あちらは予定の画面にある**次を始める**ための口で、
/// > ここは**今日をやめる**ための口。同じ結果になるとしても、
/// > 探すときに思い浮かべる言葉が違う。
struct JourneyPauseBar: View {
    @Bindable var store: GameSessionStore
    /// ターンの画面は上端の細い行に置くので、幅いっぱいには広げない
    var isCompact = false
    /// 締めくくりのふりかえり。**やめると決める前に、今日の記録を見せる**
    @State private var showingFinishSummary = false
    /// 締めくくりの画面で「畳む」と決めたか
    @State private var finishesOnDismiss = false
    /// 「今日はここまでにする」を押した時刻。
    ///
    /// **旅が終わったのは歩くのをやめたとき。** 途中でやめるとそのターンは未完了のままで、
    /// 時間は「いま」まで数え続ける。凍らせないと、ふりかえりを眺めていた時間が
    /// そのまま今日の旅の長さになる。「まだ続ける」で戻ったら、次に押した時刻で取り直す
    @State private var stoppedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            if let startedAt = store.activeRest?.startedAt {
                resting(since: startedAt)
                control(appLocalized("再開する"), systemImage: "figure.walk") {
                    store.endRest()
                }
            } else {
                control(appLocalized("休憩する"), systemImage: "cup.and.saucer") {
                    store.startRest()
                }
            }
            control(appLocalized("今日はここまでにする"), systemImage: "flag.checkered") {
                stoppedAt = Date()
                showingFinishSummary = true
            }
            if isCompact { Spacer(minLength: 0) }
        }
        // **やめる前に今日の記録を見せる。** 確認だけを出して畳むと、
        // 歩いた跡も数字も見ないまま空の盤面が残る。ここが1日の締めくくりになる
        .sheet(isPresented: $showingFinishSummary, onDismiss: finishIfDecided) {
            JourneySummaryView(store: store, finish: .quit,
                               onFinish: { finishesOnDismiss = true },
                               stoppedAt: stoppedAt)
        }
    }

    /// 締めくくりの画面で決めたとおりに旅を畳む。
    /// **畳むのは画面が閉じきってから**（消した記録を掴んだまま描き直すと落ちる）
    private func finishIfDecided() {
        guard finishesOnDismiss else { return }
        finishesOnDismiss = false
        // **画面に出した数字と、記録に残す数字を同じにする。**
        // 押した瞬間の時刻で数え、ふりかえりを眺めていたあいだは入れない
        let now = stoppedAt ?? Date()
        stoppedAt = nil
        // 終わりにすると決めた＝休憩も終わり。
        // 「まだ続ける」で戻ったときは休憩を続けたいので、閉じるのは確定した時だけ
        store.endRest(at: now)
        store.resetProgress(now: now)
    }

    /// 休憩中であることと、その経過。
    ///
    /// **休み始めたことに気づけないまま放置されるのがいちばん困る**ので、
    /// ボタンではなく経過の出ている表示に変え、隣に「再開する」を置く
    private func resting(since startedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label(appLocalized("休憩中 \(DurationText.text(context.date.timeIntervalSince(startedAt)))"),
                  systemImage: "cup.and.saucer.fill")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.mission)
                .padding(.horizontal, 10)
                .frame(maxWidth: isCompact ? nil : .infinity, minHeight: 32)
                .background(Theme.mission.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// - Parameter title: 訳し済みの文字列を渡す（盤面の他のボタンと同じ作法）
    private func control(_ title: String, systemImage: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: isCompact ? nil : .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .accessibilityLabel(title)
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

    private func badge(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.line.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.line)
    }
}

/// この旅で引いたお題の一覧。
///
/// **歩きながら続けられるお題のための画面。** 引いたその場で決めずに「あとで」にしたお題を
/// ここに集め、達成したかを後から付けられるようにする（済んだぶんも並べて振り返れる）
private struct JourneyMissionsView: View {
    @Bindable var store: GameSessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// 通報メールを開けなかった（`mailto:` を扱えない端末）
    @State private var showingReportFallback = false

    var body: some View {
        NavigationStack {
            List {
                if store.unresolvedMissionTurns.isEmpty && store.resolvedMissionTurns.isEmpty {
                    Section {
                        Text("まだお題を引いていません。駅に着地すると1つ引きます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                // **どちらの遊び方なのかを一覧の頭で伝える。**
                // 引いたお題が「みんなのぶん」なのか「自分のぶん」なのかで、
                // ここに並ぶものの意味が変わる
                if let style = store.room?.missionStyle {
                    Section {
                        Label(style.notice,
                              systemImage: style == .team ? "person.3" : "person")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !store.unresolvedMissionTurns.isEmpty {
                    Section {
                        ForEach(store.unresolvedMissionTurns) { turn in
                            unresolvedRow(turn)
                        }
                    } header: {
                        Text("進行中　\(store.unresolvedMissionTurns.count) 件")
                    } footer: {
                        Text("歩きながら続けているお題です。終わったら達成を付けてください。")
                    }
                }

                if !store.resolvedMissionTurns.isEmpty {
                    Section("済んだお題") {
                        ForEach(store.resolvedMissionTurns) { turn in
                            resolvedRow(turn)
                        }
                    }
                }
            }
            .navigationTitle("旅のお題")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .reportMailFallbackAlert(isPresented: $showingReportFallback)
        }
    }

    private func unresolvedRow(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(turn)
            Text(turn.selectedMission?.content ?? "")
                .font(.body)
            HStack(spacing: 10) {
                Button("達成した") { store.resolveMission(turn, done: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.line)
                Button("できなかった") { store.resolveMission(turn, done: false) }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
            .buttonBorderShape(.roundedRectangle(radius: 10))
        }
        .padding(.vertical, 4)
        .contextMenu { reportMenu(for: turn) }
    }

    private func resolvedRow(_ turn: Turn) -> some View {
        let outcome = MissionOutcome(turn)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: outcome.symbolName)
                .foregroundStyle(JourneySummaryView.color(of: outcome))
            VStack(alignment: .leading, spacing: 4) {
                heading(turn)
                Text(turn.selectedMission?.content ?? "")
                    .font(.subheadline)
                    .foregroundStyle(outcome == .done ? .primary : .secondary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { reportMenu(for: turn) }
    }

    /// 他人が書いたお題への通報の口（App Store ガイドライン 1.2）。
    /// 自分のお題には出さない（中身が空なら SwiftUI がメニューごと出さない）
    @ViewBuilder
    private func reportMenu(for turn: Turn) -> some View {
        if let mission = turn.selectedMission,
           let author = mission.member, !author.isMe {
            Button {
                guard let url = ReportMail.url(target: .mission,
                                               roomName: store.room?.name,
                                               authorName: author.displayName,
                                               postedAt: mission.createdAt,
                                               detail: mission.content) else { return }
                // **開けたかどうかを見る。** `mailto:` を扱えない端末では
                // 押しても何も起きず、通報の手段が無いのと同じになる
                openURL(url) { accepted in
                    if !accepted { showingReportFallback = true }
                }
            } label: {
                Label("このお題を通報する", systemImage: "flag")
            }
        }
    }

    /// 何駅目の、誰が書いたお題か
    private func heading(_ turn: Turn) -> some View {
        let station = turn.landingPosition ?? turn.landingStation?.orderNo
        let author = turn.selectedMission?.member?.displayName ?? appLocalized("だれか")
        return Text("\(station.map(store.stationName) ?? "-")　\(author) が書いた")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// `sheet(item:)` に渡すための包み。
/// `Int` に直接 `Identifiable` を後付けすると、他のライブラリと衝突しうるため避ける
struct StationSelection: Identifiable, Equatable {
    let id: Int
}
