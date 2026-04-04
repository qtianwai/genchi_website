// 他人地图 ViewModel（v6.0 新增）
// 管理他人地图的数据加载、隐私检查、订阅状态

import Foundation

@MainActor
class UserMapViewModel: ObservableObject {
    @Published var mapInfo: UserMapInfo?
    @Published var restaurants: [UserMapRestaurantItem] = []
    @Published var isLoading = false
    @Published var isPrivate = false
    @Published var errorMessage: String?

    func loadMapInfo(targetUserId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let info = try await APIService.shared.getUserMapInfo(targetUserId: targetUserId)

            // 检查是否为私密地图（is_public == false 表示私密）
            if !info.is_public {
                self.isPrivate = true
                self.mapInfo = nil
            } else {
                self.mapInfo = info
                self.isPrivate = false
                // 加载店铺列表
                await loadRestaurants(targetUserId: targetUserId)
            }
        } catch {
            errorMessage = "加载地图信息失败：\(error.localizedDescription)"
            print("[他人地图] 加载失败: \(error)")
        }
    }

    func loadRestaurants(targetUserId: String) async {
        do {
            let response = try await APIService.shared.getUserMapRestaurants(
                targetUserId: targetUserId,
                page: 1
            )

            if response.is_private ?? false {
                self.isPrivate = true
                self.restaurants = []
            } else {
                self.restaurants = response.restaurants
            }
        } catch {
            errorMessage = "加载店铺列表失败：\(error.localizedDescription)"
            print("[他人地图] 加载店铺失败: \(error)")
        }
    }

    func refresh(targetUserId: String) async {
        await loadMapInfo(targetUserId: targetUserId)
    }

    // 订阅他人地图
    func subscribeMap(targetUserId: String) async throws {
        guard let userId = UserDefaults.standard.string(forKey: "user_id") else {
            throw NSError(domain: "UserMapViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "未登录"])
        }
        try await APIService.shared.subscribeUserMap(subscriberId: userId, targetUserId: targetUserId)
    }
}
