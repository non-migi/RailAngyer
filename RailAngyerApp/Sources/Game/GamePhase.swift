import Foundation

/// 画面が今どの局面にあるか。05_フロー仕様.html の ST-1〜ST-8 に対応する。
/// 状態は保存せず、進行中の `Turn` から毎回導出する（10_アプリ設計.md AD-06）。
enum GamePhase: Equatable {
    /// ルームやマスタがまだ無い
    case notReady
    /// ST-2 待機。サイコロを振れる
    case waiting(current: Int)
    /// ST-3 移動中。`next` へ向かっている。`remaining` は着地までの残り駅数
    case walking(next: Int, remaining: Int)
    /// ST-4 着地。ミッションの抽選前
    case landed(station: Int)
    /// ST-5 ミッション実行中
    case mission(station: Int)
    /// ST-6/ST-3' 効果による移動中
    case effectWalking(next: Int, destination: Int)
    /// ST-8 クリア
    case cleared

    /// プレイ中の全画面フローを出すべき局面か（08_画面仕様.html CM-01）
    var isInTurn: Bool {
        switch self {
        case .notReady, .waiting, .cleared: false
        case .walking, .landed, .mission, .effectWalking: true
        }
    }
}
