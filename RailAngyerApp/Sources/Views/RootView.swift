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
            location.onArrive = { [weak store] order in
                store?.arriveAtNextStop(expected: order)
            }
            location.rule = ArrivalRule(radius: arrivalRadius)
            location.requestAuthorization()
            syncTarget()
        }
        .onChange(of: store.phase) { syncTarget() }
        .onChange(of: arrivalRadius) {
            location.rule = ArrivalRule(radius: arrivalRadius)
            syncTarget()
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
