import Foundation

/// すごろくのルール計算。
///
/// **位置情報にもデータベースにも依存しない。**
/// 着地駅の算出・区間の端でのクランプ・効果の適用・クリア判定がすべてここに集まる。
/// GPS もシミュレータも使わずにテストできるようにするための分離（10_アプリ設計.md AD-03）。
///
/// 位置はすべて `Station.orderNo`（路線の端からの通し番号）で扱う。
public struct GameEngine: Sendable, Equatable {

    /// 区間のスタート駅の OrderNo
    public let startOrder: Int
    /// 区間のゴール駅の OrderNo。
    /// **環状で一周するときは「始発駅＋1周ぶん」**という、駅には無い番号になる
    public let goalOrder: Int
    /// サイコロの最大出目（1〜9）
    public let diceMax: Int
    /// 環状コースの1周の駅数。`nil` なら端から端までの直線区間
    public let loopStationCount: Int?

    /// - Note: `diceMax` は 1〜9 に丸める。
    ///   保存されたデータから作るため、範囲外の値で落ちるより丸めて動き続けるほうがよい。
    public init(startOrder: Int, goalOrder: Int, diceMax: Int = 6,
                loopStationCount: Int? = nil) {
        precondition(startOrder != goalOrder, "スタートとゴールが同じ駅では区間にならない")
        self.startOrder = startOrder
        self.goalOrder = goalOrder
        self.diceMax = Swift.min(Swift.max(diceMax, 1), 9)
        self.loopStationCount = loopStationCount
    }

    /// 環状コースを一周する区間を作る。
    ///
    /// **一周を「駅の通し番号が1周ぶん伸びた直線」として扱う。**
    /// こうすると、ゴールでのクランプも戻る効果も、直線区間の計算がそのまま使える。
    /// 位置の番号は駅数を超えるので、駅に直すときは `stationOrder(at:)` を通す。
    ///
    /// - Parameter forward: `true` で通し番号が増える向き、`false` で減る向き
    public static func lap(from startOrder: Int, stationCount: Int,
                           forward: Bool, diceMax: Int = 6) -> GameEngine {
        precondition(stationCount > 1, "1周に2駅以上必要")
        return GameEngine(startOrder: startOrder,
                          goalOrder: startOrder + (forward ? stationCount : -stationCount),
                          diceMax: diceMax,
                          loopStationCount: stationCount)
    }

    public var isLoop: Bool { loopStationCount != nil }

    /// 位置の番号を、実際の駅の OrderNo に直す。
    /// 直線区間ではそのまま返す
    public func stationOrder(at position: Int) -> Int {
        guard let count = loopStationCount else { return position }
        return ((position - 1) % count + count) % count + 1
    }

    /// 訪れうる駅の数。
    /// 一周では最後にスタート駅へ戻るため、**その1駅を二重に数えない**
    public var distinctStationCount: Int {
        isLoop ? stationCount - 1 : stationCount
    }

    // MARK: - 区間

    /// 進む向き。`+1` = OrderNo が増える / `-1` = 減る（逆走コース）
    public var direction: Int { goalOrder > startOrder ? 1 : -1 }

    /// 区間内の OrderNo の範囲（両端を含む）
    public var range: ClosedRange<Int> {
        min(startOrder, goalOrder)...max(startOrder, goalOrder)
    }

    /// 区間内の駅数
    public var stationCount: Int { range.count }

    /// 区間内の OrderNo を、進む向きに並べて返す
    public var orderedRange: [Int] {
        direction == 1 ? Array(range) : Array(range.reversed())
    }

    // MARK: - サイコロ

    /// 1〜`diceMax` の一様乱数
    public func roll() -> Int { Int.random(in: 1...diceMax) }

    // MARK: - 移動

    /// 出目による着地駅。ゴールを超えたらゴールで止める（R-11）
    public func landingOrder(from current: Int, dice: Int) -> Int {
        clampToGoal(current + direction * dice)
    }

    /// ミッションの効果を適用した後の終了位置（R-11 / R-12）
    ///
    /// - `forward` / `back` は区間の端でクランプする
    /// - `jump` の移動先が区間外なら移動しない（R-16）
    /// - `none` / `rollAgain` は着地駅のまま
    public func endOrder(landing: Int,
                         effect: EffectType,
                         value: Int? = nil,
                         jumpTo: Int? = nil) -> Int {
        switch effect {
        case .none, .rollAgain:
            return landing
        case .forward:
            return clampToGoal(landing + direction * (value ?? 0))
        case .back:
            return clampToStart(landing - direction * (value ?? 0))
        case .jump:
            guard let jumpTo, range.contains(jumpTo) else { return landing }
            return jumpTo
        }
    }

    /// 歩く順に並べた通過駅（最後の要素が目的地）。
    /// 同じ駅なら空配列を返す。戻る場合も逆順で正しく返る。
    public func path(from: Int, to: Int) -> [Int] {
        guard from != to else { return [] }
        let step = to > from ? 1 : -1
        return Array(stride(from: from + step, through: to, by: step))
    }

    /// ゴールに到達したか（R-18）
    public func isCleared(_ order: Int) -> Bool { order == goalOrder }

    // MARK: - クランプ

    /// ゴールを超えさせない
    private func clampToGoal(_ order: Int) -> Int {
        direction == 1 ? Swift.min(order, goalOrder) : Swift.max(order, goalOrder)
    }

    /// スタートより手前へ戻らせない
    private func clampToStart(_ order: Int) -> Int {
        direction == 1 ? Swift.max(order, startOrder) : Swift.min(order, startOrder)
    }
}

// MARK: - 1ターンの計画

public extension GameEngine {

    /// サイコロを振った結果、そのターンで歩く道のり。
    struct TurnPlan: Sendable, Equatable {
        /// 出発した駅
        public let from: Int
        /// 出目
        public let dice: Int
        /// 着地駅（ミッションを引く駅）
        public let landing: Int
        /// 通り道の駅（着地駅を含まない）
        public let passing: [Int]
        /// 着地駅がゴールか
        public let reachesGoal: Bool

        /// 歩く順の全駅（最後が着地駅）
        public var allStops: [Int] { passing + [landing] }
    }

    /// 現在位置と出目から、そのターンの道のりを組み立てる
    func plan(from current: Int, dice: Int) -> TurnPlan {
        let landing = landingOrder(from: current, dice: dice)
        let stops = path(from: current, to: landing)
        return TurnPlan(from: current,
                        dice: dice,
                        landing: landing,
                        passing: Array(stops.dropLast()),
                        reachesGoal: isCleared(landing))
    }
}
