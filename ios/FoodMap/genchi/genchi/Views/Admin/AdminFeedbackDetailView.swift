// 管理员反馈详情页（v15.0 新增）
// 查看反馈完整内容、截图、设备信息，回复用户，更新状态

import SwiftUI

struct AdminFeedbackDetailView: View {
    @EnvironmentObject var authState: AuthState
    let feedbackItem: AdminFeedbackItem

    @State private var feedback: UserFeedback?
    @State private var replies: [FeedbackReply] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // 回复输入
    @State private var replyContent = ""
    @State private var isSendingReply = false
    @State private var replyError: String?

    // 状态更新
    @State private var isUpdatingStatus = false
    @State private var showDeviceInfo = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let feedback = feedback {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                        // 用户信息区
                        HStack(spacing: DS.Spacing.md) {
                            if let urlStr = feedbackItem.avatar_url, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    defaultAvatar
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            } else {
                                defaultAvatar
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(feedbackItem.nickname ?? "美食探索者")
                                    .font(.subheadline.weight(.medium))
                                Text("ID: \(feedbackItem.user_id.prefix(8))...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 状态切换菜单
                            Menu {
                                Button("标记为处理中") {
                                    Task { await updateStatus("in_progress") }
                                }
                                Button("标记为已解决") {
                                    Task { await updateStatus("resolved") }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(feedback.statusColor)
                                        .frame(width: 8, height: 8)
                                    Text(feedback.statusText)
                                        .font(.caption)
                                        .foregroundColor(feedback.statusColor)
                                    if isUpdatingStatus {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(feedback.statusColor.opacity(0.1))
                                )
                            }
                            .disabled(isUpdatingStatus)
                        }

                        // 分类标签
                        Text(feedback.categoryText)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DS.Color.brand.opacity(0.15))
                            .foregroundColor(DS.Color.brand)
                            .cornerRadius(4)

                        // 反馈内容
                        Text(feedback.content)
                            .font(.body)

                        // 截图展示
                        if let urls = feedback.image_urls, !urls.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                Text("截图")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: DS.Spacing.sm) {
                                        ForEach(urls, id: \.self) { urlStr in
                                            if let url = URL(string: urlStr) {
                                                AsyncImage(url: url) { image in
                                                    image.resizable().scaledToFill()
                                                } placeholder: {
                                                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                                                        .fill(Color(.systemGray5))
                                                        .overlay(ProgressView())
                                                }
                                                .frame(width: 150, height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 设备信息（可折叠）
                        DisclosureGroup("设备信息", isExpanded: $showDeviceInfo) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let model = feedback.device_model {
                                    infoRow("设备", model)
                                }
                                if let ios = feedback.ios_version {
                                    infoRow("iOS", ios)
                                }
                                if let app = feedback.app_version {
                                    infoRow("App 版本", app)
                                }
                                if let time = feedback.created_at {
                                    infoRow("提交时间", formatDate(time))
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Divider()

                        // 回复列表
                        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                            Text("回复记录 (\(replies.count))")
                                .font(.subheadline.weight(.medium))

                            if replies.isEmpty {
                                Text("暂无回复")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, DS.Spacing.md)
                            } else {
                                ForEach(replies) { reply in
                                    replyBubble(reply)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.lg)
                    .padding(.bottom, 80) // 为底部输入框留空间
                }

                // 底部回复输入区
                replyInputBar
            } else if let error = errorMessage {
                Spacer()
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("反馈详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDetail() }
    }

    // MARK: - 底部回复输入栏

    private var replyInputBar: some View {
        VStack(spacing: 0) {
            Divider()

            if let error = replyError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, 4)
            }

            HStack(spacing: DS.Spacing.sm) {
                TextField("输入回复内容...", text: $replyContent, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .fill(Color(.systemGray6))
                    )

                Button(action: sendReply) {
                    if isSendingReply {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(replyContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : DS.Color.brand)
                    }
                }
                .disabled(replyContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingReply)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - 回复气泡

    @ViewBuilder
    private func replyBubble(_ reply: FeedbackReply) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.caption)
                    .foregroundColor(DS.Color.info)
                Text("管理员")
                    .font(.caption)
                    .foregroundColor(DS.Color.info)
                Spacer()
                if let time = reply.created_at {
                    Text(formatDate(time))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Text(reply.content)
                .font(.subheadline)
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(DS.Color.info.opacity(0.08))
        )
    }

    // MARK: - 辅助视图

    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.15))
                .frame(width: 40, height: 40)
            Image(systemName: "person.fill")
                .font(.subheadline)
                .foregroundColor(.orange)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
        }
        .font(.caption)
    }

    // MARK: - 发送回复

    private func sendReply() {
        let trimmed = replyContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSendingReply = true
        replyError = nil

        Task {
            do {
                try await APIService.shared.adminReplyFeedback(
                    feedbackId: feedbackItem.id,
                    content: trimmed,
                    userId: authState.userId
                )
                replyContent = ""
                // 重新加载详情以刷新回复列表和状态
                loadDetail()
            } catch {
                replyError = "发送失败：\(error.localizedDescription)"
            }
            isSendingReply = false
        }
    }

    // MARK: - 更新状态

    private func updateStatus(_ status: String) async {
        isUpdatingStatus = true
        do {
            try await APIService.shared.adminUpdateFeedbackStatus(
                feedbackId: feedbackItem.id,
                status: status,
                userId: authState.userId
            )
            // 重新加载详情以刷新状态
            loadDetail()
        } catch {
            replyError = "状态更新失败"
        }
        isUpdatingStatus = false
    }

    // MARK: - 加载数据

    private func loadDetail() {
        Task {
            isLoading = feedback == nil // 仅首次显示 loading
            errorMessage = nil
            do {
                let response = try await APIService.shared.getFeedbackDetail(
                    feedbackId: feedbackItem.id, userId: feedbackItem.user_id
                )
                feedback = response.feedback
                replies = response.replies
            } catch {
                if feedback == nil {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    // MARK: - 日期格式化

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date2 = formatter.date(from: dateStr) else { return dateStr.prefix(16).description }
            return formatOutput(date2)
        }
        return formatOutput(date)
    }

    private func formatOutput(_ date: Date) -> String {
        let display = DateFormatter()
        display.dateFormat = "MM-dd HH:mm"
        return display.string(from: date)
    }
}
