import SwiftUI
import UIKit

/// アプリの配色。ロゴ（assets/logo.png）から取っている。
enum Theme {
    /// 南北線の緑。線・進捗・主ボタン。
    ///
    /// **明るさを配色に合わせて変える。** 濃い緑のままだと、
    /// ダークモードで黒い背景に沈んで文字やアイコンが読めなくなる
    /// （淡い緑地に緑文字を置く `.bordered` のボタンがとくに潰れる）。
    static let line = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.33, green: 0.78, blue: 0.47, alpha: 1)   // 暗所で読める明るい緑
            : UIColor(red: 0.16, green: 0.48, blue: 0.25, alpha: 1)   // ロゴの緑
    })

    /// 緑の上に文字や記号を置くときの色。地の明るさに合わせて反転させる
    static let onLine = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    /// 濃紺。サイコロの目や文字の締め
    static let ink = Color(red: 0.09, green: 0.15, blue: 0.25)
    /// 焦茶。ミッションと効果まわり
    static let mission = Color(red: 0.66, green: 0.33, blue: 0.11)
    /// 起動画像と共通の、旅支度を思わせる淡い紙色
    static let paper = Color("LaunchBackground")
    /// 笠や木の杖に使う麦色
    static let wheat = Color(red: 0.89, green: 0.67, blue: 0.29)
}

/// ペースを3分類で切らず、分/kmの値から連続的に色を作る。
/// 速いほど青、標準（12分/km前後）は緑、ゆっくりほど赤になる。
enum PacePalette {
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    private static let fast = RGB(red: 0.05, green: 0.43, blue: 0.98)
    private static let normal = RGB(red: 0.05, green: 0.68, blue: 0.32)
    private static let slow = RGB(red: 0.96, green: 0.20, blue: 0.18)

    static func color(minutesPerKilometer pace: Double?) -> Color {
        guard let pace, pace.isFinite else { return Theme.line.opacity(0.6) }
        if pace <= 12 {
            return color(mix(fast, normal, amount: normalized(pace, from: 7, to: 12)))
        }
        return color(mix(normal, slow, amount: normalized(pace, from: 12, to: 20)))
    }

    static let gradient = LinearGradient(
        stops: [
            .init(color: color(fast), location: 0),
            .init(color: color(normal), location: 0.42),
            .init(color: color(slow), location: 1)
        ],
        startPoint: .leading,
        endPoint: .trailing)

    private static func normalized(_ value: Double, from: Double, to: Double) -> Double {
        min(max((value - from) / (to - from), 0), 1)
    }

    private static func mix(_ a: RGB, _ b: RGB, amount: Double) -> RGB {
        RGB(red: a.red + (b.red - a.red) * amount,
            green: a.green + (b.green - a.green) * amount,
            blue: a.blue + (b.blue - a.blue) * amount)
    }

    private static func color(_ rgb: RGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
