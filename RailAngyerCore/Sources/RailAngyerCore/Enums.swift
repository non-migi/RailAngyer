import Foundation

/// ミッションに付けられる効果。
/// サーバー側 `Mission.EffectType` と同じ値を使う（06_schema.sql §3）。
public enum EffectType: Int, CaseIterable, Codable, Sendable {
    /// 効果なし（通常のお題）。コマは動かない
    case none = 0
    /// ゴール方向へ `effectValue` 駅進む
    case forward = 1
    /// スタート方向へ `effectValue` 駅戻る
    case back = 2
    /// 位置は動かさず、そのまま次のターンを始める
    case rollAgain = 3
    /// 指定した駅へ移動する（区間内に限る）
    case jump = 4

    /// 進む・戻るのときだけ駅数が必要
    public var needsValue: Bool { self == .forward || self == .back }
    /// 指定駅へ移動のときだけ移動先が必要
    public var needsStation: Bool { self == .jump }
    /// コマが動く効果か（動く場合は歩いて移動する）
    public var movesPiece: Bool { self == .forward || self == .back || self == .jump }
}

/// 訪問の種別。サーバー側 `Visit.VisitKind` と同じ値。
public enum VisitKind: Int, Codable, Sendable {
    /// 始点（ゲーム開始時の記録）
    case start = 0
    /// 出目による移動の通り道
    case passing = 1
    /// 着地。ミッションを引く唯一の駅
    case landing = 2
    /// 効果による移動の通り道
    case effectPassing = 3
    /// 効果による移動の到達点。ここではミッションを引かない
    case effectArrival = 4
}

/// ローカルの行がサーバーに送られているか。
public enum SyncState: Int, Codable, Sendable {
    case localOnly = 0
    case synced = 1
    case pendingUpdate = 2
}
