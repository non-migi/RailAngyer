import SwiftUI
import SwiftData

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
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            BoardView(store: store, showingSettings: $showingSettings)
        }
        .fullScreenCover(isPresented: .constant(store.phase.isInTurn || store.showingAnnouncement)) {
            TurnFlowView(store: store)
        }
        .sheet(isPresented: $showingSettings) {
            RuleSettingsView(store: store)
        }
    }
}
