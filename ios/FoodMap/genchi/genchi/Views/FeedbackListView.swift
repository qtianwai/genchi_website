// 用户反馈列表页（v15.0 新增）
// 展示用户提交的所有反馈，支持下拉刷新，右上角「+」提交新反馈

import SwiftUI

struct FeedbackListView: View {
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = FeedbackViewModel()
    @State private var showSubmitSheet = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.feedbacks.isEmpty {
                // 首次加载
                ProgressView("加载中...")
            } else if viewModel.feedbacks.isEmpty {
                // 空状态
                VStack(spacing: DS.Spacing.lg) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("暂无反馈记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("提交反馈") {
                        showSubmitSheet = true
                    }
                    .foregroundColor(DS.Color.brand)
                }
            } else {
                List {
                    ForEach(viewModel.feedbacks) { feedback in
                        NavigationLink(destination: FeedbackDetailView(feedbackId: feedback.id).environmentObject(authState)) {
                            FeedbackRowView(feedback: feedback)
                        }
                    }

                    // 加载更多
                    if viewModel.hasMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .onAppear {
                                    Task { await viewModel.loadMore(userId: authState.userId) }
                                }
                            Spacer()
                        }
                    }
                }
                .refreshable {
                    await viewModel.loadFeedbacks(userId: authState.userId)
                }
            }
        }
        .navigationTitle("意见反馈")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSubmitSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showSubmitSheet) {
            FeedbackSubmitSheet(onSuccess: {
                Task { await viewModel.loadFeedbacks(userId: authState.userId) }
            })
            .environmentObject(authState)
        }
        .onAppear {
            if viewModel.feedbacks.isEmpty {
                Task { await viewModel.loadFeedbacks(userId: authState.userId) }
            }
        }
    }
}

// MARK: - 反馈列表行视图

struct FeedbackRowView: View {
    let feedback: UserFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // 第一行：分类标签 + 状态
            HStack {
                Text(feedback.categoryText)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DS.Color.brand.opacity(0.15))
                    .foregroundColor(DS.Color.brand)
                    .cornerRadius(4)

                Spacer()

                // 状态标签
                HStack(spacing: 4) {
                    Circle()
                        .fill(feedback.statusColor)
                        .frame(width: 6, height: 6)
                    Text(feedback.statusText)
                        .font(.caption)
                        .foregroundColor(feedback.statusColor)
                }
            }

            // 内容摘要
            Text(feedback.content)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)

            // 底部：时间 + 回复数
            HStack {
                if let createdAt = feedback.created_at {
                    Text(formatDate(createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let count = feedback.reply_count, count > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.right")
                            .font(.caption2)
                        Text("\(count)")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // 格式化日期：显示 "MM-dd HH:mm" 或 "yyyy-MM-dd"
    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr) else {
            // 尝试不带毫秒的格式
            formatter.formatOptions = [.withInternetDateTime]
            guard let date2 = formatter.date(from: dateStr) else { return dateStr.prefix(10).description }
            return formatOutput(date2)
        }
        return formatOutput(date)
    }

    private func formatOutput(_ date: Date) -> String {
        let display = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            display.dateFormat = "MM-dd HH:mm"
        } else {
            display.dateFormat = "yyyy-MM-dd"
        }
        return display.string(from: date)
    }
}
