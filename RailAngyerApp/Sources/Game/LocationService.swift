import Foundation
import CoreLocation
import RailAngyerCore

/// 位置情報の監視と到着判定（10_アプリ設計.md §6）。
///
/// 監視対象は常に1駅だけ（R-02）。先の駅の圏内に入っても到着にしない。
/// 到着したら `onArrive` を呼び、次の目標は呼び出し側が設定し直す。
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    /// 監視する駅
    struct Target: Equatable {
        let orderNo: Int
        let name: String
        let latitude: Double
        let longitude: Double

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    private let manager = CLLocationManager()
    private static let regionIdentifier = "railangyer.target"

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var target: Target?
    private(set) var lastLocation: CLLocation?
    /// 精度が足切りに満たない状態が続いているか（画面に注意を出すため）
    private(set) var accuracyIsPoor = false

    var rule: ArrivalRule = .default

    /// 到着したときに呼ばれる。引数は到着した駅の OrderNo
    var onArrive: ((Int) -> Void)?

    /// 位置が動くたびに呼ばれる。**歩いた跡を残すため**。
    /// 到着判定と分けてあるのは、跡は目標が無いときも残したいから
    var onMove: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20                 // 20m動くまで更新しない（電池対策）
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - 権限

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()   // 画面を見ずに歩くため
        default: break
        }
    }

    // MARK: - 監視

    /// 監視対象を切り替える。到着のたびに呼んで次の駅へ張り替える
    func watch(_ next: Target?) {
        guard next != target else { return }
        target = next

        stopRegionMonitoring()
        guard let next else {
            manager.stopUpdatingLocation()
            return
        }
        guard isAuthorized else { return }

        manager.startUpdatingLocation()
        startRegionMonitoring(next)
        // 既に圏内にいる場合に備えて、直近の位置で一度評価する
        if let location = lastLocation { evaluate(location) }
    }

    func stop() {
        target = nil
        stopRegionMonitoring()
        manager.stopUpdatingLocation()
    }

    /// 目標までの距離（メートル）。測位できていなければ nil
    var distanceToTarget: Double? {
        guard let target, let location = lastLocation else { return nil }
        return location.distance(from: target.location)
    }

    // MARK: - ジオフェンス
    //
    // 監視するのは常に1駅だけなので、同時監視の上限（20件）には掛からない。
    // 区間が20駅を超えても、この方式なら破綻しない。

    private func startRegionMonitoring(_ target: Target) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              authorizationStatus == .authorizedAlways else { return }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            radius: rule.radius,
            identifier: Self.regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    private func stopRegionMonitoring() {
        for region in manager.monitoredRegions where region.identifier == Self.regionIdentifier {
            manager.stopMonitoring(for: region)
        }
    }

    // MARK: - 判定

    private func evaluate(_ location: CLLocation) {
        guard let target else { return }

        accuracyIsPoor = !rule.isUsable(horizontalAccuracy: location.horizontalAccuracy)
        let distance = location.distance(from: target.location)

        guard rule.shouldArrive(distance: distance,
                                horizontalAccuracy: location.horizontalAccuracy) else { return }

        // 到着したら即座に監視を外す。
        // 150mの境界を出入りしても、同じ駅で二度目が発火しない（E-04 チャタリング対策）
        let arrived = target.orderNo
        self.target = nil
        stopRegionMonitoring()
        onArrive?(arrived)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized, let target { watchAgain(target) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        onMove?(location)
        evaluate(location)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionIdentifier else { return }
        // 画面を見ていない間の到着。最新の位置で判定し直す
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        accuracyIsPoor = true
    }

    /// 権限が下りた直後に監視を張り直す
    private func watchAgain(_ target: Target) {
        self.target = nil
        watch(target)
    }
}
