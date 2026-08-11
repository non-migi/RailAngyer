import SwiftUI
import SwiftData
import RailAngyerCore

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var store: GameSessionStore?
    @State private var sync: SyncService?
    /// アプリの中で選んだ言語。**選んだその場で画面が切り替わる**
    @State private var language = LanguageSetting()

    var body: some View {
        Group {
            if let store, let sync {
                MainView(store: store, sync: sync, language: language)
                    .transition(.opacity)
            } else {
                LaunchLoadingView()
                    .transition(.opacity)
            }
        }
        .tint(Theme.line)
        // **いちばん外側で流す。** ここに置けば、下のシートまで一度に切り替わる
        .environment(\.locale, language.locale)
        .task {
            guard store == nil else { return }
            let credentials = KeychainCredentialStore()
            let client = ApiClient(baseURL: ApiConfiguration.baseURL, credentials: credentials)
            let syncService = SyncService(context: context, client: client, credentials: credentials)

            Telemetry.start()

            let s = GameSessionStore(context: context)
            s.prepare(sampleMissions: TestHooks.seedsSampleMissions)
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
            // アイコンの地色に合わせる（#4CAB72 → #357F55）。
            // **アイコンと起動画面がつながって見えるようにする**
            LinearGradient(colors: [Color(red: 0.298, green: 0.671, blue: 0.447),
                                    Color(red: 0.208, green: 0.498, blue: 0.333)],
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
    @Bindable var language: LanguageSetting
    @State private var location = LocationService()
    @State private var showingSettings = false
    @State private var showingSchedules = false
    @State private var showingMissions = false
    @State private var showingRoom = false
    @State private var showingPhotos = false
    /// ターンの画面をしまって盤面を見ているか。**次のターンが始まれば戻す**
    @State private var isTurnMinimized = false
    @State private var didAskForNotifications = false
    @State private var didRequestLocation = false
    @State private var selectedTab: AppTab = .home
    @State private var isInitialDatabaseLoad = false
    /// 共有リンクから開かれた招待。出している間だけ値が入る
    @State private var invitation: InviteLink.Invitation?
    /// 「旅をスタート」で出す、予定から選ぶ画面
    @State private var showingStartPicker = false
    /// 初めて遊ぶ人に、最初の一度だけ遊び方を出す。
    /// **このアプリは初見で分かる作りではない**（サイコロ・お題・到着判定）
    @AppStorage("didReadHowToPlay") private var didReadHowToPlay = false
    @State private var showingHowToPlay = false
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
                    showPhotos: { showingPhotos = true },
                    showRecords: { selectedTab = .records },
                    showRoom: { showingRoom = true },
                    showSettings: { showingSettings = true })
            }
            .tag(AppTab.home)
            .tabItem { Label("ホーム", systemImage: "house.fill") }

            NavigationStack {
                // 引数は統合後の BoardView に合わせる（sync は取らない）。
                // 末尾のクロージャは、しまったターン画面へ戻る操作
                BoardView(store: store, showingSettings: $showingSettings) {
                    isTurnMinimized = false
                }
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
        // **プレイ中でも盤面へ抜けられるようにする。**
        // 覆いっぱなしだと、歩いている間ずっと全体マップが見られない
        .fullScreenCover(isPresented: Binding(
            get: { (store.phase.isInTurn || store.showingAnnouncement) && !isTurnMinimized },
            set: { if !$0 { isTurnMinimized = true } })) {
            TurnFlowView(store: store, location: location) {
                isTurnMinimized = true
                selectedTab = .journey
            }
        }
        .sheet(isPresented: $showingSettings) {
            RuleSettingsView(store: store, sync: sync, language: language)
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
        .sheet(isPresented: $showingPhotos) {
            // ホームからは**端末に残っている写真をぜんぶ**見せる。
            // いまの旅のぶんだけだと、旅を保存した時点で空になってしまう。
            // 開いたときと引っ張ったときに、仲間の写真を取りに行く
            PhotoGalleryView(items: PhotoGalleryView.allItems(in: store),
                             onRefresh: {
                                 // **送ってから取りに行く。** 消したことを先に届けないと、
                                 // サーバーにまだ残っている写真を取り直して生き返る
                                 await sync.push()
                                 _ = await sync.pullPhotos()
                             },
                             onDelete: { item in
                                 if let id = item.photoId { store.deletePhoto(id: id) }
                             })
        }
        .sheet(item: $invitation) { invite in
            InviteAcceptView(invitation: invite, store: store, sync: sync)
        }
        .sheet(isPresented: $showingStartPicker) {
            StartFromScheduleView(store: store) { startJourneyNow() }
        }
        .sheet(isPresented: $showingHowToPlay) {
            HowToPlayView()
        }
        // **リンクから開いたら、ルームへ入れるところまで案内する。**
        // 地図を開くだけでは、誘われた側が何をすればいいか分からない
        .onOpenURL { url in
            guard let invite = InviteLink.invitation(from: url) else { return }
            Telemetry.inviteOpened()
            invitation = invite
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
            // 実際に歩いた跡を残す。**歩いている間だけ**（判断は store 側）
            location.onMove = { store.recordTrackPoint($0) }
            location.rule = ArrivalRule(radius: effectiveArrivalRadius)
            syncTarget()

            // 初回だけ遊び方を出す。UIテストの邪魔をしないよう、testでは出さない
            if !didReadHowToPlay && !TestHooks.usesInMemoryStore {
                showingHowToPlay = true
            }

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
            Task {
                await exchange()
                // 写真は**一覧だけ**軽く拾う。実体はギャラリーを開いたときに落とす。
                // 歩いている最中に重い通信をさせない（電池と通信量の話）。
                // 一覧が入れば、地図のピンやふりかえりには仲間の写真の存在が出る
                _ = await sync.pullPhotos(fetchBodies: false)
            }
        }
        .onChange(of: store.showingAnnouncement) {
            // 新しくサイコロを振ったら、しまっていても前に出す
            if store.showingAnnouncement { isTurnMinimized = false }
        }
        .onChange(of: store.phase) {
            // ターンが終わったら、次に振るときのためにしまいを解く
            if !store.phase.isInTurn { isTurnMinimized = false }
            syncTarget()
            askForNotificationsIfNeeded()
            // 溜めっぱなしにせず、局面が動いたら送っておく。失敗しても続行できる
            Task { await sync.push() }
        }
        .onChange(of: arrivalRadius) {
            location.rule = ArrivalRule(radius: effectiveArrivalRadius)
            syncTarget()
        }
        .onChange(of: selectedTab) {
            if selectedTab == .journey { prepareLocationIfNeeded() }
        }
    }

    /// 旅を始める。
    ///
    /// **これから歩く予定が立っているなら、まずそれを選ばせる。**
    /// 予定のたびにルール設定をたどり直すのは、同じことを二度決めているのと同じ。
    /// 予定が無ければ、これまでどおりそのまま盤面へ進む
    private func startJourney() {
        // **歩き出したあとは選ばせない。** 途中でルールは移せない（T-06）ので、
        // 選ばせても断るしかない。再開はそのまま盤面へ
        if store.hasStartedJourney || store.startableSchedules.isEmpty {
            startJourneyNow()
        } else {
            showingStartPicker = true
        }
    }

    /// 予定を選び終えた（あるいは予定が無い）あとの、実際の開始。
    /// 予定のルールの取り込みは `StartFromScheduleView` が `applySchedule` で済ませている
    private func startJourneyNow() {
        Telemetry.journeyStarted(course: store.room?.course?.name,
                                 isLap: store.room?.isLap == true,
                                 stationCount: store.stationsInOrder.count)
        selectedTab = .journey
        prepareLocationIfNeeded()
        // 予定を取り込むと区間も半径も変わりうるので、監視をやり直す
        location.rule = ArrivalRule(radius: effectiveArrivalRadius)
        syncTarget()
        // ここではサイコロを振らない。盤面の「サイコロを振る」を押して初めて開始する。
    }

    /// 到着判定の半径。**予定 > コース > 端末の設定**の順で、先に決まっているものを使う。
    /// 予定とコースの優先は `GameSessionStore.arrivalRadius` が見ているので、
    /// ここは最後の受け皿として端末の設定を足すだけ
    private var effectiveArrivalRadius: Double {
        store.arrivalRadius ?? arrivalRadius
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
    let showPhotos: () -> Void
    let showRecords: () -> Void
    let showRoom: () -> Void
    let showSettings: () -> Void

    private var hasProgress: Bool { !(store.room?.turns.isEmpty ?? true) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                roomCard
                scheduleCard
                recordsCard
                actions
            }
            .padding()
        }
        .background(Theme.canvas)
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
                        .font(.subheadline).foregroundStyle(.secondary)
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
            .tint(Theme.line)
            .foregroundStyle(Theme.onLine)
            .accessibilityIdentifier("startJourney")
        }
        .padding(20)
        // **緑一色で塗らない。** 乗換案内の類はどれも地を白か淡い灰にして、
        // 色は路線と主ボタンだけに使う。塗ると路線の色が埋もれ、
        // 文字も白抜きになって読みづらくなる（濃い緑の上の薄い文字が読めなかった）
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
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

    /// 記録の入口。**写真もここから開く。**
    /// 写真は旅の記録を別の角度から見ているだけなので、ホームのボタンを分けない
    private var recordsCard: some View {
        VStack(spacing: 0) {
            recordsSummary
            Divider().padding(.leading, 17)
            Button(action: showPhotos) {
                HStack {
                    Label("写真をまとめて見る", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 17).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openPhotos")
        }
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// **歩いている最中は、いまの旅を先に出す。**
    /// 過去のアーカイブを優先していたせいで、別のコースで遊んだ古い記録の
    /// 日付と駅数がホームに出て、「別の旅が進行中」に見えていた。
    /// 過去のものを出すときは、終わった旅だと分かる言葉を必ず添える
    /// （並びは記録画面（`JourneyHistoryView`）の「進行中」→「これまでの旅」に合わせる）
    private var recordsSummary: some View {
        Button(action: showRecords) {
            dashboardCard(title: hasProgress ? "進行中の旅" : "最近の旅",
                          icon: "chart.line.uptrend.xyaxis") {
                if hasProgress {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DurationText.text(store.timing.elapsedSeconds)).font(.title2.bold())
                        Spacer()
                        Text("\(store.visitedCount)駅訪問")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("いま歩いている旅です")
                        .font(.caption).foregroundStyle(Theme.line)
                    if let archive = store.archives.first {
                        Text("ひとつ前の旅：\(dateText(archive.endedAt))・\(archive.visitedCount)駅")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                } else if let archive = store.archives.first {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DurationText.text(archive.elapsedSeconds)).font(.title2.bold())
                        Spacer()
                        Text("\(archive.visitedCount)駅・写真\(archive.photoCount)枚")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(dateText(archive.endedAt))に終わった旅")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("歩いた旅はここに積み重なります")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).year().month().day())
    }

    /// 仲間と遊ぶための入口。設定の奥に置くと、そもそも在ることに気づけない。
    ///
    /// **いまどのルームにいるのかを、ホームの一番上で常に見せる。**
    /// 参加していないことも同じ場所に出す。どちらの状態でも、
    /// このカードを押せば参加・作成の画面（`RoomJoinView`）に行ける。
    /// 未参加のときの見出しは、他の画面の案内文（ホームの「みんなで遊ぶ」から）と
    /// 同じ言葉のままにしておく
    private var roomCard: some View {
        Button(action: showRoom) {
            dashboardCard(title: sync.isJoined ? "いまのルーム" : "みんなで遊ぶ",
                          icon: "person.2.fill") {
                if sync.isJoined {
                    joinedRoomBody
                } else {
                    unjoinedRoomBody
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("roomCard")
    }

    private var joinedRoomBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.room?.name ?? "参加中")
                .font(.title3.bold())
                .lineLimit(2)
            Text(roomSummary)
                .font(.subheadline).foregroundStyle(Theme.line)
            if !memberNames.isEmpty {
                Text(memberNames)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let code = store.room?.inviteCode, !code.isEmpty {
                Text("招待コード \(code)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
        }
    }

    private var unjoinedRoomBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ルーム未参加")
                .font(.title3.bold())
            Text("いまはこの端末だけで遊んでいます")
                .font(.subheadline).foregroundStyle(.secondary)
            Label("招待コードで参加、または新しく作る", systemImage: "person.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.onLine)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.line, in: Capsule())
                .padding(.top, 3)
        }
    }

    /// コース名は無いことがある。そのときは人数だけを出す
    private var roomSummary: String {
        let people = "\(max(store.room?.members.count ?? 1, 1))人が参加中"
        guard let course = store.room?.course?.name, !course.isEmpty else { return people }
        return "\(course)・\(people)"
    }

    /// 名前が多いとカードが伸びるので、先頭だけ出して残りは人数で示す
    private var memberNames: String {
        let names = (store.room?.members ?? [])
            .sorted { $0.joinedAt < $1.joinedAt }
            .map(\.displayName)
        guard !names.isEmpty else { return "" }
        if names.count <= 3 { return names.joined(separator: "・") }
        return names.prefix(3).joined(separator: "・") + "・ほか\(names.count - 3)人"
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
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton("予定", "calendar.badge.plus", showSchedules)
            actionButton("お題", "square.and.pencil", showMissions)
            actionButton("ルーム", "person.2.fill", showRoom)
            actionButton("過去の旅", "clock.arrow.circlepath", showRecords)
            // 写真はここには置かない。旅の記録と同じものなので、記録カードの中から開く
        }
    }

    private func actionButton(_ title: LocalizedStringKey, _ icon: String,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

