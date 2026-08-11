import Foundation
import MapKit

/// 次の駅までの徒歩経路を取得する（SC-07）。
///
/// MapKit で取れるのは**経路の線・実距離・所要時間・曲がり角の指示**まで。
/// 音声案内と自動リルートは作れないため、込み入った場所では
/// 「マップで経路を見る」で純正マップに渡す前提は変えない。
///
/// 取得は通信が要る。**失敗しても進行を止めない**（直線距離の表示に落ちる）。
@Observable
@MainActor
final class RouteProvider {

    private(set) var route: MKRoute?
    private(set) var isLoading = false
    private(set) var didFail = false

    /// いま経路を持っている行き先。区間が変わったら取り直す。
    ///
    /// **駅の通し番号だけでは足りない。** 番号はコースごとに1から振られるので、
    /// 別のコースへ移ると同じ番号が違う場所を指す。座標まで見て取り直す
    private struct Destination: Equatable {
        let orderNo: Int
        let latitude: Double
        let longitude: Double

        init(_ target: LocationService.Target) {
            orderNo = target.orderNo
            latitude = target.latitude
            longitude = target.longitude
        }
    }

    private var loadedFor: Destination?
    /// 経路を取ったときの出発地点。ここから離れたら取り直す
    private var origin: CLLocation?

    /// 出発地点からこれだけ離れたら経路を取り直す
    private static let refreshDistance: CLLocationDistance = 400

    var distanceText: String? {
        guard let route else { return nil }
        return route.distance >= 1000
            ? String(format: "徒歩 約 %.1f km", route.distance / 1000)
            : String(format: "徒歩 約 %.0f m", route.distance)
    }

    var durationText: String? {
        guard let route else { return nil }
        let minutes = max(1, Int(route.expectedTravelTime / 60))
        return "約 \(minutes) 分"
    }

    /// 最初の曲がり角の指示（あれば）
    var firstInstruction: String? {
        route?.steps.first(where: { !$0.instructions.isEmpty })?.instructions
    }

    /// 必要なら経路を取る。すでに持っていて出発地点も近ければ何もしない
    func ensureRoute(from current: CLLocation?, to target: LocationService.Target) async {
        guard let current else { return }
        if loadedFor == Destination(target), let origin,
           current.distance(from: origin) < Self.refreshDistance {
            return
        }
        guard !isLoading else { return }

        isLoading = true
        didFail = false
        defer { isLoading = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            route = response.routes.first
            loadedFor = Destination(target)
            origin = current
        } catch {
            // 圏外・地下などで取れないことがある。直線距離の表示で進行を続ける
            route = nil
            loadedFor = nil
            didFail = true
        }
    }

    func clear() {
        route = nil
        loadedFor = nil
        origin = nil
        didFail = false
    }
}
