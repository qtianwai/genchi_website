// 管理员反馈列表 ViewModel（v15.0 新增）
// 管理反馈列表的加载、状态筛选、分页

import SwiftUI

@MainActor
class AdminFeedbackViewModel: ObservableObject {
    @Published var selectedStatus: String = "all"  // all / pending / in_progress / resolved
    @Published var items: [AdminFeedbackItem] = []
    @Published var total = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentPage = 1
    private let pageSize = 20

    /// 是否还有更多数据
    var hasMore: Bool { items.count < total }

    /// 加载第一页
    func loadItems(userId: String) async {
        currentPage = 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIService.shared.adminGetFeedbackList(
                page: 1, status: selectedStatus, userId: userId
            )
            items = response.items
            total = response.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 加载更多（下一页）
    func loadMore(userId: String) async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let nextPage = currentPage + 1
            let response = try await APIService.shared.adminGetFeedbackList(
                page: nextPage, status: selectedStatus, userId: userId
            )
            items.append(contentsOf: response.items)
            total = response.total
            currentPage = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 切换状态筛选并重新加载
    func switchStatus(_ status: String, userId: String) async {
        selectedStatus = status
        await loadItems(userId: userId)
    }
}
