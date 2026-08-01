import SwiftUI
import MapKit
import RailAngyerCore

/// 選んだ区間を地図に描く。予定・お題・共有のどこでも同じ絵を出すための部品。
///
/// **歩く前に見る地図**なので、進行中の盤面（`BoardMapView`）とは役割が違う。
/// 現在地や写真は出さず、「どこからどこまで、どんな形の道のりか」だけを見せる。
///
/// 一覧の行に置くときは操作を切る（`interactive: false`）。
/// 地図が指を奪うと、一覧を縦にスクロールできなくなるため。
struct CourseSectionMapView: View {

    /// 区間の駅（通し番号の順に並んでいること）
    let stations: [Station]
    /// 一周する区間か。最後の駅から最初の駅へ線を戻す
    var isLoop: Bool = false
    /// 強く出す駅（お題を書いている駅など）
    var highlightedOrder: Int?
    /// 印を付ける駅（お題を書き終えた駅）
    var markedOrders: Set<Int> = []
    var interactive: Bool = false

    @State private var camera: MapCameraPosition = .automatic
    /// 地図の上で選ばれた施設（コンビニ・トイレ・カフェなど）。
    /// **操作できる地図でだけ拾う**（一覧の小さな地図で反応させても邪魔になる）。
    /// `MapSelection` は iOS 18 からなので、iOS 17 でも使える `MapFeature` で受ける
    @State private var selection: MapFeature?

    var body: some View {
        Map(position: $camera,
            interactionModes: interactive ? .all : [],
            selection: interactive ? $selection : .constant(nil)) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Theme.line.opacity(0.75),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            ForEach(stations) { station in
                Annotation(annotationLabel(station), coordinate: coordinate(station)) {
                    marker(station)
                }
                .annotationTitles(interactive ? .automatic : .hidden)
            }
        }
        .onAppear(perform: fit)
        .onChange(of: stations.map(\.orderNo), fit)
        .sheet(item: Binding(get: { selectedPlace }, set: { if $0 == nil { selection = nil } })) {
            MapPlaceDetailView(place: $0)
        }
    }

    /// 選ばれた施設。地図が返す `MapFeature` から名前と分類が取れる
    private var selectedPlace: MapPlace? {
        guard let selection else { return nil }
        return MapPlace(name: selection.title ?? "この場所",
                        category: selection.pointOfInterestCategory,
                        coordinate: selection.coordinate)
    }

    // MARK: - 駅の印

    @ViewBuilder
    private func marker(_ station: Station) -> some View {
        let isEnd = station.orderNo == stations.first?.orderNo
            || station.orderNo == stations.last?.orderNo
        let isHighlighted = station.orderNo == highlightedOrder
        let isMarked = markedOrders.contains(station.orderNo)

        ZStack {
            Circle()
                .fill(isHighlighted || isMarked ? Theme.line : Color(.systemBackground))
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: isHighlighted ? 3 : 2))
            if isMarked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.onLine)
            }
        }
        .frame(width: isHighlighted ? 22 : (isEnd || isMarked ? 16 : 10),
               height: isHighlighted ? 22 : (isEnd || isMarked ? 16 : 10))
    }

    private func annotationLabel(_ station: Station) -> String {
        // 操作できない小さな地図では駅名を出さない（潰れて読めない）
        interactive ? station.name : ""
    }

    private func coordinate(_ station: Station) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        let points = stations.map(coordinate)
        guard isLoop, let first = points.first, points.count > 2 else { return points }
        return points + [first]
    }

    /// 区間全体が入るように寄せる
    private func fit() {
        guard !stations.isEmpty else { return }
        let lats = stations.map(\.latitude)
        let lons = stations.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.35, 0.008),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.35, 0.008))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// 区間の地図と、歩く距離・時間の目安をひとまとめにしたもの。
///
/// **予定を立てる段で「半日で終わるのか」を決められるようにする**のが狙い。
/// 目安は駅の直線距離から出しており、経路探索はしない（通信が要るうえ、当日の道取りで変わる）。
struct CourseSectionSummaryView: View {

    let stations: [Station]
    var isLoop: Bool = false
    var highlightedOrder: Int?
    var markedOrders: Set<Int> = []
    /// 見出し（「南北線　麻生 → 真駒内」など）。省略すると出さない
    var caption: String?

    @State private var showingFullMap = false

    private var estimate: WalkEstimate {
        WalkEstimator.estimate(points: mapStations)
    }

    /// 一周では出発した駅へ戻るぶんまで数える
    private var mapStations: [Station] {
        guard isLoop, let first = stations.first, stations.count > 2 else { return stations }
        return stations + [first]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }

            Button {
                showingFullMap = true
            } label: {
                CourseSectionMapView(stations: stations,
                                     isLoop: isLoop,
                                     highlightedOrder: highlightedOrder,
                                     markedOrders: markedOrders)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Label("大きく見る", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .padding(7)
                    }
            }
            .buttonStyle(.plain)

            estimateRow
        }
        .sheet(isPresented: $showingFullMap) {
            NavigationStack {
                CourseSectionMapView(stations: stations,
                                     isLoop: isLoop,
                                     highlightedOrder: highlightedOrder,
                                     markedOrders: markedOrders,
                                     interactive: true)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(caption ?? "コースの地図")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { showingFullMap = false }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        estimateRow
                            .padding(12)
                            .background(.regularMaterial)
                    }
            }
        }
    }

    private var estimateRow: some View {
        HStack(spacing: 14) {
            metric("歩く距離の目安", estimate.distanceText, "figure.walk")
            metric("かかる時間の目安", estimate.durationText, "clock")
            metric("駅数", "\(stations.count) 駅", "tram")
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption2).foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value).font(.subheadline.bold()).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
