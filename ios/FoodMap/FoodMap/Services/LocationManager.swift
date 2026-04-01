// 定位管理器
// 负责获取用户当前位置，供地图页面使用

import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    // 用户当前位置
    @Published var userLocation: CLLocationCoordinate2D?
    // 定位授权状态
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    // 定位错误信息
    @Published var errorMessage: String?

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    // 请求定位权限
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    // 开始定位
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    // 停止定位
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.userLocation = location.coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "定位失败：\(error.localizedDescription)"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdatingLocation()
            case .denied, .restricted:
                self.errorMessage = "定位权限被拒绝，请在设置中开启"
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
