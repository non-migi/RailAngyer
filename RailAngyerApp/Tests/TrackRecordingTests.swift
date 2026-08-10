import Testing
import SwiftData
import CoreLocation
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 実際に歩いた跡を残す（`recordTrackPoint`）。
///
/// **歩いている間だけ残す。** 待っている間まで拾うと、駅で立ち止まっているところが
/// 団子になって線が汚れる。粗い点も混ぜない（地下や谷間では大きく飛ぶ）。
///
/// > 生のGPS座標は**サーバーへ送らない**。ここで残すのは端末の中だけ
@MainActor
struct TrackRecordingTests {

    private let context: ModelContext
    private let store: GameSessionStore
    private let start = Date(timeIntervalSince1970: 1_786_233_600)

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    /// 麻生からの位置を作る。`meters` だけ南へ動かす
    private func location(metersSouth meters: Double, accuracy: Double = 10,
                          after seconds: TimeInterval = 0) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 43.10834 - meters / 111_000,
                                                      longitude: 141.33848),
                   altitude: 0,
                   horizontalAccuracy: accuracy,
                   verticalAccuracy: 5,
                   timestamp: start.addingTimeInterval(seconds))
    }

    /// 歩いている状態にする
    private func startWalking() {
        store.roll(dice: 3)
    }

    @Test("歩いている間は跡が残る")
    func recordsWhileWalking() {
        startWalking()

        store.recordTrackPoint(location(metersSouth: 0))
        store.recordTrackPoint(location(metersSouth: 40, after: 30))

        #expect(store.trackPoints.count == 2)
    }

    @Test("歩き出す前は残さない")
    func ignoresBeforeWalking() {
        // サイコロを振る前は、集合場所で立ち話をしている時間。跡にしても意味がない
        store.recordTrackPoint(location(metersSouth: 0))

        #expect(store.trackPoints.isEmpty)
    }

    @Test("近すぎる点は捨てる")
    func skipsPointsTooClose() {
        startWalking()
        store.recordTrackPoint(location(metersSouth: 0))

        store.recordTrackPoint(location(metersSouth: 5, after: 10))     // 5m しか動いていない

        #expect(store.trackPoints.count == 1)
    }

    @Test("精度の粗い点は混ぜない")
    func skipsInaccuratePoints() {
        startWalking()

        store.recordTrackPoint(location(metersSouth: 0, accuracy: 200))
        store.recordTrackPoint(location(metersSouth: 60, accuracy: -1, after: 30))

        // 地下や高層ビルの谷間では大きく飛ぶ。混ぜると線が街を横切る
        #expect(store.trackPoints.isEmpty)
    }

    @Test("跡は時刻の順に返る")
    func returnsInTimeOrder() {
        startWalking()
        store.recordTrackPoint(location(metersSouth: 0, after: 0))
        store.recordTrackPoint(location(metersSouth: 40, after: 30))
        store.recordTrackPoint(location(metersSouth: 80, after: 60))

        let times = store.trackPoints.map(\.recordedAt)
        #expect(times == times.sorted())
    }

    @Test("跡は送信キューに積まれない")
    func neverEnqueued() throws {
        startWalking()
        let before = try context.fetch(FetchDescriptor<PendingChange>()).count

        store.recordTrackPoint(location(metersSouth: 0))
        store.recordTrackPoint(location(metersSouth: 40, after: 30))

        // **生のGPS座標は端末の外へ出さない**（16_プライバシーポリシー.md §1）
        #expect(try context.fetch(FetchDescriptor<PendingChange>()).count == before)
    }

    @Test("記録をリセットすると跡も消える")
    func resetClearsTrack() {
        startWalking()
        store.recordTrackPoint(location(metersSouth: 0))
        store.recordTrackPoint(location(metersSouth: 40, after: 30))

        store.resetProgress(archive: false)

        #expect(store.trackPoints.isEmpty)
    }
}
