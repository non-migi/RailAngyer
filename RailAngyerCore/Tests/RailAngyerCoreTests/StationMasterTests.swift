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
        ("札幌市電", 24, ("西4丁目", "狸小路")),
        ("阪急京都本線", 28, ("大阪梅田", "京都河原町"))
    ]

    @Test("同梱しているコースは11本")
    func loadsAllCourses() throws {
        let all = try StationMaster.all()
        #expect(all.map(\.name) == ["南北線", "東西線", "東豊線", "山手線", "札幌市電",
                                    "阪急京都本線", "ベルリン Ringbahn", "ロンドン サークル線",
                                    "モスクワ 環状線", "モスクワ 大環状線", "北京地下鉄10号線"])
    }

    @Test("どのコースも国と地方を持っている")
    func everyCourseHasRegion() throws {
        for course in try StationMaster.all() {
            #expect(!course.country.isEmpty, "\(course.name) に国が無い")
            // ISO 3166-1 alpha-2。**日本とは限らない**（ベルリン=DE、ロンドン=GB）
            #expect(course.countryCode.count == 2, "\(course.name) の国コードが変")
            #expect(!course.regions.isEmpty, "\(course.name) に地方が無い")
        }
    }

    // MARK: - 日本の外のコース
    //
    // **一周できる遊び方はどこでも成り立つ。** 山手線でやっていることが
    // ベルリンとロンドンにもある（内回り／外回りにあたる呼び分けまで実在する）

    @Test("ベルリン Ringbahn が一周として読める")
    func berlinRingbahn() throws {
        let course = try StationMaster.berlinRingbahn()

        #expect(course.stations.count == 27)
        #expect(course.isLoop)
        #expect(course.countryCode == "DE")
        #expect(course.stations.first?.name == "Gesundbrunnen")
        // S41/S42 が内回り・外回りにあたる。**実在の呼び分けをそのまま使う**
        #expect(course.directionName(forward: true).contains("S41"))
        #expect(course.directionName(forward: false).contains("S42"))
    }

    @Test("ベルリン Ringbahn の長さが営業キロと合う")
    func berlinRingbahnLength() throws {
        let course = try StationMaster.berlinRingbahn()

        // 営業キロ37.5km。直線で結ぶので少し短く出る
        let meters = WalkEstimator.estimateLap(course: course).straightMeters
        #expect(meters > 33_000 && meters < 39_000, "\(meters)")
    }

    @Test("ロンドン サークル線が一周として読める")
    func londonCircle() throws {
        let course = try StationMaster.londonCircle()

        // 2009年からの運行は「らせん」だが、環になっている元のInner Circleだけを扱う
        #expect(course.stations.count == 27)
        #expect(course.isLoop)
        #expect(course.countryCode == "GB")
        // 駅間が短いので半径を詰めてある
        #expect(course.arrivalRadius == 110)
    }

    @Test("ロンドン サークル線の長さが Inner Circle と合う")
    func londonCircleLength() throws {
        let course = try StationMaster.londonCircle()

        // Inner Circle は約21km
        let meters = WalkEstimator.estimateLap(course: course).straightMeters
        #expect(meters > 18_000 && meters < 23_000, "\(meters)")
    }

    @Test("日本の外のコースも駅の並びが飛ばない")
    func overseasCoursesAreSmooth() throws {
        for course in [try StationMaster.berlinRingbahn(), try StationMaster.londonCircle(),
                       try StationMaster.moscowKoltsevaya(), try StationMaster.moscowBolshaya(),
                       try StationMaster.beijingLine10()] {
            let sorted = course.stations.sorted { $0.orderNo < $1.orderNo }
            #expect(sorted.map(\.orderNo) == Array(1...sorted.count))

            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let d = Geo.distanceMeters(lat1: a.latitude, lon1: a.longitude,
                                           lat2: b.latitude, lon2: b.longitude)
                // 並び順が狂うと、離れた駅どうしが隣になって一目で分かる
                #expect(d < 4000, "\(course.name) \(a.name)〜\(b.name) が \(Int(d))m")
                #expect(d > 100, "\(course.name) \(a.name)〜\(b.name) が近すぎる")
            }
        }
    }

    @Test("日本のコースは国コードがJP")
    func japaneseCoursesAreJP() throws {
        let japanese = ["南北線", "東西線", "東豊線", "山手線", "札幌市電", "阪急京都本線"]
        for course in try StationMaster.all() where japanese.contains(course.name) {
            #expect(course.country == "日本")
            #expect(course.countryCode == "JP")
        }
    }

    @Test("都道府県をまたぐ路線は、通る県をすべて持つ")
    func crossingCourseHasEveryRegion() throws {
        let hankyu = try StationMaster.hankyuKyoto()
        #expect(hankyu.regions == ["大阪府", "京都府"])
        #expect(try StationMaster.yamanote().regions == ["東京都"])
        #expect(try StationMaster.nanboku().regions == ["北海道"])
    }

    @Test("阪急京都本線が大阪〜京都の範囲に収まっている")
    func hankyuCoordinates() throws {
        let course = try StationMaster.hankyuKyoto()
        for s in course.stations {
            #expect((34.6...35.1).contains(s.latitude), "\(s.name) の緯度が範囲外")
            #expect((135.3...135.9).contains(s.longitude), "\(s.name) の経度が範囲外")
        }
    }

    @Test("阪急京都本線の長さが営業キロと合う")
    func hankyuLength() throws {
        let sorted = try StationMaster.hankyuKyoto().sortedStations
        var total: Double = 0
        for i in 0..<(sorted.count - 1) {
            total += distanceMeters(sorted[i], sorted[i + 1])
        }
        // 営業キロは47.7km。直線距離の合計なので、それより少し短くなる
        #expect((44_000.0...48_000.0).contains(total), "全長が想定から外れている: \(Int(total))m")
    }

    @Test("環状線は山手線と札幌市電")
    func loopCourses() throws {
        let loops = try StationMaster.all().filter(\.isLoop).map(\.name)
        // 環状は日本の外にもある。**一周できる遊び方はどこでも成り立つ**
        #expect(loops == ["山手線", "札幌市電", "ベルリン Ringbahn", "ロンドン サークル線",
                          "モスクワ 環状線", "モスクワ 大環状線", "北京地下鉄10号線"])
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
                // 上限は徒歩1時間ぶん。郊外を走る路線には長い駅間がある
                // （阪急京都本線 高槻市〜上牧は約4.3km＝およそ1時間の徒歩）
                #expect(d < 5000,
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
