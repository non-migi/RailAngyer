import SwiftUI

/// アプリの設定（SC-02）。
///
/// **ここに置くのはシステム設定だけ。**
/// 遊び方のルール（コース・区間・サイコロ・到着判定・お題の見え方・共有・一周）は
/// 「その日どう歩くか」であって端末の設定ではないため、予定を立てる画面へ移した。
/// 設定と予定にルールが二重にあると、どちらが効いているのか分からなくなる。
///
/// 呼び出し側（RootView）に合わせて名前と引数はそのまま残している。
struct RuleSettingsView: View {
    @Bindable var store: GameSessionStore
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        LabeledContent("言語", value: AppLanguage.current.label)
                    }
                    NavigationLink("募金") { DonationView() }
                    NavigationLink("使い方とお約束") { GuideView() }
                } footer: {
                    Text("歩き方のルールは、予定を立てるときに決めます。")
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

// MARK: - 言語

/// 表示に使う言葉。
///
/// いまは日本語だけを同梱している。**選べないものを選択肢として並べない**ため、
/// 対応していない言語は「これから」として文章で伝える。
enum AppLanguage: String, CaseIterable {
    case japanese = "ja"

    var label: String {
        switch self {
        case .japanese: return "日本語"
        }
    }

    /// いま使っている言語。同梱が増えたらここを端末設定から決める形に変える
    static var current: AppLanguage { .japanese }
}

private struct LanguageSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    LabeledContent(language.label) {
                        if language == AppLanguage.current {
                            Image(systemName: "checkmark").foregroundStyle(Theme.line)
                        }
                    }
                }
            } footer: {
                Text("いまは日本語だけに対応しています。"
                     + "英語など、ほかの言葉は用意ができしだい選べるようにします。")
            }
        }
        .navigationTitle("言語")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 募金

/// 歩いた先の土地へ返す仕組み。**まだ口座も宛先も決まっていない。**
/// 決まっていないものを「できる」ように見せると、押した人を裏切ることになるので、
/// いまは考えていることだけを正直に置いておく。
private struct DonationView: View {
    var body: some View {
        Form {
            Section {
                Text("レイルアンギャーは広告を出さず、課金もありません。")
                Text("歩いて楽しかったぶんを、その土地や鉄道を守っている人たちへ"
                     + "返せる形にできないかを考えています。")
            } header: {
                Text("このアプリについて")
            }

            Section {
                Label("準備中です", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("送り先が決まったら、ここに案内を出します。"
                     + "いまのところ、このアプリからお金を受け取ることはありません。")
            }

            Section {
                Text("いちばんの応援は、実際に歩いて、写真を残して、"
                     + "だれかを誘ってもらうことです。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("募金")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 使い方とお約束

private struct GuideView: View {
    var body: some View {
        Form {
            Section("遊び方") {
                step(1, "予定を立てる",
                     "コースと区間を決めて、集合の日時と場所を書きます。"
                     + "サイコロやお題を使うかも、この予定ごとに決められます。")
                step(2, "集まって歩き出す",
                     "サイコロを振ると、その回に歩く駅数が決まります。"
                     + "サイコロを使わない予定なら、1駅ずつ順に歩きます。")
                step(3, "駅に着いたら記録する",
                     "着いた駅で写真を撮ったり、お題をこなしたりします。"
                     + "位置情報を許可していれば、到着は自動で拾います。")
                step(4, "ゴールしたらふりかえる",
                     "歩いた道のり・時間・写真は「記録」に残ります。"
                     + "記録を保存すれば、同じルールで次の旅を始められます。")
            }

            Section {
                promise("車と自転車に気をつける",
                        "画面ではなく前を見て歩いてください。"
                        + "サイコロも到着の操作も、立ち止まってから行えば間に合います。")
                promise("駅と沿線の迷惑にならない",
                        "改札の中や線路の敷地には入らないでください。"
                        + "係の人や他のお客さんの通行をふさがないようにします。")
                promise("写真に人を写しこまない",
                        "知らない人の顔や、表札・車のナンバーが写らないようにします。"
                        + "撮ってよいか迷う場所では撮らない、が安全です。")
                promise("無理をしない",
                        "体調・天気・日暮れを見て、途中でやめてかまいません。"
                        + "記録は途中でも残ります。")
            } header: {
                Text("お約束")
            } footer: {
                Text("身内で歩くためのアプリです。"
                     + "けがや事故について開発者は責任を負えないので、無理のない範囲で遊んでください。")
            }

            Section {
                Text("進行記録・訪問した駅・写真は、まず端末の中に保存されます。")
                Text("「みんなで遊ぶ」でルームに入っているあいだだけ、表示名・ルームの進行・"
                     + "お題・予定・出欠・共有した写真がサーバーへ送られます。")
                Text("端末の生のGPS座標は送りません。"
                     + "位置情報は駅に着いたかを端末の中で判定するためだけに使い、"
                     + "共有するのは到着した駅と時刻だけです。")
                Text("広告は出さず、第三者へのトラッキングも情報の販売も行いません。")
            } header: {
                Text("あつかうデータ")
            } footer: {
                Text("端末の記録は「記録を保存して新しい旅へ」かアプリの削除で消せます。"
                     + "サーバー側のルームの削除を希望するときは hikagebiyori@gmail.com まで、"
                     + "ルーム名か招待コードを添えて連絡してください。")
            }
        }
        .navigationTitle("使い方とお約束")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Theme.onLine)
                .frame(width: 24, height: 24)
                .background(Theme.line, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func promise(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
