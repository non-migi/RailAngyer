import SwiftUI

/// 使わせてもらっているデータの出典（SC-29）。
///
/// **表示は義務。** 駅の座標は公開データから作っており、
/// 国土数値情報も OpenStreetMap も出典の明示を条件にしている。
/// とくに OpenStreetMap の **ODbL** は、表示に加えて派生データの扱いにも条件がある。
///
/// 無償で配っているうちは見過ごされがちだが、
/// **有料にするなら必ず出しておくもの**なので、先に入れてある。
struct AttributionView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    source(title: "国土数値情報（鉄道データ N02）",
                           holder: "国土交通省",
                           detail: "札幌市営地下鉄3路線と山手線の駅位置に使っています。測地系は JGD2011。",
                           license: "国土数値情報 利用約款にもとづき利用",
                           url: "https://nlftp.mlit.go.jp/ksj/")
                } header: {
                    Text("駅の位置")
                }

                Section {
                    source(title: "OpenStreetMap",
                           holder: "© OpenStreetMap contributors",
                           detail: "阪急京都本線と札幌市電の駅・電停の位置に使っています。",
                           license: "Open Database License（ODbL）",
                           url: "https://www.openstreetmap.org/copyright")
                } footer: {
                    Text("ODbL では、このデータを使って作ったデータベースを配る場合、同じ条件で公開することが求められます。")
                }

                Section {
                    source(title: "Apple マップ（MapKit）",
                           holder: "Apple Inc.",
                           detail: "地図の表示、周辺の施設、徒歩経路の案内に使っています。",
                           license: nil,
                           url: "https://www.apple.com/legal/internet-services/maps/terms-en.html")
                } header: {
                    Text("地図")
                }

                Section {
                    Text("駅の位置は公開データにもとづく参考値です。到着の判定、距離と時間の目安は、いずれも目安であり、実際の道のりや所要時間とは異なります。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("正確さについて")
                }
            }
            .navigationTitle("データの出典")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    // 出典の名前（`title` / `holder`）は固有名詞なので訳さない。
    // 説明と使用条件は訳すので `LocalizedStringKey` で受ける
    private func source(title: String, holder: String, detail: LocalizedStringKey,
                        license: LocalizedStringKey?, url: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold())
            Text(holder).font(.caption).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let license {
                Text(license).font(.caption2).foregroundStyle(Theme.line)
            }
            if let link = URL(string: url) {
                Link(destination: link) {
                    Text(url).font(.caption2).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
