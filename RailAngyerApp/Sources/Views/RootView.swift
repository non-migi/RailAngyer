import SwiftUI
import SwiftData
import RailAngyerCore

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var store: GameSessionStore?

    var body: some View {
        Group {
            if let store {
                MainView(store: store)
            } else {
                ProgressView()
            }
        }
        .task {
            guard store == nil else { return }
            let s = GameSessionStore(context: context)
            s.prepare()
            store = s
        }
    }
}

private struct MainView: View {
    @Bindable var store: GameSessionStore
    @State private var location = LocationService()
    @State private var showingSettings = false
    @State private var didAskForNotifications = false
    @AppStorage("arrivalRadius") private var arrivalRadius: Double = ArrivalRule.default.radius

    var body: some View {
        NavigationStack {
            BoardView(store: store, showingSettings: $showingSettings)
        }
        .fullScreenCover(isPresented: .constant(store.phase.isInTurn || store.showingAnnouncement)) {
            TurnFlowView(store: store, location: location)
        }
        .sheet(isPresented: $showingSettings) {
            RuleSettingsView(store: store)
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
        }
        .onChange(of: store.phase) {
            syncTarget()
            askForNotificationsIfNeeded()
        }
        .onChange(of: arrivalRadius) {
            location.rule = ArrivalRule(radius: arrivalRadius)
            syncTarget()
        }
    }

    /// 通知の許可は、歩き始めて初めて必要になった時点で聞く。
    /// 起動直後に位置情報と続けて聞くと押し付けがましく、拒否されやすい
    private func askForNotificationsIfNeeded() {
        guard !didAskForNotifications, case .walking = store.phase else { return }
        didAskForNotifications = true
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
