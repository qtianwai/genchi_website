// 解析抖音链接的底部弹窗
// 用户粘贴抖音链接后，调用后端解析并展示结果
// 支持后台异步解析：当前视频优先快速返回，博主其他视频在后台处理

import SwiftUI

struct ParseLinkSheet: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    let onSuccess: () -> Void

    @State private var linkText = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var result: ParseLinkResponse? = nil
    // 后台解析进度相关状态
    @State private var bgProgressTimer: Timer? = nil
    @State private var showBgProgress = false
    @State private var bgStatusMessage: String = ""
    @State private var bgCompletedMessage: String? = nil
    // 是否显示手动添加店铺弹窗
    @State private var showManualAddSheet = false
    // 解析是否已完成
    @State private var parseCompleted = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // ── 说明文字 ──
                    VStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("粘贴抖音链接")
                            .font(.title2).fontWeight(.bold)
                        Text("从抖音复制博主视频链接，粘贴到下方\nAI 将自动识别推荐的店铺")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // ── 链接输入框 ──
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("粘贴抖音链接...", text: $linkText, axis: .vertical)
                                .lineLimit(3)
                                .padding(12)
                            if !linkText.isEmpty {
                                Button(action: { linkText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .padding(.trailing, 12)
                            }
                        }
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // 快速粘贴按钮（从剪贴板读取）
                        Button(action: pasteFromClipboard) {
                            Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 20)

                    // ── 错误提示 ──
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 20)
                    }

                    // ── 后台解析完成通知 ──
                    if let completedMsg = bgCompletedMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(completedMsg)
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                            Button(action: { bgCompletedMessage = nil; onSuccess() }) {
                                Text("刷新地图")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                    }

                    // ── 后台解析进度指示器 ──
                    if showBgProgress {
                        BgProgressView(statusMessage: bgStatusMessage)
                            .padding(.horizontal, 20)
                    }

                    // ── 解析结果 ──
                    if let result = result {
                        ParseResultView(result: result, onManualAdd: {
                            showManualAddSheet = true
                        })
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 30)

                    // ── 解析按钮 ──
                    Button(action: parseLink) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(buttonText)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(buttonBackground)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(linkText.isEmpty || isLoading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        bgProgressTimer?.invalidate()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            bgProgressTimer?.invalidate()
        }
        .sheet(isPresented: $showManualAddSheet) {
            if let result = result {
                ManualAddRestaurantSheet(
                    videoUrl: linkText,
                    authorName: result.author?.name ?? "未知博主",
                    onSuccess: {
                        // 手动添加成功后刷新地图
                        onSuccess()
                    }
                )
                .environmentObject(authState)
            }
        }
    }

    // 按钮文本
    var buttonText: String {
        if isLoading {
            return "正在解析..."
        } else if parseCompleted {
            return "重新解析"
        } else {
            return "开始解析"
        }
    }

    // 按钮背景色
    var buttonBackground: Color {
        if linkText.isEmpty || isLoading {
            return Color.gray.opacity(0.4)
        } else if parseCompleted {
            return Color.blue
        } else {
            return Color.orange
        }
    }

    // 从剪贴板读取链接
    func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            linkText = text
        }
    }

    // 调用后端解析链接
    func parseLink() {
        guard !linkText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        parseCompleted = false  // 重置状态
        errorMessage = nil
        result = nil
        bgCompletedMessage = nil
        showBgProgress = false
        bgProgressTimer?.invalidate()

        Task {
            do {
                let response = try await APIService.shared.parseDouyinLink(
                    url: linkText.trimmingCharacters(in: .whitespaces),
                    userId: authState.userId
                )
                result = response
                parseCompleted = true  // 标记完成
                onSuccess()

                // 如果有后台任务正在运行，启动轮询
                if response.is_background_running, let authorId = response.author_id ?? response.author?.id {
                    showBgProgress = true
                    bgStatusMessage = "正在解析博主其他探店视频..."
                    startBgProgressPolling(authorId: authorId)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // 轮询后台任务进度（每 5 秒查询一次）
    func startBgProgressPolling(authorId: String) {
        bgProgressTimer?.invalidate()
        var failureCount = 0  // 记录连续失败次数

        bgProgressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                do {
                    let status = try await APIService.shared.getParseStatus(authorId: authorId)
                    failureCount = 0  // 成功后重置失败计数

                    await MainActor.run {
                        if status.status == "completed" {
                            bgProgressTimer?.invalidate()
                            showBgProgress = false
                            if let newCount = status.new_restaurants_found, newCount > 0 {
                                bgCompletedMessage = "博主其他视频解析完成，发现 \(newCount) 家新店铺！"
                            } else {
                                bgCompletedMessage = "博主其他视频解析完成"
                            }
                        } else if status.status == "running" {
                            if let total = status.total_videos, total > 0,
                               let processed = status.processed_videos {
                                bgStatusMessage = "正在解析博主其他探店视频（\(processed)/\(total)）..."
                            } else if let processed = status.processed_videos {
                                bgStatusMessage = "正在解析博主历史视频（已处理 \(processed) 个）..."
                            }
                        } else if status.status == "failed" {
                            bgProgressTimer?.invalidate()
                            showBgProgress = false
                            errorMessage = "后台解析遇到问题：\(status.message)"
                        }
                    }
                } catch {
                    failureCount += 1
                    print("[轮询错误] 查询后台任务状态失败: \(error)")

                    // 连续失败 3 次后停止轮询并提示用户
                    if failureCount >= 3 {
                        await MainActor.run {
                            bgProgressTimer?.invalidate()
                            showBgProgress = false
                            errorMessage = "无法获取后台解析进度，请稍后刷新地图查看"
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────
// 后台解析进度指示器
// ─────────────────────────────────────────
struct BgProgressView: View {
    let statusMessage: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                .scaleEffect(0.8)
            VStack(alignment: .leading, spacing: 2) {
                Text("后台解析中")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// ─────────────────────────────────────────
// 解析结果展示（适配新旧两种后端响应格式）
// ─────────────────────────────────────────
struct ParseResultView: View {
    let result: ParseLinkResponse
    let onManualAdd: () -> Void

    // 兼容新旧格式：优先用 restaurants（旧格式），降级用 restaurant（新格式）
    private var restaurants: [RestaurantResult] {
        if let list = result.restaurants, !list.isEmpty {
            return list
        }
        if let single = result.restaurant {
            return [single]
        }
        return []
    }

    private var authorName: String {
        result.author?.name ?? "未知博主"
    }

    private var authorAvatar: String? {
        result.author?.avatar_url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 博主信息
            HStack(spacing: 10) {
                AsyncImage(url: URL(string: authorAvatar ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.subheadline).fontWeight(.semibold)
                    HStack(spacing: 4) {
                        Image(systemName: result.status == "cached" ? "arrow.clockwise" : "sparkles")
                            .font(.caption2)
                        Text(_statusText)
                            .font(.caption)
                    }
                    .foregroundColor(result.status == "cached" ? .blue : .green)
                }
                Spacer()
                // 店铺数量徽章
                Text("\(restaurants.count) 家店铺")
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 后台解析进度提示（当 is_background_running = true 时显示）
            if result.is_background_running {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("博主其他探店视频正在后台解析中，完成后将自动更新地图")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // 店铺列表（最多显示 5 条）
            if !restaurants.isEmpty {
                Text("识别到的店铺")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(restaurants.prefix(5)) { restaurant in
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(restaurant.name)
                                .font(.caption).fontWeight(.medium)
                            if let address = restaurant.address {
                                Text(address)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let category = restaurant.category {
                            Text(category)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if restaurants.count > 5 {
                    Text("还有 \(restaurants.count - 5) 家店铺已添加到地图")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 消息文本
            Text(result.message)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)

            // 手动添加店铺按钮（当未识别到店铺时显示）
            if restaurants.isEmpty {
                Button(action: onManualAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.caption)
                        Text("手动添加店铺")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.top, 8)
            }
        }
    }

    private var _statusText: String {
        switch result.status {
        case "cached": return "已有数据，直接加载"
        case "parsed": return "新解析完成"
        default: return result.status
        }
    }
}
