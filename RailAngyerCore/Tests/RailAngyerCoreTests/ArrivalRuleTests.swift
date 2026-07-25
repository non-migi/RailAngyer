import Testing
@testable import RailAngyerCore

/// 到着判定の条件（10_アプリ設計.md §6.1 / §6.2）
struct ArrivalRuleTests {

    let rule = ArrivalRule.default   // 半径150m / 精度100m

    @Test("圏内かつ精度が良ければ到着")
    func arrivesInsideRadius() {
        #expect(rule.shouldArrive(distance: 10, horizontalAccuracy: 5))
        #expect(rule.shouldArrive(distance: 149.9, horizontalAccuracy: 20))
        #expect(rule.shouldArrive(distance: 150, horizontalAccuracy: 20), "境界は到着に含む")
    }

    @Test("圏外なら到着しない")
    func doesNotArriveOutsideRadius() {
        #expect(!rule.shouldArrive(distance: 151, horizontalAccuracy: 5))
        #expect(!rule.shouldArrive(distance: 900, horizontalAccuracy: 5))
    }

    @Test("精度が悪い測位では到着させない")
    func rejectsPoorAccuracy() {
        #expect(!rule.shouldArrive(distance: 10, horizontalAccuracy: 101),
                "誤差101mでは、10m地点にいるという情報を信用できない")
        #expect(!rule.shouldArrive(distance: 10, horizontalAccuracy: 500))
    }

    @Test("精度が負の値なら測位失敗として扱う")
    func rejectsInvalidAccuracy() {
        #expect(!rule.isUsable(horizontalAccuracy: -1))
        #expect(!rule.shouldArrive(distance: 0, horizontalAccuracy: -1))
    }

    @Test("半径を変えれば判定も変わる")
    func customRadius() {
        let tight = ArrivalRule(radius: 50)
        #expect(!tight.shouldArrive(distance: 100, horizontalAccuracy: 10))
        #expect(tight.shouldArrive(distance: 40, horizontalAccuracy: 10))
    }

    @Test("南北線の最短駅間（約655m）で圏内が重ならない半径か")
    func radiusDoesNotOverlapNeighbours() {
        let minimumGap = 655.0   // 大通〜すすきの
        #expect(ArrivalRule(radius: 150).isSafe(forMinimumStationGap: minimumGap))
        #expect(ArrivalRule(radius: 320).isSafe(forMinimumStationGap: minimumGap))
        #expect(!ArrivalRule(radius: 400).isSafe(forMinimumStationGap: minimumGap),
                "半径400mでは隣の駅の圏内と重なる")
        #expect(ArrivalRule.radiusRange.upperBound * 2 <= minimumGap,
                "設定で選べる上限は、重ならない範囲に収めてある")
    }
}
