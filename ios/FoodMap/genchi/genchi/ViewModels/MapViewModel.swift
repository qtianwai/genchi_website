// 地图页面 ViewModel
// 管理地图页面的数据状态和业务逻辑

import Foundation
import SwiftUI
import MapKit
import Combine

@MainActor
class MapViewModel: ObservableObject {
    // 地图上显示的店铺列表
    @Published var mapRestaurants: [MapRestaurant] = []
    // 当前选中的博主过滤器（nil = 显示所有博主）
    @Published var selectedAuthorId: String? = nil
    // 加载状态
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    // 地图相机位置（iOS 17+ 新 API，默认显示全国）
    @Published var mapCameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.5, longitude: 114.3),
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    ))
    // 是否是首次定位（首次定位时自动移动地图到用户位置）
    var isFirstLocationUpdate = true

    // 自动刷新相关
    private var refreshTimer: Timer? = nil
    private var lastRestaurantCount = 0

    // 根据过滤器筛选后的店铺列表
    var filteredRestaurants: [MapRestaurant] {
        guard let authorId = selectedAuthorId else {
            return mapRestaurants
        }
        return mapRestaurants.filter { $0.author_id == authorId }
    }

    // 加载地图数据
    func loadMapData(userId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            mapRestaurants = try await APIService.shared.getMapRestaurants(userId: userId)
            lastRestaurantCount = mapRestaurants.count
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    // 静默刷新地图数据（后台轮询用，不显示 loading 状态）
    func silentRefreshMapData(userId: String) async {
        do {
            let newData = try await APIService.shared.getMapRestaurants(userId: userId)
            // 只有数据真的变化了才更新（避免无意义的 UI 刷新）
            if newData.count != lastRestaurantCount {
                mapRestaurants = newData
                lastRestaurantCount = newData.count
                print("[地图自动刷新] 检测到新店铺，已更新地图（当前 \(newData.count) 家）")
            }
        } catch {
            print("[地图自动刷新] 静默刷新失败: \(error)")
        }
    }

    // 启动自动刷新（每 10 秒检查一次新店铺）
    func startAutoRefresh(userId: String) {
        stopAutoRefresh()  // 先停止旧的 timer
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.silentRefreshMapData(userId: userId)
            }
        }
    }

    // 停止自动刷新
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // 将地图中心移动到用户位置
    func centerMapOnUserLocation(_ location: CLLocationCoordinate2D) {
        mapCameraPosition = .region(MKCoordinateRegion(
            center: location,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
        isFirstLocationUpdate = false
    }
}
