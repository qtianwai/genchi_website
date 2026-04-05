// 复核功能 ViewModel
// 管理复核列表的状态：加载、分页、执行复核操作
// 支持待复核（pending）和已复核（reviewed）两个 Tab

import Foundation
import Combine

@MainActor
class ReviewViewModel: ObservableObject {
    // 当前 Tab：pending（待复核）或 reviewed（已复核）
    @Published var selectedTab: ReviewTab = .pending

    // 待复核列表
    @Published var pendingItems: [ReviewItem] = []
    @Published var pendingTotal = 0
    @Published var pendingPage = 1

    // 已复核列表
    @Published var reviewedItems: [ReviewItem] = []
    @Published var reviewedTotal = 0
    @Published var reviewedPage = 1

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let pageSize = 20

    // 当前 Tab 的数据
    var items: [ReviewItem] { selectedTab == .pending ? pendingItems : reviewedItems }
    var totalCount: Int { selectedTab == .pending ? pendingTotal : reviewedTotal }
    var hasMore: Bool { items.count < totalCount }

    // 切换 Tab 时自动加载对应数据
    func switchTab(_ tab: ReviewTab, userId: String) async {
        selectedTab = tab
        let list = tab == .pending ? pendingItems : reviewedItems
        if list.isEmpty {
            await loadItems(userId: userId)
        }
    }

    // 加载第一页（下拉刷新时调用）
    func loadItems(userId: String) async {
        isLoading = true
        errorMessage = nil
        let tab = selectedTab
        do {
            let resp = try await APIService.shared.getReviewList(page: 1, tab: tab.rawValue, userId: userId)
            if tab == .pending {
                pendingItems = resp.items
                pendingTotal = resp.total
                pendingPage = 1
            } else {
                reviewedItems = resp.items
                reviewedTotal = resp.total
                reviewedPage = 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // 加载下一页（滚动到底部时调用）
    func loadMore(userId: String) async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        let tab = selectedTab
        let nextPage = (tab == .pending ? pendingPage : reviewedPage) + 1
        do {
            let resp = try await APIService.shared.getReviewList(page: nextPage, tab: tab.rawValue, userId: userId)
            if tab == .pending {
                pendingItems.append(contentsOf: resp.items)
                pendingTotal = resp.total
                pendingPage = nextPage
            } else {
                reviewedItems.append(contentsOf: resp.items)
                reviewedTotal = resp.total
                reviewedPage = nextPage
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // 从待复核列表中移除已复核的记录（复核操作完成后调用）
    // 同时将已复核 Tab 的计数 +1，保持两个 Tab 数字同步
    func removeFromPending(id: String) {
        pendingItems.removeAll { $0.id == id }
        pendingTotal = max(0, pendingTotal - 1)
        reviewedTotal += 1
    }

    // 刷新已复核列表（二次调整后调用）
    func refreshReviewed(userId: String) async {
        reviewedItems = []
        reviewedTotal = 0
        reviewedPage = 1
        let savedTab = selectedTab
        selectedTab = .reviewed
        await loadItems(userId: userId)
        selectedTab = savedTab
    }
}

// Tab 枚举
enum ReviewTab: String {
    case pending = "pending"
    case reviewed = "reviewed"
}
