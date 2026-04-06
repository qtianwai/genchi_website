// 冷启动博主录入主页面
// v14.0 新增：管理员查看已录入博主列表，提交新的冷启动任务

import SwiftUI

struct ColdStartView: View {
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = ColdStartViewModel()
    @State private var showSubmitSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.authors.isEmpty && !viewModel.isLoading {
                    // 空状态
                    VStack(spacing: DS.Spacing.lg) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("还没有录入博主")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("点击右上角「+」录入博主视频")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                } else {
                    List {
                        ForEach(viewModel.authors) { author in
                            NavigationLink(destination: AuthorDetailView(
                                author: Author(
                                    id: author.id,
                                    douyin_uid: author.douyin_uid ?? "",
                                    name: author.name,
                                    avatar_url: author.avatar_url,
                                    created_at: nil
                                )
                            )) {
                                ColdStartAuthorRow(author: author)
                            }
                        }

                        // 加载更多
                        if viewModel.authors.count < viewModel.total {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .onAppear {
                                        Task {
                                            await viewModel.loadMore(userId: authState.userId)
                                        }
                                    }
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.loadAuthors(userId: authState.userId)
                    }
                }

                // 加载中
                if viewModel.isLoading && viewModel.authors.isEmpty {
                    ProgressView("加载中...")
                }
            }
            .navigationTitle("博主录入")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSubmitSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSubmitSheet) {
                ColdStartSubmitSheet(
                    onSuccess: {
                        Task {
                            await viewModel.loadAuthors(userId: authState.userId)
                        }
                    }
                )
                .environmentObject(authState)
            }
            .onAppear {
                if viewModel.authors.isEmpty {
                    Task {
                        await viewModel.loadAuthors(userId: authState.userId)
                    }
                }
            }
            .onDisappear {
                viewModel.stopAllPolling()
            }
            // 错误提示
            .overlay(alignment: .bottom) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { viewModel.errorMessage = nil }
                            }
                        }
                }
            }
        }
    }
}

// ─────────────────────────────────────────
// 博主列表行
// ─────────────────────────────────────────
struct ColdStartAuthorRow: View {
    let author: ColdStartAuthor

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // 博主头像
            AsyncImage(url: URL(string: author.avatar_url ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            // 博主信息
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(author.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let task = author.task {
                    HStack(spacing: DS.Spacing.sm) {
                        taskStatusView(task: task)
                        if let cost = task.api_cost, cost > 0 {
                            Text("¥\(String(format: "%.2f", cost))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // 右侧状态
            if let task = author.task {
                VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                    taskBadge(status: task.status)
                    if let createdAt = task.created_at {
                        Text(formatDate(createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func taskStatusView(task: ColdStartTask) -> some View {
        switch task.status {
        case "completed":
            if let count = task.food_videos_found {
                Text("\(count) 条美食视频")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case "running", "pending":
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("处理中...")
                    .font(.caption)
                    .foregroundColor(DS.Color.brand)
            }
        case "failed":
            Text(task.error_message ?? "任务失败")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func taskBadge(status: String) -> some View {
        switch status {
        case "completed":
            Label("完成", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(DS.Color.success)
        case "running", "pending":
            Label("进行中", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundColor(DS.Color.brand)
        case "failed":
            Label("失败", systemImage: "xmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.red)
        default:
            EmptyView()
        }
    }

    // 格式化日期（只显示月-日）
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.dateFormat = "MM-dd"
            return df.string(from: date)
        }
        // 兜底：截取前 10 位
        if isoString.count >= 10 {
            let start = isoString.index(isoString.startIndex, offsetBy: 5)
            let end = isoString.index(isoString.startIndex, offsetBy: 10)
            return String(isoString[start..<end])
        }
        return isoString
    }
}
