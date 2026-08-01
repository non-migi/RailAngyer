import Foundation
import Testing
@testable import RailAngyerCore

/// 同梱した南北線マスタの検証。
/// 位置計算が壊れない条件と、公式データへ補正した代表座標を確かめる。
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

}

/// 追加したコース（フェーズ4）。
///
/// 座標はいずれも概値。**値そのものではなく、位置計算が壊れない条件**を確かめる。
/// 実地で補正するまでは、どのコースも自動到着が合わない駅が出うる。
struct AdditionalCourseTests {

    private static let courses: [(name: String, count: Int, terminals: (String, String))] = [
        ("東西線", 19, ("宮の沢", "新さっぽろ")),
        ("東豊線", 14, ("栄町", "福住")),
        ("山手線", 30, ("東京", "有楽町")),
        ("札幌市電", 24, ("西4丁目", "狸小路"))
    ]

    @Test("同梱しているコースは5本")
    func loadsAllCourses() throws {
        let all = try StationMaster.all()
        #expect(all.map(\.name) == ["南北線", "東西線", "東豊線", "山手線", "札幌市電"])
    }

    @Test("環状線は山手線と札幌市電")
    func loopCourses() throws {
        let loops = try StationMaster.all().filter(\.isLoop).map(\.name)
        #expect(loops == ["山手線", "札幌市電"])
    }

    @Test("環状線には、まわる向きの呼び名がある")
    func loopDirectionNames() throws {
        for course in try StationMaster.all() where course.isLoop {
            #expect(course.directionName(forward: true).isEmpty == false)
            #expect(course.directionName(forward: false).isEmpty == false)
            #expect(course.directionName(forward: true) != course.directionName(forward: false))
        }
    }

    @Test("環状線は、端どうしもつながっている")
    func loopClosesTheCircle() throws {
        for course in try StationMaster.all() where course.isLoop {
            let sorted = course.sortedStations
            let gap = distanceMeters(try #require(sorted.last), try #require(sorted.first))
            #expect(gap < 4000, "\(course.name) の終点と始点が離れすぎている: \(Int(gap))m")
        }
    }

    @Test("駅数と両端が定義どおり", arguments: courses)
    func stationCountAndTerminals(_ course: (name: String, count: Int, terminals: (String, String))) throws {
        let loaded = try #require(try StationMaster.all().first { $0.name == course.name })
        #expect(loaded.stations.count == course.count)
        #expect(loaded.station(orderNo: 1)?.name == course.terminals.0)
        #expect(loaded.station(orderNo: course.count)?.name == course.terminals.1)
    }

    @Test("OrderNo が連続していて駅名が重複しない")
    func orderNoAndNamesAreSound() throws {
        for course in try StationMaster.all() {
            let orders = course.sortedStations.map(\.orderNo)
            #expect(orders == Array(1...course.stations.count), "\(course.name) の OrderNo に欠番か重複がある")
            #expect(Set(course.stations.map(\.name)).count == course.stations.count,
                    "\(course.name) に同名の駅がある")
        }
    }

    @Test("隣り合う駅が、到着判定の圏内どうしで重ならない")
    func spacingIsPlausible() throws {
        for course in try StationMaster.all() {
            // 圏内が重なると、どちらに着いたのか決められなくなる。
            // 市電のように駅間が短い路線は、路線ごとに半径を小さくしてある
            let radius = course.arrivalRadius ?? ArrivalRule.default.radius
            let sorted = course.sortedStations
            for i in 0..<(sorted.count - 1) {
                let d = distanceMeters(sorted[i], sorted[i + 1])
                #expect(d > radius * 2,
                        "\(course.name) \(sorted[i].name)〜\(sorted[i+1].name) が近すぎる: \(Int(d))m（半径 \(Int(radius))m）")
                #expect(d < 4000,
                        "\(course.name) \(sorted[i].name)〜\(sorted[i+1].name) が遠すぎる: \(Int(d))m")
            }
        }
    }

    @Test("山手線は一周ぶんの長さになっている")
    func yamanoteIsRoughlyOneLap() throws {
        let course = try StationMaster.yamanote()
        let sorted = course.sortedStations
        var total: Double = 0
        for i in 0..<(sorted.count - 1) {
            total += distanceMeters(sorted[i], sorted[i + 1])
        }
        // 実際の営業キロは約34.5km。駅間の直線距離の合計なので、それより短くなる
        #expect((25_000.0...36_000.0).contains(total), "一周の長さが想定から外れている: \(Int(total))m")
    }
}

/// 2駅間の直線距離。座標の妥当性を測るためだけに使う（本番は CLLocation が計算する）
func distanceMeters(_ a: StationRef, _ b: StationRef) -> Double {
    let r = 6_371_000.0
    let dLat = (b.latitude - a.latitude) * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let lat1 = a.latitude * .pi / 180
    let lat2 = b.latitude * .pi / 180
    let h = sin(dLat / 2) * sin(dLat / 2)
        + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
    return 2 * r * asin(min(1, h.squareRoot()))
}
