import Testing
import SwiftData
import Foundation
@testable import RailAngyerApp
@testable import RailAngyerCore

/// 消えた行を掴んだままの参照（TestFlight のクラッシュ報告 2026-08-01）。
///
/// SwiftData は**消えた行の属性を読んだ瞬間に落ちる**（`_InvalidFutureBackingData`）。
/// 実際に落ちたのは、引いたお題が消えているターンを開いたときの
/// `missionCandidates` で、`selectedMission?.id` を読んだところだった。
///
/// ここでは同じ壊れ方を作って、**起動時に直ること**と、
/// **直る前に読んでも落ちないこと**を確かめる。
@MainActor
struct DanglingReferenceTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let store: GameSessionStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(AppSchema.all), configurations: config)
        context = ModelContext(container)
        store = GameSessionStore(context: context)
        store.prepare(sampleMissions: false)
    }

    /// お題を引いた状態で1ターン進め、そのお題だけを直接消す
    /// （ビルド2の「コースを変えると他コースのお題を消す」と同じ壊し方）
    @discardableResult
    private func breakSelectedMission() throws -> Turn {
        store.saveMission(nil, station: 2, content: "消えるお題",
                          effect: .none, value: nil, jumpTo: nil)
        store.roll(dice: 1)
        while case .walking = store.phase { store.arriveAtNextStop() }
        store.drawMission()

        let turn = try #require(store.activeTurn)
        let mission = try #require(turn.selectedMission)
        #expect(mission.content == "消えるお題")

        context.delete(mission)          // 参照を外さずに消す（これが不具合の作り方）
        try context.save()
        return turn
    }

    @Test("消えたお題を掴んだままでも、候補の計算で落ちない")
    func missionCandidatesSurvivesDanglingReference() throws {
        try breakSelectedMission()

        // 落ちたのはここ。属性ではなく persistentModelID で突き合わせるようにした
        _ = store.missionCandidates(at: 2)
        _ = store.phase
    }

    @Test("起動時に、消えたお題への参照が外れる")
    func prepareRepairsDanglingMission() throws {
        try breakSelectedMission()

        // 起動し直しに相当（同じ保存領域を、別のコンテキストから読む）
        let reopenedContext = ModelContext(container)
        let reopened = GameSessionStore(context: reopenedContext)
        reopened.prepare(sampleMissions: false)

        #expect(reopened.repairedReferenceCount >= 1)
        #expect(reopened.lastError == nil)

        // 読み直したターンから参照が外れている（元のコンテキストの控えは見ない）
        let turns = try reopenedContext.fetch(FetchDescriptor<Turn>())
        #expect(turns.allSatisfy { $0.selectedMission == nil })
    }

    @Test("お題を消すと、掴んでいたターンの参照がその場で外れる")
    func deleteMissionClearsReference() throws {
        store.saveMission(nil, station: 2, content: "消すお題",
                          effect: .none, value: nil, jumpTo: nil)
        store.roll(dice: 1)
        while case .walking = store.phase { store.arriveAtNextStop() }
        store.drawMission()
        let turn = try #require(store.activeTurn)
        #expect(turn.selectedMission != nil)

        store.deleteMission(try #require(store.myMissions.first))

        #expect(turn.selectedMission == nil)
        _ = store.missionCandidates(at: 2)     // 続けて読んでも落ちない
    }

    @Test("ターンが消えた訪問は、起動時に片づけられる")
    func prepareRemovesOrphanVisits() throws {
        store.roll(dice: 2)
        while case .walking = store.phase { store.arriveAtNextStop() }
        let turn = try #require(store.activeTurn)
        let visitCount = try context.fetch(FetchDescriptor<Visit>()).count
        #expect(visitCount > 1)

        context.delete(turn)                   // 訪問の参照を外さずにターンだけ消す
        try context.save()

        let reopenedContext = ModelContext(container)
        let reopened = GameSessionStore(context: reopenedContext)
        reopened.prepare(sampleMissions: false)

        // 消えたターンを指したままの訪問が残っていないこと。
        // なお**メモリ上のストアでは SwiftData がその場で参照を外す**ため、
        // 直す対象は0件になる。実際に壊れるのは、保存済みのストアを開き直したとき
        #expect(reopened.lastError == nil)
        let remaining = try reopenedContext.fetch(FetchDescriptor<Visit>())
        #expect(remaining.allSatisfy { $0.turn == nil })
    }

    @Test("壊れていなければ、何も直さない")
    func prepareLeavesHealthyStoreAlone() throws {
        store.saveMission(nil, station: 2, content: "残るお題",
                          effect: .none, value: nil, jumpTo: nil)
        store.roll(dice: 1)
        while case .walking = store.phase { store.arriveAtNextStop() }
        store.drawMission()

        let reopened = GameSessionStore(context: ModelContext(container))
        reopened.prepare(sampleMissions: false)

        #expect(reopened.repairedReferenceCount == 0)
        #expect(reopened.activeTurn?.selectedMission?.content == "残るお題")
    }
}
