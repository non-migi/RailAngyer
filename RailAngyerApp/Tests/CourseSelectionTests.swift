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
    func listsBundledCourses() throws {
        // 名前の正は駅マスタ（`RailAngyerCore/Resources/*.json`）。
        // ここで書き写すと、コースを足すたびに関係のないテストが落ちる
        #expect(Set(store.courses.map(\.name)) == Set(try StationMaster.all().map(\.name)))
    }

    @Test("コースを変えると区間が新しいコースの両端になる")
    func switchingResetsRange() throws {
        #expect(store.updateCourse(try course("東西線")))

        #expect(store.room?.course?.name == "東西線")
        #expect(store.room?.startStation?.name == "宮の沢")
        #expect(store.room?.goalStation?.name == "新さっぽろ")
        #expect(store.engine?.stationCount == 19)
    }

    @Test("コースを変えると、そのコースのお題だけが一覧に出る")
    func switchingScopesMissionsToCourse() throws {
        store.saveMission(nil, station: 4, content: "南北線のお題",
                          effect: .none, value: nil, jumpTo: nil)
        #expect(store.myMissions.count == 1)

        _ = store.updateCourse(try course("東豊線"))

        // 新しいコースにはまだ何も書いていない。
        // 南北線のぶんは**消さずに残す**（予定のために用意したお題を失わないため）
        #expect(store.myMissions.isEmpty)
        #expect(store.myMissions(in: try course("南北線")).count == 1)
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
