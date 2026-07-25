import Foundation

/// 駅への到着を判定する条件（10_アプリ設計.md §6）。
///
/// CoreLocation に依存させないことで、測位を伴わずにテストできる。
/// 実際の距離計算は `CLLocation.distance(from:)` が行い、その結果をここへ渡す。
public struct ArrivalRule: Sendable, Equatable {

    /// 到着とみなす半径（メートル）。R-01。設定で変更できる
    public var radius: Double
    /// これより精度が悪い測位は使わない（メートル）。
    /// 誤差の大きい位置で誤到着させないための足切り
    public var accuracyLimit: Double

    public init(radius: Double = 150, accuracyLimit: Double = 100) {
        self.radius = radius
        self.accuracyLimit = accuracyLimit
    }

    /// 既定値
    public static let `default` = ArrivalRule()

    /// 半径として許される範囲。
    /// 上限は「最も近い駅間（南北線では 大通〜すすきの の約655m）の半分」を超えないこと。
    /// 超えると隣り合う駅の圏内が重なり、どちらに着いたか判定できなくなる。
    public static let radiusRange: ClosedRange<Double> = 50...320

    /// 測位が使えるか（精度が確保できているか）
    public func isUsable(horizontalAccuracy: Double) -> Bool {
        horizontalAccuracy > 0 && horizontalAccuracy <= accuracyLimit
    }

    /// 到着したとみなすか
    public func shouldArrive(distance: Double, horizontalAccuracy: Double) -> Bool {
        guard isUsable(horizontalAccuracy: horizontalAccuracy) else { return false }
        return distance <= radius
    }

    /// 隣り合う駅の圏内が重ならない半径か
    public func isSafe(forMinimumStationGap gap: Double) -> Bool {
        radius * 2 <= gap
    }
}
