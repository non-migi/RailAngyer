import SwiftUI

/// アプリの配色。ロゴ（assets/logo.png）から取っている。
enum Theme {
    /// 南北線の緑。線・進捗・主ボタン
    static let line = Color(red: 0.16, green: 0.48, blue: 0.25)
    /// 濃紺。サイコロの目や文字の締め
    static let ink = Color(red: 0.09, green: 0.15, blue: 0.25)
    /// 焦茶。ミッションと効果まわり
    static let mission = Color(red: 0.66, green: 0.33, blue: 0.11)
    /// 起動画像と共通の、旅支度を思わせる淡い紙色
    static let paper = Color("LaunchBackground")
    /// 笠や木の杖に使う麦色
    static let wheat = Color(red: 0.89, green: 0.67, blue: 0.29)
}
