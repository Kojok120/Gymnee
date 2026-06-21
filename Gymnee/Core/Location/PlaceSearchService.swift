import Foundation
import MapKit

/// 地図上の場所（POI）から見つけた近隣ジム。DB 未登録でも候補に出すための値。
struct NearbyPlace: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let lat: Double
    let lng: Double
    let address: String?
    var distance: Double?
}

/// MapKit のローカル POI 検索で現在地周辺のジム（fitnessCenter）を探す（§6.3 強化）。
/// DB に未登録の「初訪問ジム」も検出できるのが狙い。
struct PlaceSearchService {
    /// 現在地周辺のフィットネス系 POI を返す。失敗時は空配列。
    func nearbyGyms(around center: CLLocationCoordinate2D, radius: CLLocationDistance = 1200) async -> [NearbyPlace] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        let search = MKLocalSearch(request: request)
        return await withCheckedContinuation { continuation in
            search.start { response, _ in
                let places: [NearbyPlace] = (response?.mapItems ?? []).compactMap { item in
                    guard let location = item.placemark.location else { return nil }
                    return NearbyPlace(
                        name: item.name ?? item.placemark.name ?? "ジム",
                        lat: location.coordinate.latitude,
                        lng: location.coordinate.longitude,
                        address: item.placemark.title
                    )
                }
                continuation.resume(returning: places)
            }
        }
    }
}
