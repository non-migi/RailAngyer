import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 「記録を保存して新しい旅へ」（`resetProgress`）。
///
/// 記録を消したあとも**画面が壊れずに次の旅を始められる**ことを確かめる。
/// 消したモデルを掴んだまま参照すると SwiftData が落ちるため、
/// リセット直後に画面が読む値（局面・現在地・集計・地図の区間）を一通りなぞる。
@MainActor
struct ResetProgressTests {

    private let context: ModelContext
    private let store: GameSessionStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    /// 出目を指定して1ターン歩ききる
    private func playTurn(dice: Int) {
        store.roll(dice: dice)
        for _ in 0..<30 {
            switch store.phase {
            case .walking, .effectWalking: store.arriveAtNextStop()
            case .arrivedPassing: store.continueWalking()
            case .landed: store.drawMission()
            case .mission: store.finishMission(done: true)
            default: return
            }
        }
    }

    @Test("記録を保存して新しい旅へ進める")
    func resetArchivesAndStartsOver() throws {
        playTurn(dice: 3)
        #expect(store.visitedCount > 0)

        store.resetProgress()

        // 保存された記録が1件残り、進行だけが消えている
        #expect(store.archives.count == 1)
        #expect(store.lastError == nil)
        #expect(store.visitedCount == 0)
        #expect(store.activeTurn == nil)
        #expect(store.currentOrder == store.room?.startStation?.orderNo)
    }

    @Test("リセット直後に画面が読む値をすべて触っても落ちない")
    func viewsSurviveReset() throws {
        playTurn(dice: 3)
        store.resetProgress()

        // 盤面・地図・ふりかえりが起動直後に読むもの
        _ = store.phase
        _ = store.timing
        _ = store.legs
        _ = store.visitedOrders
        _ = store.landedOrders
        _ = store.photographedOrders
        _ = store.stationsInOrder
        _ = store.currentTurnBreakdown
        for order in 1...16 {
            _ = store.visits(at: order)
            _ = store.photoFileNames(at: order)
            _ = store.legs(arrivingAt: order)
        }
        let summary = try #require(store.room.map { JourneySummary(room: $0, engine: store.engine) })
        #expect(summary.visitedCount == 0)
    }

    @Test("写真を撮った旅を保存しても、写真の実体は消さない")
    func keepsPhotoFilesWhenArchiving() throws {
        playTurn(dice: 2)
        let visit = try #require(store.room?.visits.first)
        let photo = Photo(localFileName: "test-\(UUID().uuidString).jpg")
        photo.visit = visit
        context.insert(photo)
        try context.save()

        store.resetProgress()

        // 記録から写真を見返せなくなるので、ファイルは残す
        let archive = try #require(store.archives.first)
        #expect(archive.photoCount == 1)
        #expect(archive.photoFileNames.count == 1)
    }

    @Test("続けてもう一度リセットしても落ちない")
    func resetTwice() throws {
        playTurn(dice: 2)
        store.resetProgress()
        playTurn(dice: 2)
        store.resetProgress()

        #expect(store.archives.count == 2)
        #expect(store.lastError == nil)
    }

    @Test("何も歩いていなければ記録は増えない")
    func nothingToArchive() throws {
        store.resetProgress()

        #expect(store.archives.isEmpty)
        #expect(store.lastError == nil)
    }
}
