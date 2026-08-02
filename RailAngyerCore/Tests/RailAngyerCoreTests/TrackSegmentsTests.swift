import Testing
import Foundation
@testable import RailAngyerCore

/// 歩いた跡を決まった長さごとに刻む（`TrackSegments`）。
///
/// **駅間ひとまとまりで色を塗ると、途中の起伏が消える。**
/// 同じ駅間でも「坂で失速した」「商店街で寄り道した」が分かる粒度にしたい。
struct TrackSegmentsTests {

    private let start = Date(timeIntervalSince1970: 1_786_233_600)

    /// 麻生から南へ、だいたい `meters` おきに `count` 点を置く。
    /// 緯度1度 ≒ 111km なので、そこから刻み幅を出す
    private func line(count: Int, meters: Double,
                      secondsPerStep: TimeInterval = 144) -> [TrackSegments.Fix] {
        (0..<count).map { index in
            TrackSegments.Fix(latitude: 43.10834 - Double(index) * (meters / 111_000),
                              longitude: 141.33848,
                              time: start.addingTimeInterval(Double(index) * secondsPerStep))
        }
    }

    @Test("点が1つだけなら刻めない")
    func needsTwoPoints() {
        #expect(TrackSegments.split(line(count: 1, meters: 50)).isEmpty)
        #expect(TrackSegments.split([]).isEmpty)
    }

    @Test("刻み幅ごとに区切られる")
    func splitsByInterval() {
        // 50m × 20歩 = 1000m を 200m で刻めば 5本
        let segments = TrackSegments.split(line(count: 21, meters: 50), interval: 200)

        #expect(segments.count == 5)
        for segment in segments {
            #expect(segment.meters >= 190 && segment.meters <= 260, "\(segment.meters)")
        }
    }

    @Test("線がつながるように、切れ目の点は次の区切りにも入る")
    func segmentsShareBoundaryPoint() throws {
        let segments = TrackSegments.split(line(count: 21, meters: 50), interval: 200)

        // 途切れて見えないよう、前の終わりと次の始まりが同じ場所であること
        for (previous, next) in zip(segments, segments.dropFirst()) {
            let end = try #require(previous.fixes.last)
            let head = try #require(next.fixes.first)
            #expect(abs(end.latitude - head.latitude) < 1e-9)
            #expect(abs(end.longitude - head.longitude) < 1e-9)
        }
    }

    @Test("刻みに満たない端数もひとつの区切りになる")
    func keepsRemainder() {
        // 50m × 5歩 = 250m。200mで刻むと 200m と 50m の2本
        let segments = TrackSegments.split(line(count: 6, meters: 50), interval: 200)

        #expect(segments.count == 2)
        #expect(segments.last!.meters < 200)
    }

    @Test("刻みより短い跡でも1本は返る")
    func shortTrackStillHasOneSegment() {
        let segments = TrackSegments.split(line(count: 3, meters: 20), interval: 200)

        #expect(segments.count == 1)
        #expect(segments.first!.meters > 0)
    }

    @Test("区切りごとに分/kmが出る")
    func computesPacePerSegment() throws {
        // 50m を 36秒 = 時速5km = 12分/km
        let segments = TrackSegments.split(line(count: 21, meters: 50, secondsPerStep: 36),
                                           interval: 200)

        let pace = try #require(segments.first?.minutesPerKilometer)
        #expect(abs(pace - 12) < 0.6, "\(pace)")
    }

    @Test("止まっていた区切りは色に使わない")
    func ignoresStandingStill() {
        // 200m に1時間かけている＝300分/km。信号待ちや休憩で、徒歩の色に混ぜたくない
        let segments = TrackSegments.split(line(count: 5, meters: 50, secondsPerStep: 900),
                                           interval: 200)

        #expect(segments.first?.minutesPerKilometer == nil)
    }

    @Test("総距離が出る")
    func totalDistance() {
        let total = TrackSegments.totalMeters(line(count: 11, meters: 100))

        // 100m × 10歩
        #expect(abs(total - 1000) < 30, "\(total)")
    }

    @Test("既定の刻み幅は50m")
    func defaultIntervalIsFineGrained() {
        #expect(TrackSegments.defaultInterval == 50)

        // 10mおきに300m歩いた跡を、指定なしで刻むと6本になる
        let segments = TrackSegments.split(line(count: 31, meters: 10))

        #expect(segments.count == 6)
    }

    @Test("50m刻みでも、区切りごとの分/kmが出る")
    func computesPaceAtFineInterval() throws {
        // 10m を 7.2秒 = 時速5km = 12分/km
        let segments = TrackSegments.split(line(count: 31, meters: 10, secondsPerStep: 7.2))

        let pace = try #require(segments.first?.minutesPerKilometer)
        #expect(abs(pace - 12) < 1.0, "\(pace)")
    }

    @Test("刻み幅が0以下なら刻まない")
    func rejectsZeroInterval() {
        #expect(TrackSegments.split(line(count: 10, meters: 50), interval: 0).isEmpty)
    }
}
