// 地图页面 ViewModel
// 管理地图页面的数据状态和业务逻辑

import Foundation
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
    // 地图区域（默认显示全国）
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.5, longitude: 114.3),
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    )

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
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }
}
