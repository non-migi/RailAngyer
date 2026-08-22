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

    /// 「11分30秒/km」のような表示。求められなければ nil。
    /// 単位は `DurationText.locale` の言葉になる
    public func text(locale: Locale = DurationText.locale) -> String? {
        guard let pace = minutesPerKilometer, pace.isFinite else { return nil }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        let amount = DurationText.units(minutes: minutes,
                                        seconds: seconds == 0 ? nil : seconds,
                                        locale: locale)
        return "\(amount)/km"
    }

    /// 既定の言語での表示（呼び出し側を変えずに済ませるための入口）
    public var text: String? { text() }

    /// 時速（km/h）
    public var kilometersPerHour: Double? {
        guard seconds > 0 else { return nil }
        return (meters / 1000) / (seconds / 3600)
    }
}

/// 時間の表示。集計と画面で同じ形にするためここにまとめる。
///
/// > ⚠️ **単位は訳文を持たず、`DateComponentsFormatter` に任せる。**
/// > ここは `RailAngyerCore`（GPS・DB非依存の計算だけを置く場所）で、
/// > 画面の文言と違って多言語化の仕組みが無い。かつて `秒` `分` `時間` を
/// > 直書きしていたため、**英語で開いても「Total 32秒」と出ていた**。
/// >
/// > アプリの中で選んだ言語（`AppLanguage`）は Core からは見えないので、
/// > `locale` に入れてもらう。入れなければ端末の言語で出る。
public enum DurationText {

    /// どの言葉で単位を出すか。**アプリ側が言語を変えたら入れ直す**
    /// （既定は端末の言語。入れ忘れても壊れない）
    nonisolated(unsafe) public static var locale: Locale = .autoupdatingCurrent

    /// 「1時間5分」「1 hr 5 min」など。言葉は `locale` に従う。
    ///
    /// **言語を渡せるようにしてある**のはテストのため。渡さなければ
    /// `DurationText.locale`（＝アプリで選んだ言語）で出る。
    /// テストが `locale` を書き換え合うと、並行して走る別のテストが巻き添えになる
    public static func text(_ seconds: TimeInterval,
                            locale: Locale = DurationText.locale) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return units(seconds: total, locale: locale) }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return units(hours: hours, minutes: minutes, locale: locale) }
        return units(minutes: minutes, locale: locale)
    }

    /// 数と単位を、その言語の言い方で並べる
    static func units(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil,
                      locale: Locale = DurationText.locale) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll

        var units: NSCalendar.Unit = []
        if hours != nil { units.insert(.hour) }
        if minutes != nil { units.insert(.minute) }
        if seconds != nil { units.insert(.second) }
        formatter.allowedUnits = units

        var components = DateComponents()
        components.hour = hours
        components.minute = minutes
        components.second = seconds
        // 0 は `dropAll` で消えるが、0 しか無いときは何も残らないので保険を置く
        return formatter.string(from: components).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "\(seconds ?? minutes ?? hours ?? 0)"
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
