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

/// MapKit で現在地周辺のジムを探す（§6.3 強化）。DB 未登録の「初訪問ジム」も検出する。
///
/// `.fitnessCenter` カテゴリの POI 検索だけだと、Apple Maps 上でフィットネス扱いに
/// なっていない店舗（例: FIT PLACE 24 等）が漏れる。そこでカテゴリ検索に加えて
/// 「フィットネス」「ジム」のテキスト検索を併用し、結果をマージして取りこぼしを減らす。
struct PlaceSearchService {
    /// 現在地周辺のジム候補を返す。失敗時は空配列。
    func nearbyGyms(around center: CLLocationCoordinate2D, radius: CLLocationDistance = 2000) async -> [NearbyPlace] {
        async let poi = poiSearch(center: center, radius: radius)
        async let byFitness = textSearch("フィットネス", center: center, radius: radius)
        async let byGym = textSearch("ジム", center: center, radius: radius)
        async let by24 = textSearch("24時間ジム", center: center, radius: radius)

        let merged = await poi + byFitness + byGym + by24
        // 名前＋座標（約100m）でデデュープ。
        var seen = Set<String>()
        var result: [NearbyPlace] = []
        for place in merged {
            let key = "\(place.name)|\(String(format: "%.3f,%.3f", place.lat, place.lng))"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(place)
        }
        return result
    }

    // MARK: - カテゴリ検索（.fitnessCenter）

    private func poiSearch(center: CLLocationCoordinate2D, radius: CLLocationDistance) async -> [NearbyPlace] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        return await run(MKLocalSearch(request: request), center: center, maxDistance: nil)
    }

    // MARK: - テキスト検索（取りこぼし対策）

    private func textSearch(_ query: String, center: CLLocationCoordinate2D, radius: CLLocationDistance) async -> [NearbyPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        request.resultTypes = .pointOfInterest
        // テキスト検索は region 外も返すため、半径で絞る。
        return await run(MKLocalSearch(request: request), center: center, maxDistance: radius)
    }

    private func run(_ search: MKLocalSearch, center: CLLocationCoordinate2D, maxDistance: CLLocationDistance?) async -> [NearbyPlace] {
        await withCheckedContinuation { continuation in
            search.start { response, _ in
                let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
                let places: [NearbyPlace] = (response?.mapItems ?? []).compactMap { item in
                    guard let location = item.placemark.location else { return nil }
                    if let maxDistance, location.distance(from: origin) > maxDistance { return nil }
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
