import Foundation
import MapKit

/// これから歩く道のりを、**道路に沿った形**で取る。
///
/// 駅と駅を直線で結ぶと、川や線路を横切る線になって
/// 「そこは通れない」ことが地図から読み取れない。
/// 徒歩の経路を引いておけば、実際に歩ける道の形で見える。
///
/// - 取るのは**次に歩くところから順に少しずつ**。区間ぜんぶを一度に叩かない
///   （MapKit は続けて投げると絞られる。急ぐのは目の前の1区間だけ）
/// - **取れなくても進行を止めない。** 取れていないところは直線のまま描く
/// - 一度取った形は憶えておく。同じ区間を歩き直しても叩き直さない
@Observable
@MainActor
final class CourseRouteProvider {

    /// 駅と駅の間ひとつぶん。
    ///
    /// **コースを必ず含める。** 駅の通し番号はコースごとに1から振り直されるので、
    /// 番号だけを鍵にすると別の路線の道なりを取り違える
    /// （南北線の1→2の形が、東西線の1→2として出てしまう）
    struct LegKey: Hashable {
        let course: String
        let from: Int
        let to: Int
    }

    private(set) var routes: [LegKey: [CLLocationCoordinate2D]] = [:]
    /// 取りにいって取れなかったところ。何度も叩き直さない
    private var failed: Set<LegKey> = []
    private var isLoading = false

    /// 続けて投げるときの間合い。MapKit に絞られないようにする
    private static let pacing: Duration = .milliseconds(600)
    /// 一度に取りにいく上限。歩いているうちに続きを取る
    private static let batch = 6

    func coordinates(from: Int, to: Int, course: String) -> [CLLocationCoordinate2D]? {
        routes[LegKey(course: course, from: from, to: to)]
            ?? routes[LegKey(course: course, from: to, to: from)]?.reversed()
    }

    /// 憶えている形を捨てる。コースを変えたときに呼ぶ
    func reset() {
        routes = [:]
        failed = []
    }

    /// 並んだ駅の隣どうしについて、足りないぶんを取る。
    /// **手前から順に**取るので、いま歩いているところが先に埋まる
    func load(stations: [Station], course: String) async {
        guard !isLoading, stations.count >= 2 else { return }
        isLoading = true
        defer { isLoading = false }

        var fetched = 0
        for (from, to) in zip(stations, stations.dropFirst()) {
            let key = LegKey(course: course, from: from.orderNo, to: to.orderNo)
            if routes[key] != nil || failed.contains(key) { continue }
            if fetched >= Self.batch { return }

            fetched += 1
            if let line = await walkingRoute(from: from, to: to) {
                routes[key] = line
            } else {
                failed.insert(key)
            }
            try? await Task.sleep(for: Self.pacing)
        }
    }

    private func walkingRoute(from: Station, to: Station) async -> [CLLocationCoordinate2D]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
        request.transportType = .walking

        guard let route = try? await MKDirections(request: request).calculate().routes.first else {
            return nil
        }
        return route.polyline.coordinates
    }
}

extension MKPolyline {
    /// 線の座標を取り出す。`MapPolyline` へ渡すために要る
    var coordinates: [CLLocationCoordinate2D] {
        var points = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&points, range: NSRange(location: 0, length: pointCount))
        return points
    }
}
