import SwiftUI
import MapKit
import CoreLocation

/// 次の駅と現在地を示す地図（SC-07）。
///
/// **到着判定の半径を円で描く**のが要点。数字の距離だけでは、
/// 現地で判定が合わなかったときに「座標が悪いのか測位が悪いのか」を切り分けられない
/// （フェーズ1の検証項目「駅座標の精度と150m判定」）。
struct StationMapView: View {

    let target: LocationService.Target
    let userLocation: CLLocation?
    /// 到着判定の半径（メートル）
    let radius: Double

    @State private var camera: MapCameraPosition = .automatic

    private var targetCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
    }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()

            Annotation(target.name, coordinate: targetCoordinate) {
                ZStack {
                    Circle().fill(Theme.line)
                    Image(systemName: "tram.fill")
                        .font(.caption).foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
            }

            // 到着判定の圏内
            MapCircle(center: targetCoordinate, radius: radius)
                .foregroundStyle(Theme.line.opacity(0.12))
                .stroke(Theme.line.opacity(0.7), lineWidth: 2)
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onAppear { fit() }
        .onChange(of: target) { fit() }
    }

    /// 駅と現在地の両方が入るように寄せる。
    /// 現在地の更新ごとには動かさない（見ている最中に勝手に動くのを避けるため）
    private func fit() {
        guard let user = userLocation else {
            camera = .region(MKCoordinateRegion(center: targetCoordinate,
                                                latitudinalMeters: radius * 4,
                                                longitudinalMeters: radius * 4))
            return
        }
        let center = CLLocationCoordinate2D(
            latitude: (targetCoordinate.latitude + user.coordinate.latitude) / 2,
            longitude: (targetCoordinate.longitude + user.coordinate.longitude) / 2)
        let distance = user.distance(from: target.location)
        let span = max(distance * 1.8, radius * 4)
        camera = .region(MKCoordinateRegion(center: center,
                                            latitudinalMeters: span,
                                            longitudinalMeters: span))
    }
}

extension LocationService.Target {
    /// 純正マップアプリを徒歩モードで開く。
    /// 経路案内は自前で作らず、マップアプリに任せる
    func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
