// 用户反馈详情页（v15.0 新增）
// 展示反馈完整内容、截图、设备信息、管理员回复列表

import SwiftUI

struct FeedbackDetailView: View {
    @EnvironmentObject var authState: AuthState
    let feedbackId: String

    @State private var feedback: UserFeedback?
    @State private var replies: [FeedbackReply] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDeviceInfo = false  // 设备信息折叠

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
            } else if let feedback = feedback {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                        // 顶部：分类 + 状态
                        HStack {
                            Text(feedback.categoryText)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DS.Color.brand.opacity(0.15))
                                .foregroundColor(DS.Color.brand)
                                .cornerRadius(4)

                            Spacer()

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(feedback.statusColor)
                                    .frame(width: 8, height: 8)
                                Text(feedback.statusText)
                                    .font(.subheadline)
                                    .foregroundColor(feedback.statusColor)
                            }
                        }

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
                                                .frame(width: 120, height: 120)
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

                        // 分隔线
                        Divider()

                        // 回复列表
                        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                            Text("处理记录")
                                .font(.subheadline.weight(.medium))

                            if replies.isEmpty {
                                Text("暂无回复")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, DS.Spacing.lg)
                            } else {
                                ForEach(replies) { reply in
                                    replyBubble(reply)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.lg)
                }
            } else if let error = errorMessage {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("反馈详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDetail() }
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

    // MARK: - 加载数据

    private func loadDetail() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                let response = try await APIService.shared.getFeedbackDetail(
                    feedbackId: feedbackId, userId: authState.userId
                )
                feedback = response.feedback
                replies = response.replies
            } catch {
                errorMessage = error.localizedDescription
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
