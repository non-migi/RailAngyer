import SwiftUI

/// 利用規約とプライバシーポリシーを、アプリの中で読めるようにする（SC-26）。
///
/// **リンク先が開けなくても読めることが大事。** 圏外でも、
/// 公開ページを直すのが間に合わなくても、同梱したものは必ず出る。
/// 正は `files/21_利用規約.md` と `files/16_プライバシーポリシー.md`
/// （`RailAngyerApp/Resources/` へ写して同梱している）。
struct DocumentView: View {

    enum Kind: String, Identifiable {
        case terms = "Terms"
        case privacy = "Privacy"
        /// 特定商取引法に基づく表記。**規約の中の一節ではなく、専用の1枚にする**
        /// （全文をスクロールして該当節を探させない）
        case commerce = "Commerce"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .terms:    return appLocalized("利用規約")
            case .privacy:  return appLocalized("プライバシーポリシー")
            case .commerce: return appLocalized("特定商取引法に基づく表記")
            }
        }

        /// 参考訳（`.en.md`）を出してよいか。
        ///
        /// **特定商取引法の表記は日本語のまま出す。** 日本の消費者を守る日本法の表記で、
        /// 表示言語を英語にしている日本の利用者が、日本語の表記に辿り着けなくなるのは
        /// 望ましくない（海外の利用者に日本語が出るのは差し支えない）。
        /// そのため英語版のファイルも作らない
        var usesTranslation: Bool { self != .commerce }
    }

    let kind: Kind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    /// 同梱した本文。Markdownの記号だけ落として、そのまま読ませる。
    ///
    /// **正文は日本語版**（`Privacy.md` / `Terms.md`）。アプリの言語が日本語以外なら
    /// 参考訳の英語版（`.en.md`）を出し、無ければ日本語へフォールバックする
    private var text: AttributedString {
        guard let url = documentURL,
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return AttributedString(appLocalized("本文を読み込めませんでした。"))
        }
        return (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }

    /// 表示する版のURL。日本語以外では `Privacy.en.md` / `Terms.en.md` を先に探す。
    /// **`.commerce` だけは言語で分けない**（`Kind.usesTranslation` に理由を書いた）
    private var documentURL: URL? {
        let isJapanese = AppLanguage.currentLocale.language.languageCode?.identifier == "ja"
        if kind.usesTranslation, !isJapanese,
           let english = Bundle.main.url(forResource: "\(kind.rawValue).en", withExtension: "md") {
            return english
        }
        return Bundle.main.url(forResource: kind.rawValue, withExtension: "md")
    }
}
