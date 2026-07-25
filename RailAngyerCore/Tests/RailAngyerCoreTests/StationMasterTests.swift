import Foundation
import Testing
@testable import RailAngyerCore

/// 同梱した南北線マスタの検証。
/// 座標は概値のため値そのものは検証せず、**位置計算が壊れない条件**だけを確かめる。
struct StationMasterTests {

    @Test("南北線が16駅で読み込める")
    func loadsSixteenStations() throws {
        let course = try StationMaster.nanboku()
        #expect(course.name == "南北線")
        #expect(course.stations.count == 16)
    }

    @Test("OrderNo が 1〜16 で重複なく連続している")
    func orderNoIsContiguous() throws {
        let course = try StationMaster.nanboku()
        let orders = course.sortedStations.map(\.orderNo)
        #expect(orders == Array(1...16), "位置計算は OrderNo に依存するため、欠番や重複があると破綻する")
    }

    @Test("両端が麻生と真駒内")
    func terminals() throws {
        let course = try StationMaster.nanboku()
        #expect(course.station(orderNo: 1)?.name == "麻生")
        #expect(course.station(orderNo: 16)?.name == "真駒内")
    }

    @Test("駅名に重複がない")
    func namesAreUnique() throws {
        let course = try StationMaster.nanboku()
        #expect(Set(course.stations.map(\.name)).count == 16)
    }

    @Test("座標が札幌市内の妥当な範囲にある")
    func coordinatesAreInSapporo() throws {
        let course = try StationMaster.nanboku()
        for s in course.stations {
            #expect((42.9...43.2).contains(s.latitude), "\(s.name) の緯度が範囲外")
            #expect((141.2...141.5).contains(s.longitude), "\(s.name) の経度が範囲外")
        }
    }

    @Test("隣り合う駅が近すぎない・遠すぎない")
    func stationSpacingIsPlausible() throws {
        let course = try StationMaster.nanboku()
        let sorted = course.sortedStations
        for i in 0..<(sorted.count - 1) {
            let d = distanceMeters(sorted[i], sorted[i + 1])
            // 到着判定は半径150m。駅間が300m未満だと圏内が重なり判定が壊れる
            #expect(d > 300, "\(sorted[i].name)〜\(sorted[i+1].name) が近すぎる: \(Int(d))m")
            #expect(d < 4000, "\(sorted[i].name)〜\(sorted[i+1].name) が遠すぎる: \(Int(d))m")
        }
    }

    @Test("区間を指定すると、その範囲の駅だけが進む向きで返る")
    func sectionStations() throws {
        let course = try StationMaster.nanboku()
        let engine = GameEngine(startOrder: 6, goalOrder: 11, diceMax: 3)
        let names = course.stations(in: engine).map(\.name)
        #expect(names == ["さっぽろ", "大通", "すすきの", "中島公園", "幌平橋", "中の島"])

        let back = GameEngine(startOrder: 16, goalOrder: 14, diceMax: 6)
        #expect(course.stations(in: back).map(\.name) == ["真駒内", "自衛隊前", "澄川"])
    }

    /// ハーバサインによる概算距離（テスト用。実装では CLLocation.distance を使う）
    private func distanceMeters(_ a: StationRef, _ b: StationRef) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * r * asin(min(1, h.squareRoot()))
    }
}
