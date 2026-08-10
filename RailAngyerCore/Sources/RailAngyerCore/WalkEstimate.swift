import Foundation

/// 緯度経度を持つもの。駅マスタ（`StationRef`）でもアプリの `Station` でも同じ計算を使うための入口。
public protocol GeoPoint {
    var latitude: Double { get }
    var longitude: Double { get }
}

extension StationRef: GeoPoint {}

/// 区間を歩いたときの目安（距離と時間）。
///
/// **実測ではなく見積もり。** 予定を立てる段で「半日で終わるのか、丸一日かかるのか」を
/// 決められれば足りるため、経路探索（通信が要る・区間の駅数ぶん叩くことになる）はしない。
public struct WalkEstimate: Sendable, Equatable {

    /// 駅と駅を直線で結んだ合計（メートル）
    public let straightMeters: Double
    /// 実際に歩く距離の目安（メートル）。直線に迂回のぶんを掛けたもの
    public let meters: Double
    /// 歩く時間の目安（秒）。休憩とお題の時間は含まない
    public let seconds: TimeInterval
    /// 区間に含まれる駅の数
    public let stationCount: Int

    public init(straightMeters: Double, meters: Double,
                seconds: TimeInterval, stationCount: Int) {
        self.straightMeters = straightMeters
        self.meters = meters
        self.seconds = seconds
        self.stationCount = stationCount
    }

    public var kilometers: Double { meters / 1000 }

    /// 「約 14.2 km」。1km未満は m で出す
    public var distanceText: String {
        meters >= 1000
            ? String(format: "約 %.1f km", kilometers)
            : String(format: "約 %.0f m", meters)
    }

    /// 「約 3時間5分」
    public var durationText: String { "約 " + DurationText.text(seconds) }

    /// 一行にまとめた表示
    public var summaryText: String { "\(distanceText)　\(durationText)" }
}

/// 区間の距離と時間を見積もる。
public enum WalkEstimator {

    /// 直線距離に掛ける迂回の係数。
    ///
    /// 道は駅を直線では結ばない。市街地の徒歩では実距離が直線の 1.2〜1.4 倍になるため、
    /// 中ほどの **1.3** を採る。`Pace` の注記（直線で測るぶん実際よりやや遅く出る）と同じ考え方。
    public static let detourFactor: Double = 1.3

    /// 歩く速さ（分/km）。`PaceCategory` の「ふつう」の中央にあたる時速5km
    public static let minutesPerKilometer: Double = 12

    /// 並んだ地点を順に歩いたときの目安。地点が1つ以下なら距離ゼロ
    public static func estimate(points: [GeoPoint]) -> WalkEstimate {
        var straight: Double = 0
        for i in 0..<max(0, points.count - 1) {
            straight += Geo.distanceMeters(lat1: points[i].latitude, lon1: points[i].longitude,
                                           lat2: points[i + 1].latitude, lon2: points[i + 1].longitude)
        }
        let meters = straight * detourFactor
        return WalkEstimate(straightMeters: straight,
                            meters: meters,
                            seconds: (meters / 1000) * minutesPerKilometer * 60,
                            stationCount: points.count)
    }

    /// コースの区間の目安。`from` と `to` はどちらが大きくてもよい
    public static func estimate(course: CourseRef, from: Int, to: Int) -> WalkEstimate {
        let range = min(from, to)...max(from, to)
        let stations = course.sortedStations.filter { range.contains($0.orderNo) }
        return estimate(points: stations)
    }

    /// 環状線を一周したときの目安。**出発した駅へ戻るぶんまで含める**
    public static func estimateLap(course: CourseRef) -> WalkEstimate {
        let stations = course.sortedStations
        guard course.isLoop, let first = stations.first else { return estimate(points: stations) }
        return estimate(points: stations + [first])
    }
}
