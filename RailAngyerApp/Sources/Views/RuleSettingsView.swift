import SwiftUI

/// アプリの設定（SC-02）。
///
/// **ここに置くのはシステム設定だけ**（言語・募金・使い方とお約束・アプリ情報）。
/// 遊び方のルール（コース・区間・サイコロ・到着判定・お題の見え方・共有・一周）は
/// 「その日どう歩くか」であって端末の設定ではないため、予定を立てる画面へ移した。
/// 設定と予定にルールが二重にあると、どちらが効いているのか分からなくなる。
///
/// 「みんなで遊ぶ」への入口はホームに1か所だけ置く。
/// 呼び出し側（RootView）に合わせて名前と引数はそのまま残している。
struct RuleSettingsView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Bindable var language: LanguageSetting
    @Environment(\.dismiss) private var dismiss

    @State private var showingHowToPlay = false
    @State private var document: DocumentView.Kind?
    @State private var showingSupport = false
    @State private var showingAttribution = false
    @State private var tipJar = TipJar()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("言語", selection: $language.selected) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("言語")
                } footer: {
                    Text("選ぶとすぐに切り替わります。訳が入っていないところは日本語のまま出ます。")
                }

                // **応援の導線はここに置く。** 一番下のアプリ情報に埋めると誰も見つけない。
                // ただし遊びの流れには一切割り込ませない（設定の中だけ）
                Section {
                    Button {
                        showingSupport = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.mission)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("開発者を応援する")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("1人で作っています。¥300から")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("supportDeveloper")
                } header: {
                    Text("募金")
                } footer: {
                    Text("応援しても機能は増えません。気持ちだけを受け取る仕組みです。")
                }

                Section {
                    Button {
                        showingHowToPlay = true
                    } label: {
                        Label("遊び方", systemImage: "questionmark.circle")
                    }
                    Button {
                        document = .terms
                    } label: {
                        Label("利用規約", systemImage: "doc.text")
                    }
                    Button {
                        document = .privacy
                    } label: {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                    Button {
                        showingAttribution = true
                    } label: {
                        Label("データの出典", systemImage: "map")
                    }
                } header: {
                    Text("使い方とお約束")
                } footer: {
                    Text("実際の道を歩く遊びです。歩きながら画面を操作しないでください。"
                         + "\n歩き方のルール（コース・区間・サイコロ・お題・共有）は、"
                         + "予定を立てるときに決めます。")
                }

                Section("アプリ情報") {
                    HStack(spacing: 14) {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("レイルアンギャー")
                                .font(.headline)
                            Text(versionText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showingHowToPlay) {
                HowToPlayView()
            }
            .sheet(item: $document) { DocumentView(kind: $0) }
            .sheet(isPresented: $showingSupport) {
                SupportDeveloperView(tipJar: tipJar)
            }
            .sheet(isPresented: $showingAttribution) { AttributionView() }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
        return "バージョン \(version)（\(build)）"
    }
}
