// 地图订阅管理 ViewModel（v6.0 新增）
// 管理用户的订阅列表、订阅/取消订阅、开关切换

import Foundation

@MainActor
class MapSubscriptionsViewModel: ObservableObject {
    @Published var subscriptions: [MapSubscription] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadSubscriptions(userId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            subscriptions = try await APIService.shared.getMapSubscriptions(userId: userId)
        } catch {
            errorMessage = "加载订阅列表失败：\(error.localizedDescription)"
            print("[订阅管理] 加载失败: \(error)")
        }
    }

    func toggleSubscription(subscriberId: String, targetUserId: String, isEnabled: Bool) async {
        // 乐观更新：先更新本地状态
        if let idx = subscriptions.firstIndex(where: { $0.target_user_id == targetUserId }) {
            subscriptions[idx].is_enabled = isEnabled
        }

        do {
            try await APIService.shared.toggleMapSubscription(
                subscriberId: subscriberId,
                targetUserId: targetUserId,
                isEnabled: isEnabled
            )
        } catch {
            // 失败回滚
            if let idx = subscriptions.firstIndex(where: { $0.target_user_id == targetUserId }) {
                subscriptions[idx].is_enabled = !isEnabled
            }
            errorMessage = "切换失败：\(error.localizedDescription)"
            print("[订阅管理] 切换失败: \(error)")
        }
    }

    func unsubscribe(subscriberId: String, targetUserId: String) async {
        do {
            try await APIService.shared.unsubscribeUserMap(
                subscriberId: subscriberId,
                targetUserId: targetUserId
            )
            // 成功后移除本地记录
            subscriptions.removeAll { $0.target_user_id == targetUserId }
        } catch {
            errorMessage = "取消订阅失败：\(error.localizedDescription)"
            print("[订阅管理] 取消订阅失败: \(error)")
        }
    }
}
