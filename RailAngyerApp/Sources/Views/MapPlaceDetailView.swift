import SwiftUI
import MapKit

/// 地図の上で押された施設。
///
/// 地図が返すのは名前と分類と座標だけなので、住所や電話は
/// **押されてから** `MKMapItem` を引き当てて足す（一覧を出すたびに問い合わせない）。
struct MapPlace: Identifiable, Equatable {
    let name: String
    let category: MKPointOfInterestCategory?
    let coordinate: CLLocationCoordinate2D
    var mapItem: MKMapItem?

    var id: String { "\(name)/\(coordinate.latitude),\(coordinate.longitude)" }

    static func == (lhs: MapPlace, rhs: MapPlace) -> Bool { lhs.id == rhs.id }
}

/// 押した施設の情報（SC-24）。
///
/// **歩いている最中に知りたいのは「入れるのか」**。
/// トイレ・コンビニ・カフェを探しているのであって、観光案内が要るわけではない。
/// だから出すのは、分類・住所・電話・地図アプリへの引き渡しに絞る。
struct MapPlaceDetailView: View {

    let place: MapPlace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var detail: MKMapItem?
    @State private var isLoading = false

    private var resolved: MKMapItem? { detail ?? place.mapItem }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name).font(.headline)
                        if let label = categoryLabel {
                            Label(label, systemImage: categorySymbol)
                                .font(.subheadline).foregroundStyle(Theme.line)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("詳しい情報を調べています…")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let address {
                        LabeledContent("住所", value: address)
                    }
                    if let phone = resolved?.phoneNumber {
                        Button {
                            if let url = URL(string: "tel://"
                                             + phone.filter { $0.isNumber || $0 == "+" }) {
                                openURL(url)
                            }
                        } label: {
                            LabeledContent("電話", value: phone)
                        }
                    }
                    if let url = resolved?.url {
                        Link(destination: url) {
                            LabeledContent("ホームページ", value: url.host() ?? url.absoluteString)
                        }
                    }
                    if !isLoading && address == nil && resolved?.phoneNumber == nil {
                        Text("この場所の詳しい情報は見つかりませんでした。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        openInMaps()
                    } label: {
                        Label("マップアプリで開く", systemImage: "map")
                    }
                } footer: {
                    Text("経路を調べたいときは、マップアプリへ渡してください。")
                }
            }
            .navigationTitle("この場所")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await resolveIfNeeded() }
        }
    }

    private var address: String? {
        guard let placemark = resolved?.placemark else { return nil }
        // 日本の住所は「北海道札幌市北区…」の順に読む
        let parts = [placemark.administrativeArea, placemark.locality,
                     placemark.subLocality, placemark.thoroughfare,
                     placemark.subThoroughfare]
        let text = parts.compactMap { $0 }.joined()
        return text.isEmpty ? nil : text
    }

    /// 地図が返すのは名前と分類だけなので、住所や電話は問い合わせて足す
    private func resolveIfNeeded() async {
        guard resolved == nil else { return }
        isLoading = true
        defer { isLoading = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.name
        request.region = MKCoordinateRegion(center: place.coordinate,
                                            latitudinalMeters: 300, longitudinalMeters: 300)
        detail = try? await MKLocalSearch(request: request).start().mapItems.first
    }

    private func openInMaps() {
        let item = resolved ?? MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = item.name ?? place.name
        item.openInMaps()
    }

    private var categoryLabel: String? {
        guard let category = place.category ?? resolved?.pointOfInterestCategory else { return nil }
        return Self.labels[category].map { appLocalized($0) }
    }

    private var categorySymbol: String {
        switch place.category ?? resolved?.pointOfInterestCategory {
        case .some(.restroom):     return "toilet"
        case .some(.cafe):         return "cup.and.saucer"
        case .some(.restaurant):   return "fork.knife"
        case .some(.store), .some(.foodMarket): return "cart"
        case .some(.park):         return "tree"
        case .some(.publicTransport): return "tram"
        default:                   return "mappin.circle"
        }
    }

    /// 歩いているときに探しがちなものだけ日本語にする。
    /// 網羅はしない（訳が無ければ分類の行を出さないだけ）。
    /// 値はカタログのキー。表示するときに `appLocalized` で選択言語に解決する
    private static let labels: [MKPointOfInterestCategory: String.LocalizationValue] = [
        .restroom: "トイレ",
        .cafe: "カフェ",
        .restaurant: "飲食店",
        .store: "お店",
        .foodMarket: "食料品店",
        .bakery: "パン屋",
        .park: "公園",
        .publicTransport: "駅・バス停",
        .parking: "駐車場",
        .atm: "ATM",
        .bank: "銀行",
        .hospital: "病院",
        .pharmacy: "薬局",
        .museum: "博物館",
        .library: "図書館",
        .hotel: "宿",
        .nightlife: "居酒屋・バー",
        .beach: "浜辺",
        .campground: "キャンプ場",
        .fitnessCenter: "ジム",
        .movieTheater: "映画館",
        .postOffice: "郵便局",
        .school: "学校",
        .stadium: "競技場",
        .theater: "劇場",
        .zoo: "動物園"
    ]
}
