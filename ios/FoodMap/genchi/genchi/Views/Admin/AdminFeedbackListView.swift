// 管理员反馈列表页（v15.0 新增）
// 管理员查看所有用户反馈，支持状态筛选，按优先级排序

import SwiftUI

struct AdminFeedbackListView: View {
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = AdminFeedbackViewModel()

    // 状态筛选选项
    private let statusOptions: [(String, String)] = [
        ("all", "全部"),
        ("pending", "待处理"),
        ("in_progress", "处理中"),
        ("resolved", "已解决"),
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部状态筛选
                Picker("状态", selection: $viewModel.selectedStatus) {
                    ForEach(statusOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .onChange(of: viewModel.selectedStatus) { _, newValue in
                    Task { await viewModel.switchStatus(newValue, userId: authState.userId) }
                }

                // 列表内容
                if viewModel.isLoading && viewModel.items.isEmpty {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                } else if viewModel.items.isEmpty {
                    Spacer()
                    VStack(spacing: DS.Spacing.lg) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无反馈")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.items) { item in
                            NavigationLink(destination: AdminFeedbackDetailView(feedbackItem: item).environmentObject(authState)) {
                                AdminFeedbackRowView(item: item)
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
                        await viewModel.loadItems(userId: authState.userId)
                    }
                }
            }
            .navigationTitle("用户反馈")
            .onAppear {
                if viewModel.items.isEmpty {
                    Task { await viewModel.loadItems(userId: authState.userId) }
                }
            }
        }
    }
}

// MARK: - 管理员反馈列表行视图

struct AdminFeedbackRowView: View {
    let item: AdminFeedbackItem

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // 用户头像
            if let urlStr = item.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    defaultAvatar
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                defaultAvatar
            }

            // 内容区
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：昵称 + 分类 + 状态
                HStack {
                    Text(item.nickname ?? "美食探索者")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(item.categoryText)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DS.Color.brand.opacity(0.15))
                        .foregroundColor(DS.Color.brand)
                        .cornerRadius(3)

                    Spacer()

                    HStack(spacing: 3) {
                        Circle()
                            .fill(item.statusColor)
                            .frame(width: 6, height: 6)
                        Text(item.statusText)
                            .font(.caption2)
                            .foregroundColor(item.statusColor)
                    }
                }

                // 内容摘要
                Text(item.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // 底部：时间 + 回复数
                HStack {
                    if let createdAt = item.created_at {
                        Text(formatDate(createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let count = item.reply_count, count > 0 {
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
        }
        .padding(.vertical, 4)
    }

    // 默认头像
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    // 日期格式化
    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr) else {
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
