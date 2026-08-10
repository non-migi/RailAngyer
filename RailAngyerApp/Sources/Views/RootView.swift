import SwiftUI
import SwiftData
import RailAngyerCore

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var store: GameSessionStore?
    @State private var sync: SyncService?

    var body: some View {
        Group {
            if let store, let sync {
                MainView(store: store, sync: sync)
                    .transition(.opacity)
            } else {
                LaunchLoadingView()
                    .transition(.opacity)
            }
        }
        .tint(Theme.line)
        .task {
            guard store == nil else { return }
            let credentials = KeychainCredentialStore()
            let client = ApiClient(baseURL: ApiConfiguration.baseURL, credentials: credentials)
            let syncService = SyncService(context: context, client: client, credentials: credentials)

            let s = GameSessionStore(context: context)
            s.prepare()
            s.sync = syncService

            // 初期化が速い端末でも起動画面が一瞬ちらつかないよう、短い一拍だけ保つ。
            // UIテストは待たせず、検証時間とタイムアウトを増やさない。
            if !TestHooks.usesInMemoryStore && !TestHooks.resetsProgressOnLaunch {
                try? await Task.sleep(for: .milliseconds(350))
            }
            withAnimation(.easeOut(duration: 0.25)) {
                sync = syncService
                store = s
            }
        }
    }
}

/// ネイティブの起動画面から盤面へ自然につなぐ、短時間のブランド表示。
private struct LaunchLoadingView: View {
    @State private var isMoving = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.50, blue: 0.25),
                                    Color(red: 0.01, green: 0.24, blue: 0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.22)).frame(width: 250, height: 3)
                    HStack(spacing: 34) {
                        ForEach(0..<6, id: \.self) { _ in
                            Circle().fill(.white.opacity(0.55)).frame(width: 6, height: 6)
                        }
                    }
                    Image("WalkingMascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 142, height: 142)
                        .offset(x: isMoving ? 64 : -64, y: isMoving ? -7 : -2)
                        .rotationEffect(.degrees(isMoving ? 1.5 : -1.5))
                        .shadow(color: .black.opacity(0.22), radius: 12, y: 7)
                }
                .frame(height: 158)

                VStack(spacing: 5) {
                    Text("レイルアンギャー")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("駅から駅へ、旅の支度中")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }

                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .accessibilityLabel("読み込み中")
            }
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("launchLoading")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                isMoving = true
            }
        }
    }
}

private struct MainView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @State private var location = LocationService()
    @State private var showingSettings = false
    @State private var showingSchedules = false
    @State private var showingMissions = false
    @State private var showingRoom = false
    @State private var didAskForNotifications = false
    @State private var didRequestLocation = false
    @State private var selectedTab: AppTab = .home
    @State private var isInitialDatabaseLoad = false
    @AppStorage("arrivalRadius") private var arrivalRadius: Double = ArrivalRule.default.radius
    @Environment(\.scenePhase) private var scenePhase

    /// 他の端末の進行を拾う間隔。歩く速さに対してはこれで足りる（11_API設計.md §7）
    private let pullInterval: Duration = .seconds(30)

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeDashboardView(
                    store: store,
                    sync: sync,
                    startJourney: startJourney,
                    showSchedules: { showingSchedules = true },
                    showMissions: { showingMissions = true },
                    showRecords: { selectedTab = .records },
                    showRoom: { showingRoom = true },
                    showSettings: { showingSettings = true })
            }
            .tag(AppTab.home)
            .tabItem { Label("ホーム", systemImage: "house.fill") }

            NavigationStack {
                BoardView(store: store, showingSettings: $showingSettings)
            }
            .tag(AppTab.journey)
            .tabItem { Label("旅", systemImage: "map.fill") }

            NavigationStack {
                JourneyHistoryView(store: store)
            }
            .tag(AppTab.records)
            .tabItem { Label("記録", systemImage: "chart.bar.xaxis") }
        }
        .tint(Theme.line)
        .fullScreenCover(isPresented: .constant(store.phase.isInTurn || store.showingAnnouncement)) {
            TurnFlowView(store: store, location: location)
        }
        .sheet(isPresented: $showingSettings) {
            RuleSettingsView(store: store, sync: sync)
        }
        .sheet(isPresented: $showingSchedules) {
            ScheduleListView(store: store, sync: sync)
        }
        .sheet(isPresented: $showingMissions) {
            MissionEditorView(store: store, sync: sync)
        }
        .sheet(isPresented: $showingRoom) {
            RoomJoinView(store: store, sync: sync)
        }
        .overlay(alignment: .top) {
            if isInitialDatabaseLoad {
                // **全画面で塞がない。** サーバーは寝ていると起きるまで数分かかるが、
                // 遊ぶだけなら端末の中で完結する。待たせる理由がない
                Label("サーバーを起こしています", systemImage: "zzz")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(.top, 4)
            } else if sync.isSyncing {
                Label("データを同期中", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(.top, 4)
            }
        }
        .task {
            // 到着判定は LocationService から。手動到着と同じ入口を通す
            location.onArrive = { order in
                store.arriveAtNextStop(expected: order)
                notifyArrival(at: order)
            }
            location.rule = ArrivalRule(radius: store.arrivalRadius ?? arrivalRadius)
            syncTarget()

            // アプリもDBも寝ていることがある。**起こすのは待たずに裏で進める。**
            // 起きるまで数分かかることがあり、そのあいだ画面を止めると
            // 「立ち上がらないアプリ」に見えてしまう
            if sync.isJoined {
                isInitialDatabaseLoad = true
                Task {
                    await sync.wakeUpIfJoined()
                    await exchange()
                    withAnimation(.easeOut(duration: 0.2)) { isInitialDatabaseLoad = false }
                }
            }
        }
        .task {
            // 定期取得。リアルタイム通信は要らない（§7）
            while !Task.isCancelled {
                try? await Task.sleep(for: pullInterval)
                guard sync.isJoined else { continue }
                await exchange()
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await exchange() }
        }
        .onChange(of: store.phase) {
            syncTarget()
            askForNotificationsIfNeeded()
            // 溜めっぱなしにせず、局面が動いたら送っておく。失敗しても続行できる
            Task { await sync.push() }
        }
        .onChange(of: arrivalRadius) {
            location.rule = ArrivalRule(radius: store.arrivalRadius ?? arrivalRadius)
            syncTarget()
        }
        .onChange(of: selectedTab) {
            if selectedTab == .journey { prepareLocationIfNeeded() }
        }
    }

    private func startJourney() {
        selectedTab = .journey
        prepareLocationIfNeeded()
        // ここではサイコロを振らない。盤面の「サイコロを振る」を押して初めて開始する。
    }

    private func prepareLocationIfNeeded() {
        guard !didRequestLocation else { return }
        didRequestLocation = true
        location.requestAuthorization()
    }

    /// **送ってから取りに行く。** 逆にすると、自分のまだ送っていない記録を
    /// サーバーの古い状態で判断してしまう
    private func exchange() async {
        guard sync.isJoined else { return }
        await sync.push()
        await sync.pull()
    }

    /// 通知の許可は、歩き始めて初めて必要になった時点で聞く。
    /// 起動直後に位置情報と続けて聞くと押し付けがましく、拒否されやすい
    private func askForNotificationsIfNeeded() {
        guard !didAskForNotifications, case .walking = store.phase else { return }
        didAskForNotifications = true
        guard !TestHooks.suppressesNotificationPrompt else { return }
        NotificationService.requestAuthorization()
    }

    /// 位置情報が拾った到着を知らせる。
    /// 手動で到着させたときは画面を見ているので通知しない
    private func notifyArrival(at order: Int) {
        let name = store.stationName(order)
        switch store.phase {
        case .arrivedPassing:
            NotificationService.notifyPassingArrival(station: name)
        case .landed(let station):
            NotificationService.notifyLanding(station: name,
                                              missionCount: store.missionCandidates(at: station).count)
        case .cleared:
            NotificationService.notifyCleared(station: name)
        default:
            NotificationService.notifyPassingArrival(station: name)
        }
    }

    /// いま向かっている駅だけを監視対象にする（R-02）
    private func syncTarget() {
        switch store.phase {
        case .walking(let next, _), .effectWalking(let next, _):
            guard let station = store.station(next) else { return location.stop() }
            location.watch(.init(orderNo: station.orderNo,
                                 name: station.name,
                                 latitude: station.latitude,
                                 longitude: station.longitude))
        default:
            location.stop()
        }
    }
}

private enum AppTab: Hashable { case home, journey, records }

/// 予定・現在の進捗・過去の記録を、起動直後にまとめて確認するホーム。
/// **盤面の外で開くものは、すべてここを入口にする。**
private struct HomeDashboardView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    let startJourney: () -> Void
    let showSchedules: () -> Void
    let showMissions: () -> Void
    let showRecords: () -> Void
    let showRoom: () -> Void
    let showSettings: () -> Void

    private var hasProgress: Bool { !(store.room?.turns.isEmpty ?? true) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                scheduleCard
                recordsCard
                roomCard
                actions
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ホーム")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showSettings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("設定")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasProgress ? "旅を続けよう" : "次の駅へ、歩き出そう")
                        .font(.title2.bold())
                    Text(store.room?.course?.name ?? "コースを準備中")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image("WalkingMascot")
                    .resizable().scaledToFit().frame(width: 88, height: 88)
            }

            HStack(spacing: 0) {
                metric("現在地", store.stationName(store.currentOrder))
                metric("訪問", "\(store.visitedCount)駅")
                metric("時間", DurationText.text(store.timing.elapsedSeconds))
            }

            Button(action: startJourney) {
                Label(hasProgress ? "旅を再開" : "旅をスタート",
                      systemImage: hasProgress ? "play.fill" : "figure.walk.motion")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier("startJourney")
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [Color(red: 0.02, green: 0.55, blue: 0.27),
                                    Color(red: 0.01, green: 0.28, blue: 0.17)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.line.opacity(0.24), radius: 18, y: 9)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var scheduleCard: some View {
        Button(action: showSchedules) {
            dashboardCard(title: "次の予定", icon: "calendar") {
                if let schedule = store.nextSchedule {
                    Text(schedule.title).font(.headline)
                    Text(schedule.startAt.formatted(
                        .dateTime.locale(Locale(identifier: "ja_JP"))
                            .month().day().weekday().hour().minute()))
                        .foregroundStyle(.secondary)
                    if !schedule.courseName.isEmpty {
                        Text("\(schedule.courseName)・サイコロ1〜\(schedule.diceMax)")
                            .font(.caption).foregroundStyle(Theme.line)
                    }
                } else {
                    Text("まだ予定はありません")
                    Text("ルールセットから予定を立てる")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var recordsCard: some View {
        Button(action: showRecords) {
            dashboardCard(title: "最近の旅", icon: "chart.line.uptrend.xyaxis") {
                if let archive = store.archives.first {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DurationText.text(archive.elapsedSeconds)).font(.title2.bold())
                        Spacer()
                        Text("\(archive.visitedCount)駅・写真\(archive.photoCount)枚")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(archive.endedAt.formatted(
                        .dateTime.locale(Locale(identifier: "ja_JP")).year().month().day()))
                        .font(.caption).foregroundStyle(.secondary)
                } else if hasProgress {
                    Text("進行中の旅").font(.headline)
                    Text("\(store.visitedCount)駅訪問・\(DurationText.text(store.timing.elapsedSeconds))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("歩いた旅はここに積み重なります")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 仲間と遊ぶための入口。設定の奥に置くと、そもそも在ることに気づけない
    private var roomCard: some View {
        Button(action: showRoom) {
            dashboardCard(title: "みんなで遊ぶ", icon: "person.2.fill") {
                if sync.isJoined {
                    Text(store.room?.name ?? "参加中").font(.headline)
                    Text("\(store.room?.members.count ?? 1)人が参加しています")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("この端末だけで遊んでいます")
                    Text("招待コードで参加するか、新しくルームを作る")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dashboardCard<Content: View>(
        title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(17)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton("予定", "calendar.badge.plus", showSchedules)
            actionButton("お題", "square.and.pencil", showMissions)
            actionButton("過去の旅", "clock.arrow.circlepath", showRecords)
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

