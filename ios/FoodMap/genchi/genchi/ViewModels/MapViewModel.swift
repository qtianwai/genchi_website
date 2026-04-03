// 地图页面 ViewModel
// 管理地图页面的数据状态和业务逻辑

import Foundation
import SwiftUI
import MapKit
import Combine

@MainActor
class MapViewModel: ObservableObject {
    // 地图上显示的店铺列表（博主推荐）
    @Published var mapRestaurants: [MapRestaurant] = []
    // 用户自建推荐店铺列表（v4.0 新增）
    @Published var userRestaurants: [UserCreatedRestaurant] = []
    // 当前选中的博主过滤器（nil = 显示所有博主；"my" = 仅显示我的推荐）
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

    // 根据过滤器筛选后的博主推荐店铺列表
    var filteredRestaurants: [MapRestaurant] {
        // 选中"我的推荐"时，博主推荐不显示
        if selectedAuthorId == "my" { return [] }
        guard let authorId = selectedAuthorId else {
            return mapRestaurants
        }
        return mapRestaurants.filter { $0.author_id == authorId }
    }

    // 根据过滤器筛选后的用户自建推荐列表
    var filteredUserRestaurants: [UserCreatedRestaurant] {
        // 选中某个博主时，不显示用户自建推荐
        if let authorId = selectedAuthorId, authorId != "my" { return [] }
        return userRestaurants
    }

    // 加载地图数据
    func loadMapData(userId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let resp = try await APIService.shared.getMapRestaurants(userId: userId)
            mapRestaurants = resp.restaurants
            userRestaurants = resp.user_restaurants
            lastRestaurantCount = mapRestaurants.count + userRestaurants.count
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    // 静默刷新地图数据（后台轮询用，不显示 loading 状态）
    func silentRefreshMapData(userId: String) async {
        do {
            let resp = try await APIService.shared.getMapRestaurants(userId: userId)
            let newCount = resp.restaurants.count + resp.user_restaurants.count
            // 只有数据真的变化了才更新（避免无意义的 UI 刷新）
            if newCount != lastRestaurantCount {
                mapRestaurants = resp.restaurants
                userRestaurants = resp.user_restaurants
                lastRestaurantCount = newCount
                print("[地图自动刷新] 检测到新店铺，已更新地图（当前 \(newCount) 家）")
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
