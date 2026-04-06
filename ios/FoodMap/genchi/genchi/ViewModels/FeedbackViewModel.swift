// 用户反馈列表 ViewModel（v15.0 新增）
// 管理用户反馈列表的加载、分页、刷新

import SwiftUI

@MainActor
class FeedbackViewModel: ObservableObject {
    @Published var feedbacks: [UserFeedback] = []
    @Published var total = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentPage = 1
    private let pageSize = 20

    /// 是否还有更多数据
    var hasMore: Bool { feedbacks.count < total }

    /// 加载第一页
    func loadFeedbacks(userId: String) async {
        currentPage = 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIService.shared.getFeedbackList(userId: userId, page: 1)
            feedbacks = response.items
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
            let response = try await APIService.shared.getFeedbackList(userId: userId, page: nextPage)
            feedbacks.append(contentsOf: response.items)
            total = response.total
            currentPage = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
