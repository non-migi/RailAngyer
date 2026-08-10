import Testing
import Foundation
@testable import RailAngyerApp

/// 利用状況の測定（`Telemetry`）。
///
/// **App ID を入れ忘れると、黙って何も送らない。**
/// 動かないことに気づけないので、埋め込まれていることをここで押さえる。
/// 送信そのものは外へ出るため確かめない。
@MainActor
struct TelemetryTests {

    @Test("送る先が埋め込まれている")
    func appIDIsEmbedded() throws {
        // テストの実行ファイルではなく、**アプリのバンドル**を見る。
        // 目印にはアプリ側のクラスを使う（テスト側のクラスだとテストのバンドルになる）
        let bundle = Bundle(for: GameSessionStore.self)
        let value = bundle.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
        let id = try #require(value?.trimmingCharacters(in: .whitespacesAndNewlines))

        #expect(!id.isEmpty, "App ID が空。測定は動かない")
        #expect(!id.hasPrefix("$("), "ビルド設定が展開されていない: \(id)")
        #expect(UUID(uuidString: id) != nil, "UUID の形ではない: \(id)")
    }

    @Test("テストのあいだは測定しない")
    func doesNotMeasureDuringTests() {
        // **ユニットテストはアプリを起動したまま走る。**
        // ここを塞がないと、テストを流すたびに本番の数字が汚れる
        #expect(!Telemetry.isEnabled, "テスト中なのに測定が動いている")
    }

}
