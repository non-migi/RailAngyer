import SwiftUI
import MapKit
import RailAngyerCore

/// 盤面の地図表示（SC-04）。区間の全駅を地図に出し、進捗を一目で見せる。
///
/// **現地でマスタの座標が実際の駅とどれだけズレているかを確認する用途も兼ねる**
/// （フェーズ1の検証項目「駅座標の精度」）。一覧では1駅ずつしか見られない。
struct BoardMapView: View {
    @Bindable var store: GameSessionStore
    @Binding var selectedStation: StationSelection?

    @State private var camera: MapCameraPosition = .automatic

    private var stations: [Station] { store.stationsInOrder }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()

            // 区間全体の線（薄い）
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Theme.line.opacity(0.25), style: lineStyle)
            }

            // 歩いた区間の線（濃い）。飛び飛びになることもあるので区間ごとに引く
            ForEach(walkedSegments) { segment in
                MapPolyline(coordinates: segment.points)
                    .stroke(Theme.line, style: lineStyle)
            }

            ForEach(stations) { station in
                Annotation(station.name, coordinate: coordinate(station)) {
                    marker(for: station)
                        .onTapGesture { selectedStation = StationSelection(id: station.orderNo) }
                }
            }
        }
        .mapControls { MapUserLocationButton() }
        .onAppear(perform: fitToSection)
        .onChange(of: stations.count, fitToSection)
    }

    // MARK: - 駅のマーカー

    @ViewBuilder
    private func marker(for station: Station) -> some View {
        let isCurrent = station.orderNo == store.currentOrder
        let isVisited = store.visitedOrders.contains(station.orderNo)
        let isLanded = store.landedOrders.contains(station.orderNo)

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
        .shadow(radius: isCurrent ? 3 : 0)
    }

    private var lineStyle: StrokeStyle {
        StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    }

    // MARK: - 線

    private func coordinate(_ station: Station) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
    }

    private var coordinates: [CLLocationCoordinate2D] { stations.map(coordinate) }

    /// 連続して訪問済みの区間
    struct WalkedSegment: Identifiable {
        let id: Int              // 区間の先頭の駅番号
        let points: [CLLocationCoordinate2D]
    }

    /// 訪問済みの駅が隣り合っている区間だけを濃く描く。
    /// 戻る効果やジャンプで飛び飛びに訪れることがあるため、単純な前方一致では表せない
    private var walkedSegments: [WalkedSegment] {
        var segments: [WalkedSegment] = []
        var current: [Station] = []

        func flush() {
            if current.count >= 2, let head = current.first {
                segments.append(WalkedSegment(id: head.orderNo,
                                              points: current.map(coordinate)))
            }
            current = []
        }

        for station in stations {
            if store.visitedOrders.contains(station.orderNo) {
                current.append(station)
            } else {
                flush()
            }
        }
        flush()
        return segments
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
