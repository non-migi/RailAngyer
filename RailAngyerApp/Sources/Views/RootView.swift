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
            } else {
                ProgressView()
            }
        }
        .task {
            guard store == nil else { return }
            let credentials = KeychainCredentialStore()
            let client = ApiClient(baseURL: ApiConfiguration.baseURL, credentials: credentials)
            let syncService = SyncService(context: context, client: client, credentials: credentials)

            let s = GameSessionStore(context: context)
            s.prepare()
            s.sync = syncService

            sync = syncService
            store = s
        }
    }
}

private struct MainView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @State private var location = LocationService()
    @State private var showingSettings = false
    @State private var didAskForNotifications = false
    @AppStorage("arrivalRadius") private var arrivalRadius: Double = ArrivalRule.default.radius
    @Environment(\.scenePhase) private var scenePhase

    /// 他の端末の進行を拾う間隔。歩く速さに対してはこれで足りる（11_API設計.md §7）
    private let pullInterval: Duration = .seconds(30)

    var body: some View {
        NavigationStack {
            BoardView(store: store, showingSettings: $showingSettings)
        }
        .fullScreenCover(isPresented: .constant(store.phase.isInTurn || store.showingAnnouncement)) {
            TurnFlowView(store: store, location: location)
        }
        .sheet(isPresented: $showingSettings) {
            RuleSettingsView(store: store, sync: sync)
        }
        .task {
            // 到着判定は LocationService から。手動到着と同じ入口を通す
            location.onArrive = { order in
                store.arriveAtNextStop(expected: order)
                notifyArrival(at: order)
            }
            location.rule = ArrivalRule(radius: arrivalRadius)
            location.requestAuthorization()
            syncTarget()

            // アプリもDBも寝ていることがある。起こしておくと実プレイ時の待ちが減る
            await sync.wakeUpIfJoined()
            await exchange()
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
            location.rule = ArrivalRule(radius: arrivalRadius)
            syncTarget()
        }
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
