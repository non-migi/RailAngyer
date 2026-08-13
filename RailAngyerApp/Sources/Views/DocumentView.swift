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

        var id: String { rawValue }

        var title: String {
            switch self {
            case .terms:   return appLocalized("利用規約")
            case .privacy: return appLocalized("プライバシーポリシー")
            }
        }
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

    /// 同梱した本文。Markdownの記号だけ落として、そのまま読ませる
    private var text: AttributedString {
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return AttributedString(appLocalized("本文を読み込めませんでした。"))
        }
        return (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }
}
