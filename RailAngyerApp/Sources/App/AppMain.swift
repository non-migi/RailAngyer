import SwiftUI
import SwiftData

@main
struct AppMain: App {

    let container: ModelContainer

    init() {
        let schema = Schema(AppSchema.all)
        do {
            if TestHooks.usesInMemoryStore {
                container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } else {
                container = try ModelContainer(for: schema)
            }
        } catch {
            // ディスク上にストアを作れない場合（テストホストや保護された環境）でも
            // 起動を止めない。記録は残らないが、画面は動く。
            print("[RailAngyer] 永続ストアを開けませんでした。メモリ上で起動します: \(error)")
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } catch {
                fatalError("SwiftData を初期化できません: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
