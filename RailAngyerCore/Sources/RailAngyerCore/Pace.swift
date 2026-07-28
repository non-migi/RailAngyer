import Foundation

/// 2点間の距離。
///
/// 実プレイの到着判定は `CLLocation.distance(from:)` が行うが、
/// **記録の集計は測位を伴わない**（保存済みの駅座標から後で計算する）ため、
/// ここに置いて CoreLocation なしでテストできるようにする。
public enum Geo {

    /// ハーバサインによる大円距離（メートル）
    public static func distanceMeters(lat1: Double, lon1: Double,
                                      lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a1 = lat1 * .pi / 180
        let a2 = lat2 * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2)
              + sin(dLon / 2) * sin(dLon / 2) * cos(a1) * cos(a2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }
}

/// 歩く速さの区分。地図の色分けと表示に使う。
///
/// **駅間の直線距離で測る。** 実際に歩いた経路より短く出るため、
/// 表示される「分/km」は実際のペースよりやや遅めに（数字が大きめに）出る。
/// 速さの目安として使うぶんには支障がなく、経路を記録し続けるより電池に優しい。
public enum PaceCategory: String, Sendable, CaseIterable {
    /// 速い（10分/km 未満）。競歩に近い
    case fast
    /// ふつう（10〜14分/km）。徒歩の平均は約12分/km（時速5km）
    case normal
    /// ゆっくり（14分/km 超）。寄り道や信号待ちが多いとここに入る
    case slow

    public var label: String {
        switch self {
        case .fast:   return "速い"
        case .normal: return "ふつう"
        case .slow:   return "ゆっくり"
        }
    }

    /// 区切りとなる分/km
    public static let fastThreshold: Double = 10
    public static let slowThreshold: Double = 14

    public init(minutesPerKilometer: Double) {
        switch minutesPerKilometer {
        case ..<Self.fastThreshold:  self = .fast
        case ..<Self.slowThreshold:  self = .normal
        default:                     self = .slow
        }
    }
}

/// 移動1区間ぶんの速さ。
public struct Pace: Sendable, Equatable {

    public let meters: Double
    public let seconds: TimeInterval

    public init(meters: Double, seconds: TimeInterval) {
        self.meters = meters
        self.seconds = seconds
    }

    /// 分/km。距離か時間が0以下なら求められない
    public var minutesPerKilometer: Double? {
        guard meters > 0, seconds > 0 else { return nil }
        return (seconds / 60) / (meters / 1000)
    }

    public var category: PaceCategory? {
        minutesPerKilometer.map(PaceCategory.init(minutesPerKilometer:))
    }

    /// 「11分30秒/km」のような表示。求められなければ nil
    public var text: String? {
        guard let pace = minutesPerKilometer, pace.isFinite else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return seconds == 0 ? "\(minutes)分/km" : "\(minutes)分\(seconds)秒/km"
    }

    /// 時速（km/h）
    public var kilometersPerHour: Double? {
        guard seconds > 0 else { return nil }
        return (meters / 1000) / (seconds / 3600)
    }
}

/// 時間の表示。集計と画面で同じ形にするためここにまとめる
public enum DurationText {

    /// 「1時間5分」「12分」「45秒」
    public static func text(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)秒" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)時間\(minutes)分" }
        return "\(minutes)分"
    }

    /// 「1:05:30」。細かく見たいときに使う
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
