import Testing
@testable import RailAngyerCore

/// 10_アプリ設計.md §4「テストで必ず確認すること」の12ケース。
/// GPS もDBも使わないため、実機・シミュレータなしで実行できる。
struct GameEngineTests {

    /// 南北線を全線通し（麻生1 → 真駒内16）、最大出目6
    let full = GameEngine(startOrder: 1, goalOrder: 16, diceMax: 6)
    /// 逆走コース（真駒内16 → 麻生1）
    let reverse = GameEngine(startOrder: 16, goalOrder: 1, diceMax: 6)
    /// 一部区間（さっぽろ6 → 中の島11）、最大出目3
    let section = GameEngine(startOrder: 6, goalOrder: 11, diceMax: 3)

    // MARK: - 着地駅の算出

    @Test("1. 通常の移動：現在6・出目3 → 着地9")
    func normalMove() {
        #expect(full.landingOrder(from: 6, dice: 3) == 9)
    }

    @Test("2. 出目の超過：現在12・出目5 → ゴール16で止まる")
    func overshootStopsAtGoal() {
        #expect(full.landingOrder(from: 12, dice: 5) == 16)
    }

    @Test("3. 逆走コース：現在12・出目3 → 着地9")
    func reverseMove() {
        #expect(reverse.direction == -1)
        #expect(reverse.landingOrder(from: 12, dice: 3) == 9)
    }

    @Test("4. 逆走の超過：現在3・出目5 → ゴール1で止まる")
    func reverseOvershoot() {
        #expect(reverse.landingOrder(from: 3, dice: 5) == 1)
    }

    @Test("5. 区間の超過：区間6〜11・現在10・出目3 → 11で止まる")
    func sectionOvershoot() {
        #expect(section.landingOrder(from: 10, dice: 3) == 11)
    }

    // MARK: - 効果の適用

    @Test("6. 戻る3：着地10 → 終了7")
    func effectBack() {
        #expect(section.endOrder(landing: 10, effect: .back, value: 3) == 7)
    }

    @Test("7. 戻るのクランプ：着地7で戻る5 → スタート6で止まる")
    func effectBackClampedAtStart() {
        #expect(section.endOrder(landing: 7, effect: .back, value: 5) == 6)
    }

    @Test("8. 進むのクランプ：着地9で進む4 → ゴール11で止まる")
    func effectForwardClampedAtGoal() {
        #expect(section.endOrder(landing: 9, effect: .forward, value: 4) == 11)
    }

    @Test("9. 区間外へのジャンプは無効：区間6〜11で3へ飛ぶ → 移動しない")
    func jumpOutsideRangeIsIgnored() {
        #expect(section.endOrder(landing: 9, effect: .jump, jumpTo: 3) == 9)
        #expect(section.endOrder(landing: 9, effect: .jump, jumpTo: 7) == 7)
    }

    @Test("効果なし・もう一度振る は位置を変えない")
    func nonMovingEffects() {
        #expect(section.endOrder(landing: 8, effect: .none) == 8)
        #expect(section.endOrder(landing: 8, effect: .rollAgain) == 8)
    }

    // MARK: - 通り道

    @Test("10. 通り道：6→9 は [7,8,9]")
    func pathForward() {
        #expect(full.path(from: 6, to: 9) == [7, 8, 9])
    }

    @Test("11. 逆走の通り道：12→9 は [11,10,9]")
    func pathReverse() {
        #expect(reverse.path(from: 12, to: 9) == [11, 10, 9])
    }

    @Test("同じ駅なら通り道は空")
    func pathSameStation() {
        #expect(full.path(from: 6, to: 6).isEmpty)
    }

    // MARK: - サイコロ

    @Test("12. 最大出目1なら必ず1が出る")
    func diceMaxOne() {
        let engine = GameEngine(startOrder: 1, goalOrder: 16, diceMax: 1)
        for _ in 0..<100 { #expect(engine.roll() == 1) }
    }

    @Test("出目は 1...diceMax の範囲に収まる", arguments: [1, 3, 6, 9])
    func diceRange(max: Int) {
        let engine = GameEngine(startOrder: 1, goalOrder: 16, diceMax: max)
        for _ in 0..<200 {
            let v = engine.roll()
            #expect(v >= 1 && v <= max)
        }
    }

    // MARK: - 区間

    @Test("範囲外の最大出目は丸める（保存データから作るため落とさない）")
    func diceMaxIsClamped() {
        #expect(GameEngine(startOrder: 1, goalOrder: 16, diceMax: 0).diceMax == 1)
        #expect(GameEngine(startOrder: 1, goalOrder: 16, diceMax: 99).diceMax == 9)
        #expect(GameEngine(startOrder: 1, goalOrder: 16, diceMax: -5).diceMax == 1)
        // 丸めたあとも出目は必ずその範囲に収まる
        let engine = GameEngine(startOrder: 1, goalOrder: 16, diceMax: 99)
        for _ in 0..<100 { #expect((1...9).contains(engine.roll())) }
    }

    @Test("区間の駅数と並び")
    func rangeProperties() {
        #expect(full.stationCount == 16)
        #expect(section.stationCount == 6)
        #expect(section.orderedRange == [6, 7, 8, 9, 10, 11])
        #expect(reverse.orderedRange.first == 16)
        #expect(reverse.orderedRange.last == 1)
    }

    @Test("クリア判定はゴール到達のみ")
    func clearDetection() {
        #expect(full.isCleared(16))
        #expect(!full.isCleared(15))
        #expect(reverse.isCleared(1))
        #expect(section.isCleared(11))
    }

    // MARK: - ターンの計画

    @Test("ターンの計画：通り道と着地が分かれる")
    func turnPlan() {
        let plan = full.plan(from: 6, dice: 3)
        #expect(plan.landing == 9)
        #expect(plan.passing == [7, 8])
        #expect(plan.allStops == [7, 8, 9])
        #expect(!plan.reachesGoal)
    }

    @Test("出目1のときは通り道がなく、着地のみ")
    func turnPlanSingleStep() {
        let plan = full.plan(from: 6, dice: 1)
        #expect(plan.passing.isEmpty)
        #expect(plan.allStops == [7])
    }

    @Test("旅の1ターン目：スタート駅は数に入れず、出目1なら隣駅で止まる")
    func firstTurnFromStart() {
        let first = full.plan(from: full.startOrder, dice: 1)
        #expect(first.landing == 2, "スタート（1）から出目1で隣の2へ")
        #expect(first.passing.isEmpty)
        #expect(first.allStops == [2])

        // 出目のぶんだけ、いま立っている駅の次から1駅ずつ数える
        #expect(full.plan(from: full.startOrder, dice: 3).allStops == [2, 3, 4])
    }

    @Test("ゴールに届くターンは reachesGoal が真")
    func turnPlanReachesGoal() {
        let plan = full.plan(from: 12, dice: 5)
        #expect(plan.landing == 16)
        #expect(plan.passing == [13, 14, 15])
        #expect(plan.reachesGoal)
    }

    // MARK: - 進行の通し

    @Test("区間6〜11を最大出目3で進めると、必ずゴールに到達して終わる")
    func fullPlaythroughTerminates() {
        var current = section.startOrder
        var turns = 0
        var visited: [Int] = [current]
        while !section.isCleared(current) {
            let plan = section.plan(from: current, dice: section.roll())
            visited.append(contentsOf: plan.allStops)
            current = plan.landing
            turns += 1
            #expect(turns < 100, "無限ループになっている")
        }
        #expect(current == 11)
        // 通り道を含め、区間内の全駅を必ず踏む
        #expect(Set(visited) == Set(6...11))
    }
}
