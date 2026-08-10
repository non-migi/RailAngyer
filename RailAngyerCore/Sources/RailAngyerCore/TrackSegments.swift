import Foundation

/// 歩いた跡を、**決まった長さごとに区切って**速さを出す。
///
/// 駅と駅の間ひとまとまりで色を塗ると、
/// 「途中の坂で失速した」「商店街で寄り道した」といった中の起伏が消えてしまう。
/// 一定の距離ごとに刻めば、同じ駅間でも速いところと遅いところが色で分かる。
///
/// 距離で刻む（時間ではない）のは、**地図の上で等しい長さになる**ため。
/// 時間で刻むと、止まっている間だけ点が濃くなって線が団子になる。
public enum TrackSegments {

    /// 位置と時刻の組。アプリの `TrackPoint` も駅マスタも同じ形で渡せる
    public struct Fix: Sendable {
        public let latitude: Double
        public let longitude: Double
        public let time: Date

        public init(latitude: Double, longitude: Double, time: Date) {
            self.latitude = latitude
            self.longitude = longitude
            self.time = time
        }
    }

    /// 刻んだ一本ぶん
    public struct Segment: Sendable, Identifiable {
        public let id: Int
        /// この区切りを通る点（線を引くのに使う。始点と終点を含む）
        public let fixes: [Fix]
        public let meters: Double
        public let seconds: TimeInterval

        /// 分/km。**止まっていた区間は返さない**（色が振り切れるため）
        public var minutesPerKilometer: Double? {
            guard meters >= 1, seconds >= 1 else { return nil }
            let value = (seconds / 60) / (meters / 1000)
            // 徒歩としてありえない値は色に使わない（信号待ち・休憩・GPSの飛び）
            return (2...60).contains(value) ? value : nil
        }
    }

    /// 既定の刻み幅。**50m**。
    ///
    /// 信号ひとつ、坂ひとつぶんの粒度。「この角で止まった」まで見える。
    ///
    /// この長さで意味を持たせるには、**跡の点そのものが細かく要る**。
    /// 点が20mおきだと1区切りに2点しか入らず、GPSの誤差がそのまま色に出る。
    /// アプリ側は10mおきに点を残すようにしてある（`GameSessionStore.trackMinimumDistance`）。
    ///
    /// 時間で刻む案（1分ごとなど）は採らない。**地図の上で長さが揃わない**ため、
    /// 止まっている間だけ線が濃くなり、速いところほど色が大雑把になる
    public static let defaultInterval: Double = 50

    /// 跡を刻む。
    ///
    /// - Parameter interval: 刻む長さ（m）。最後の切れ端は短いままひとつの区切りにする
    public static func split(_ fixes: [Fix], interval: Double = defaultInterval) -> [Segment] {
        guard interval > 0, fixes.count >= 2 else { return [] }

        var segments: [Segment] = []
        var current: [Fix] = [fixes[0]]
        var carried: Double = 0

        for (previous, fix) in zip(fixes, fixes.dropFirst()) {
            let step = Geo.distanceMeters(lat1: previous.latitude, lon1: previous.longitude,
                                          lat2: fix.latitude, lon2: fix.longitude)
            current.append(fix)
            carried += step

            if carried >= interval {
                segments.append(make(id: segments.count, fixes: current, meters: carried))
                // **切れ目の点は次の区切りにも入れる。** 入れないと線が途切れて見える
                current = [fix]
                carried = 0
            }
        }

        // 端数。1点しか残っていないなら線にならないので捨てる
        if current.count >= 2 {
            segments.append(make(id: segments.count, fixes: current, meters: carried))
        }
        return segments
    }

    private static func make(id: Int, fixes: [Fix], meters: Double) -> Segment {
        let seconds = (fixes.last?.time.timeIntervalSince(fixes.first?.time ?? Date())) ?? 0
        return Segment(id: id, fixes: fixes, meters: meters, seconds: max(0, seconds))
    }

    /// 跡の総距離（m）
    public static func totalMeters(_ fixes: [Fix]) -> Double {
        zip(fixes, fixes.dropFirst()).reduce(0) { sum, pair in
            sum + Geo.distanceMeters(lat1: pair.0.latitude, lon1: pair.0.longitude,
                                     lat2: pair.1.latitude, lon2: pair.1.longitude)
        }
    }
}
