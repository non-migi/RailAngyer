import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// コースの切り替え（フェーズ4）。
///
/// **区間とお題はコースに紐づく。** 切り替えたときに前のコースのものが残ると、
/// 区間の外を指す設定や、絶対に引けないお題が残って進行が壊れる。
@MainActor
struct CourseSelectionTests {

    private let context: ModelContext
    private let store: GameSessionStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    private func course(_ name: String) throws -> Course {
        try #require(store.courses.first { $0.name == name })
    }

    @Test("同梱コースが選べる")
    func listsBundledCourses() {
        #expect(Set(store.courses.map(\.name)) == ["南北線", "東西線", "東豊線", "山手線"])
    }

    @Test("コースを変えると区間が新しいコースの両端になる")
    func switchingResetsRange() throws {
        #expect(store.updateCourse(try course("東西線")))

        #expect(store.room?.course?.name == "東西線")
        #expect(store.room?.startStation?.name == "宮の沢")
        #expect(store.room?.goalStation?.name == "新さっぽろ")
        #expect(store.engine?.stationCount == 19)
    }

    @Test("前のコースに書いたお題は消える")
    func switchingDropsMissionsOfOldCourse() throws {
        store.saveMission(nil, station: 4, content: "南北線のお題",
                          effect: .none, value: nil, jumpTo: nil)
        #expect(store.myMissions.count == 1)

        _ = store.updateCourse(try course("東豊線"))

        // 引けないお題が残ると、抽選の候補が合わなくなる
        #expect(store.myMissions.isEmpty)
    }

    @Test("プレイを始めたらコースは変えられない")
    func lockedAfterFirstRoll() throws {
        store.roll(dice: 1)

        #expect(!store.updateCourse(try course("東西線")))
        #expect(store.room?.course?.name == "南北線")
    }

    @Test("山手線は東京から有楽町までの直線として扱う")
    func yamanoteIsLinear() throws {
        #expect(store.updateCourse(try course("山手線")))

        // 環状として一周させるにはルール計算の作り直しが要る（StationMaster に明記）
        #expect(store.room?.startStation?.name == "東京")
        #expect(store.room?.goalStation?.name == "有楽町")
        #expect(store.engine?.stationCount == 30)
    }

    @Test("切り替えた先のコースでも1ターン進める")
    func canPlayAfterSwitching() throws {
        _ = store.updateCourse(try course("東豊線"))

        store.roll(dice: 2)
        for _ in 0..<10 {
            guard case .walking = store.phase else { break }
            store.arriveAtNextStop()
            if case .arrivedPassing = store.phase { store.continueWalking() }
        }

        #expect(store.activeTurn?.landingStation?.name == "元町")   // 栄町から2駅
    }
}
