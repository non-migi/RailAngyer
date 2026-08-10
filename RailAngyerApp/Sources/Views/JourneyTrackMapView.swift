import SwiftUI
import MapKit
import RailAngyerCore

/// ふりかえりに出す、その旅ぜんぶの地図。
///
/// **数字だけでは、その日の道のりを思い出せない。**
/// 何km歩いたかより「どこを通ったか」のほうが記憶に残る。
///
/// 盤面（`BoardMapView`）と違い、現在地も操作も要らない。
/// 出すのは**歩いた跡・通った駅・撮った写真**の3つだけ。
struct JourneyTrackMapView: View {

    @Bindable var store: GameSessionStore
    /// 押した駅。指定すると詳細を開ける
    var onSelectStation: ((Int) -> Void)?

    @State private var camera: MapCameraPosition = .automatic

    private var stations: [Station] { store.stationsInOrder }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            // 通らなかったところも薄く残す。区間のどこまで行けたかが分かる
            if stations.count >= 2 {
                MapPolyline(coordinates: stations.map(coordinate))
                    .stroke(Theme.line.opacity(0.25),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 8]))
            }

            ForEach(walkedLegs) { leg in
                MapPolyline(coordinates: leg.points)
                    .stroke(PacePalette.color(minutesPerKilometer: leg.minutesPerKilometer),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            ForEach(trackSegments) { segment in
                MapPolyline(coordinates: segment.points)
                    .stroke(PacePalette.color(minutesPerKilometer: segment.minutesPerKilometer),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }

            ForEach(stations) { station in
                Annotation("", coordinate: coordinate(station)) {
                    marker(station)
                        .onTapGesture { onSelectStation?(station.orderNo) }
                }
                .annotationTitles(.hidden)
            }
        }
        .onAppear(perform: fit)
        .onChange(of: stations.map(\.orderNo), fit)
    }

    @ViewBuilder
    private func marker(_ station: Station) -> some View {
        let visited = store.visitedOrders.contains(station.orderNo)
        let landed = store.landedOrders.contains(station.orderNo)
        let photos = store.photoFileNames(at: station.orderNo)

        if let name = photos.first, let image = PhotoStore.load(name) {
            // **撮った写真をそのまま地図に置く。** どこで何を見たかが一目で戻ってくる
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        } else {
            ZStack {
                Circle()
                    .fill(visited ? Theme.line : Color(.systemBackground))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 2))
                if landed {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8)).foregroundStyle(Theme.onLine)
                }
            }
            .frame(width: landed ? 18 : (visited ? 14 : 10),
                   height: landed ? 18 : (visited ? 14 : 10))
        }
    }

    // MARK: - 線

    private func coordinate(_ station: Station) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
    }

    struct Leg: Identifiable {
        let id: String
        let points: [CLLocationCoordinate2D]
        let minutesPerKilometer: Double?
    }

    /// 駅と駅を結んだ線。跡が無い区間の記録として残す
    private var walkedLegs: [Leg] {
        let byOrder = Dictionary(uniqueKeysWithValues:
            (store.room?.course?.stations ?? []).map { ($0.orderNo, $0) })

        return store.legs.compactMap { leg in
            guard let from = byOrder[leg.fromOrder], let to = byOrder[leg.toOrder] else { return nil }
            return Leg(id: leg.id.uuidString,
                       points: [coordinate(from), coordinate(to)],
                       minutesPerKilometer: leg.pace.minutesPerKilometer)
        }
    }

    struct TrackLeg: Identifiable {
        let id: Int
        let points: [CLLocationCoordinate2D]
        let minutesPerKilometer: Double?
    }

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

    /// 歩いた跡まで含めて収める。跡が区間の外へ出ることもある（寄り道）
    private func fit() {
        var lats = stations.map(\.latitude)
        var lons = stations.map(\.longitude)
        lats += store.trackPoints.map(\.latitude)
        lons += store.trackPoints.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.35, 0.008),
                                   longitudeDelta: max((maxLon - minLon) * 1.35, 0.008))))
    }
}
