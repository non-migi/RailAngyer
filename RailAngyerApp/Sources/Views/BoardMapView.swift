import SwiftUI
import MapKit
import RailAngyerCore

/// 盤面の地図表示（SC-04）。区間の全駅を地図に出し、進捗を一目で見せる。
///
/// **現地でマスタの座標が実際の駅とどれだけズレているかを確認する用途も兼ねる**
/// （フェーズ1の検証項目「駅座標の精度」）。一覧では1駅ずつしか見られない。
///
/// 線の引き分け:
/// - **これから行くところ**は点線。**道路に沿った形**で引く（取れるまでは直線）
/// - **実際に歩いた跡**は実線。GPSで残した跡そのものを描き、
///   **200mごとに刻んでその区切りの速さで色を変える**
///   （分/kmに応じて、速い青 → 標準の緑 → ゆっくりの赤へ連続変化）
/// - 跡がまだ無いところは、駅と駅を結んだ線を区間の速さで描く（従来どおり）
///
/// **駅にお題があればピンを立てる。** 押すとその駅の詳細が開き、中身が読める。
struct BoardMapView: View {
    @Bindable var store: GameSessionStore
    @Binding var selectedStation: StationSelection?

    @State private var camera: MapCameraPosition = .automatic
    @State private var routes = CourseRouteProvider()

    private var stations: [Station] { store.stationsInOrder }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()

            // これから行くところ。点線。道路沿いの形が取れていればそれを使う
            ForEach(plannedLegs) { leg in
                MapPolyline(coordinates: leg.points)
                    .stroke(Theme.line.opacity(0.5), style: plannedStyle)
            }

            // 駅と駅を結んだ線。跡が無いところの記録として残す
            ForEach(walkedLegs) { leg in
                MapPolyline(coordinates: leg.points)
                    .stroke(PacePalette.color(minutesPerKilometer: leg.minutesPerKilometer),
                            style: walkedStyle)
            }

            // 実際に歩いた跡。200mごとに、その区切りの速さで色を変える
            ForEach(trackSegments) { segment in
                MapPolyline(coordinates: segment.points)
                    .stroke(PacePalette.color(minutesPerKilometer: segment.minutesPerKilometer),
                            style: trackStyle)
            }

            ForEach(stations) { station in
                Annotation(station.name, coordinate: coordinate(station)) {
                    marker(for: station)
                        .onTapGesture { selectedStation = StationSelection(id: station.orderNo) }
                }
            }
        }
        .mapControls { MapUserLocationButton() }
        .safeAreaInset(edge: .bottom) { legend }
        .onAppear(perform: fitToSection)
        .onChange(of: stations.count, fitToSection)
        .task(id: stations.map(\.orderNo)) {
            // 道路沿いの形を、手前の区間から少しずつ取る。取れなくても直線で描ける
            await routes.load(stations: stations)
        }
    }

    // MARK: - 駅のマーカー

    @ViewBuilder
    private func marker(for station: Station) -> some View {
        let isCurrent = station.orderNo == store.currentOrder
        let isVisited = store.visitedOrders.contains(station.orderNo)
        let isLanded = store.landedOrders.contains(station.orderNo)
        let photos = store.photoFileNames(at: station.orderNo)
        let hasMission = store.missionOrders.contains(station.orderNo)

        ZStack(alignment: .topTrailing) {
            if let fileName = photos.first, let image = PhotoStore.load(fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: isCurrent ? 50 : 42, height: isCurrent ? 50 : 42)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: isCurrent ? 3 : 1))
            } else {
                ZStack {
                    Circle()
                        .fill(isVisited ? Theme.line : Color(.systemBackground))
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: isCurrent ? 4 : 2))
                    if isLanded {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9)).foregroundStyle(Theme.onLine)
                    }
                }
                .frame(width: isCurrent ? 26 : (isVisited ? 18 : 14),
                       height: isCurrent ? 26 : (isVisited ? 18 : 14))
            }

            if !photos.isEmpty {
                Text("\(photos.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(Theme.ink))
                    .offset(x: 5, y: -5)
                    .accessibilityLabel("\(station.name)で撮った写真がある")
            }

            // **お題のある駅にピンを立てる。** 地図を見ただけで
            // 「この駅には何かある」と分かるようにする（中身は押すと読める）
            if hasMission && !isLanded {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.onLine)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(Theme.mission))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: photos.isEmpty ? 4 : 4, y: photos.isEmpty ? -4 : 16)
                    .accessibilityLabel("\(station.name)にはお題がある")
            }
        }
        .frame(width: 54, height: 54)
        .shadow(color: .black.opacity(0.2), radius: isCurrent || !photos.isEmpty ? 5 : 0, y: 2)
    }

    // MARK: - 線

    private var plannedStyle: StrokeStyle {
        StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [2, 10])
    }

    /// 駅と駅を結んだだけの線。跡がある区間では跡に主役を譲るので細く薄く
    private var walkedStyle: StrokeStyle {
        StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    }

    /// 実際に歩いた跡。いちばん太く描く
    private var trackStyle: StrokeStyle {
        StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
    }

    private func coordinate(_ station: Station) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
    }

    private var coordinates: [CLLocationCoordinate2D] { stations.map(coordinate) }

    struct Leg: Identifiable {
        let id: String
        let points: [CLLocationCoordinate2D]
    }

    /// これから行くところ。駅と駅の間ごとに引く。
    /// **道路沿いの形が取れていればそれを、無ければ直線を**使う
    private var plannedLegs: [Leg] {
        zip(stations, stations.dropFirst()).map { from, to in
            let line = routes.coordinates(from: from.orderNo, to: to.orderNo)
                ?? [coordinate(from), coordinate(to)]
            return Leg(id: "\(from.orderNo)-\(to.orderNo)", points: line)
        }
    }

    struct TrackLeg: Identifiable {
        let id: Int
        let points: [CLLocationCoordinate2D]
        let minutesPerKilometer: Double?
    }

    /// 実際に歩いた跡を200mごとに刻んだもの。
    /// 刻む計算は `RailAngyerCore` にあり、テストで固定してある
    private var trackSegments: [TrackLeg] {
        let fixes = store.trackPoints.map {
            TrackSegments.Fix(latitude: $0.latitude, longitude: $0.longitude, time: $0.recordedAt)
        }
        return TrackSegments.split(fixes).map { segment in
            TrackLeg(id: segment.id,
                     points: segment.fixes.map {
                         CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                     },
                     minutesPerKilometer: segment.minutesPerKilometer)
        }
    }

    struct WalkedLeg: Identifiable {
        let id: UUID
        let points: [CLLocationCoordinate2D]
        let minutesPerKilometer: Double?
    }

    /// 実際に通った区間。戻る効果やジャンプで同じ区間を何度も通ることがあるので、
    /// **1区間ずつ引く**（つないで1本にすると、後から通った速さで塗り替わってしまう）
    private var walkedLegs: [WalkedLeg] {
        let byOrder = Dictionary(uniqueKeysWithValues:
            (store.room?.course?.stations ?? []).map { ($0.orderNo, $0) })

        return store.legs.compactMap { leg in
            guard let from = byOrder[leg.fromOrder], let to = byOrder[leg.toOrder] else { return nil }
            return WalkedLeg(id: leg.id,
                             points: [coordinate(from), coordinate(to)],
                             minutesPerKilometer: leg.pace.minutesPerKilometer)
        }
    }

    // MARK: - 凡例

    private var legend: some View {
        VStack(spacing: 5) {
            HStack {
                Text("速い")
                Spacer()
                Text("標準")
                Spacer()
                Text("ゆっくり")
            }
            Capsule().fill(PacePalette.gradient).frame(width: 190, height: 7)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Capsule().fill(Theme.line.opacity(0.5)).frame(width: 14, height: 4)
                    Text("これから")
                }
                HStack(spacing: 4) {
                    Capsule().fill(Theme.ink.opacity(0.6)).frame(width: 14, height: 5)
                    Text("歩いた跡は200mごとに色分け")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .padding(.bottom, 6)
    }

    // MARK: - カメラ

    /// 区間全体が入るように寄せる
    private func fitToSection() {
        guard !stations.isEmpty else { return }
        let lats = stations.map(\.latitude)
        let lons = stations.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.01),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.4, 0.01))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}
