import Foundation
import CoreLocation
import Observation
import UserNotifications

/// CoreLocation ラッパ（§6.3 GPS によるジム自動補完 / §6.10 ジオフェンス）。
/// 許諾拒否でもアプリは動作する（候補提示が無効になるだけ、§6.1）。
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var current: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// 利用許諾を要求し、許可済みなら現在地の取得を開始する。
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func refresh() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    // MARK: - Geofence (§6.10 ジオフェンス自動チェックイン)

    /// 登録ジム（座標あり）への接近を監視する。iOS の上限 20 リージョンに合わせて先頭 20 件。
    func startMonitoring(gymRegions: [(id: UUID, name: String, lat: Double, lng: Double)]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        for gym in gymRegions.prefix(20) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: gym.lat, longitude: gym.lng),
                radius: 120,
                identifier: gym.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            monitoredGymNames[gym.id.uuidString] = gym.name
            manager.startMonitoring(for: region)
        }
    }

    private var monitoredGymNames: [String: String] = [:]

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in self.suggestCheckIn(regionId: region.identifier) }
    }

    private func suggestCheckIn(regionId: String) {
        let name = monitoredGymNames[regionId] ?? "ジム"
        let content = UNMutableNotificationContent()
        content.title = "\(name) に着きました"
        content.body = "チェックインしますか？📸"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "gymnee.geofence.\(regionId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.current = loc }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 取得失敗は無視（候補提示が出ないだけ）。
    }
}

extension LocationService {
    /// 現在地からの距離（m）。現在地不明なら nil。
    func distance(toLat lat: Double?, lng: Double?) -> CLLocationDistance? {
        guard let current, let lat, let lng else { return nil }
        return current.distance(from: CLLocation(latitude: lat, longitude: lng))
    }
}

/// 距離の人間可読表記。
func formatDistance(_ meters: Double) -> String {
    if meters < 1000 {
        return "\(Int(meters))m"
    }
    return String(format: "%.1fkm", meters / 1000)
}
