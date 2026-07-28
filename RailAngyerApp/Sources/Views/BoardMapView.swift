import SwiftUI
import MapKit
import RailAngyerCore

/// 盤面の地図表示（SC-04）。区間の全駅を地図に出し、進捗を一目で見せる。
///
/// **現地でマスタの座標が実際の駅とどれだけズレているかを確認する用途も兼ねる**
/// （フェーズ1の検証項目「駅座標の精度」）。一覧では1駅ずつしか見られない。
///
/// 線の引き分け:
/// - **これから行くところ**は点線。まだ歩いていないことを一目で分かるようにする
/// - **実際に通ったところ**は実線で、**その区間の速さで色を変える**
///   （速い=青 / ふつう=緑 / ゆっくり=赤）
struct BoardMapView: View {
    @Bindable var store: GameSessionStore
    @Binding var selectedStation: StationSelection?

    @State private var camera: MapCameraPosition = .automatic

    private var stations: [Station] { store.stationsInOrder }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()

            // これから行くところ。点線
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Theme.line.opacity(0.5), style: plannedStyle)
            }

            // 実際に通ったところ。実線、速さで色分け
            ForEach(walkedLegs) { leg in
                MapPolyline(coordinates: leg.points)
                    .stroke(color(for: leg.category), style: walkedStyle)
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
    }

    // MARK: - 駅のマーカー

    @ViewBuilder
    private func marker(for station: Station) -> some View {
        let isCurrent = station.orderNo == store.currentOrder
        let isVisited = store.visitedOrders.contains(station.orderNo)
        let isLanded = store.landedOrders.contains(station.orderNo)
        let hasPhoto = store.photographedOrders.contains(station.orderNo)

        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(isVisited ? Theme.line : Color(.systemBackground))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: isCurrent ? 4 : 2))
                if isLanded {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9)).foregroundStyle(.white)
                }
            }
            .frame(width: isCurrent ? 26 : (isVisited ? 18 : 14),
                   height: isCurrent ? 26 : (isVisited ? 18 : 14))

            // 写真を撮った駅。あとで見返すとき、どこで撮ったかが地図で分かる
            if hasPhoto {
                Image(systemName: "camera.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(.orange))
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("\(station.name)で撮った写真がある")
            }
        }
        .frame(width: 32, height: 32)
        .shadow(radius: isCurrent ? 3 : 0)
    }

    // MARK: - 線

    private var plannedStyle: StrokeStyle {
        StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [2, 10])
    }

    private var walkedStyle: StrokeStyle {
        StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
    }

    /// 速さの色。**色だけに頼らせない**ため、凡例と数字も併せて出す
    private func color(for category: PaceCategory?) -> Color {
        switch category {
        case .fast:   return .blue
        case .normal: return Theme.line
        case .slow:   return .red
        case nil:     return Theme.line.opacity(0.6)   // 測れなかった区間
        }
    }

    private func coordinate(_ station: Station) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
    }

    private var coordinates: [CLLocationCoordinate2D] { stations.map(coordinate) }

    struct WalkedLeg: Identifiable {
        let id: UUID
        let points: [CLLocationCoordinate2D]
        let category: PaceCategory?
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
                             category: leg.category)
        }
    }

    // MARK: - 凡例

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(PaceCategory.allCases, id: \.self) { category in
                HStack(spacing: 4) {
                    Capsule().fill(color(for: category)).frame(width: 14, height: 4)
                    Text(category.label)
                }
            }
            HStack(spacing: 4) {
                Capsule().fill(Theme.line.opacity(0.5)).frame(width: 14, height: 4)
                Text("これから")
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
