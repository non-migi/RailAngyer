import SwiftUI

/// 遊び方（SC-25）。
///
/// **このアプリは初見で分かる作りではない。** サイコロで駅を進み、
/// 着いた駅で誰かの書いたお題をやる、という筋を知らないと何もできない。
/// 説明は「まず何をするか」の順に置き、ルールの網羅はしない。
struct HowToPlayView: View {

    @Environment(\.dismiss) private var dismiss
    /// 初めて開いたときだけ出す。読んだら二度目からは出さない
    @AppStorage("didReadHowToPlay") private var didRead = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("鉄道の駅を、実際に歩いて巡ります。")
                            .font(.headline)
                        Text("サイコロを振った目の数だけ駅を進み、"
                             + "着いた駅で誰かの書いた「お題」をこなします。"
                             + "ゴールの駅に着いたら終わりです。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("遊ぶ順番") {
                    step(1, "コースと区間を決める", "設定＞ルール設定。"
                         + "国 → 都道府県 → 路線 の順にたどって選びます。",
                         "slider.horizontal.3")
                    step(2, "お題を書く", "区間の駅に、その駅でやることを書きます。"
                         + "1つの駅に書けるのは1人1個までです。",
                         "square.and.pencil")
                    step(3, "サイコロを振る", "出た目の数だけ先の駅が行き先になります。",
                         "dice")
                    step(4, "そこまで歩く", "通り道の駅も1駅ずつ通過します。"
                         + "駅に近づくと自動で到着になります。",
                         "figure.walk")
                    step(5, "お題をこなす", "着いた駅のお題が1つ引かれます。"
                         + "終わったら次のサイコロへ。",
                         "checkmark.circle")
                }

                Section {
                    bullet("駅に着いたのに反応しないとき",
                           "画面下の「ここに着いた」で手動でも進めます。"
                           + "GPSがずれる場所や、地下では届かないことがあります。")
                    bullet("圏外でも遊べます",
                           "記録は端末に残り、電波が戻ったときにまとめて共有されます。")
                    bullet("みんなで遊ぶには",
                           "設定＞みんなで遊ぶ からルームを作り、"
                           + "招待コードか共有リンクを仲間に渡します。")
                    bullet("お題を先に見せるかどうか",
                           "設定＞お題の見え方 で、当日までのお楽しみにするか、"
                           + "いつでも見えるようにするかを選べます。")
                } header: {
                    Text("困ったとき")
                }

                Section {
                    bullet("車内では遊ばない",
                           "歩いて巡る遊びです。移動中の車両内での操作は想定していません。")
                    bullet("歩きスマホをしない",
                           "画面を見るときは立ち止まってください。"
                           + "到着は自動で判定されるので、歩きながら見る必要はありません。")
                    bullet("私有地に入らない",
                           "お題は駅の外でも構いませんが、入れる場所だけにしてください。")
                } header: {
                    Text("安全のために")
                } footer: {
                    Text("実際の道を歩く遊びです。周りの人と交通に気をつけてください。")
                }
            }
            .navigationTitle("遊び方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        didRead = true
                        dismiss()
                    }
                }
            }
        }
    }

    private func step(_ number: Int, _ title: String,
                      _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.line.opacity(0.15))
                Text("\(number)").font(.subheadline.bold()).foregroundStyle(Theme.line)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func bullet(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
