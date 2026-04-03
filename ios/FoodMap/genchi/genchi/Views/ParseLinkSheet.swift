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
    // 轮询连续失败次数（用 @State 替代局部变量，避免 Swift 6 并发警告）
    @State private var bgPollingFailureCount = 0
    // 入库范围选择：关注博主全部推荐 or 仅添加本店铺
    @State private var selectedScope: ParseScope = .followAll

    enum ParseScope {
        case followAll   // 关注博主全部推荐（默认）
        case singleOnly  // 仅添加本店铺
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    // ── 说明文字 ──
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(DS.Color.brand)
                        Text("粘贴抖音链接")
                            .font(.title2).fontWeight(.bold)
                        Text("从抖音复制博主视频链接，粘贴到下方\nAI 将自动识别推荐的店铺")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, DS.Spacing.xl)

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
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

                        // 快速粘贴按钮（从剪贴板读取）
                        Button(action: pasteFromClipboard) {
                            Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                                .font(.caption)
                                .foregroundColor(DS.Color.brand)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)

                    // ── 入库范围选择 ──
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("添加方式")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ScopeOptionRow(
                            icon: "person.crop.circle.badge.plus",
                            title: "关注博主全部推荐",
                            subtitle: "解析博主所有探店视频，自动关注博主",
                            isSelected: selectedScope == .followAll
                        ) { selectedScope = .followAll }

                        ScopeOptionRow(
                            icon: "fork.knife.circle",
                            title: "仅添加本店铺",
                            subtitle: "只添加这条视频的店铺，不关注博主",
                            isSelected: selectedScope == .singleOnly
                        ) { selectedScope = .singleOnly }
                    }
                    .padding(.horizontal, DS.Spacing.xl)

                    // ── 错误提示 ──
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, DS.Spacing.xl)
                    }

                    // ── 后台解析完成通知 ──
                    if let completedMsg = bgCompletedMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(DS.Color.success)
                            Text(completedMsg)
                                .font(.caption)
                                .foregroundColor(DS.Color.success)
                            Spacer()
                            Button(action: { bgCompletedMessage = nil; onSuccess() }) {
                                Text("刷新地图")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DS.Color.brand)
                            }
                        }
                        .padding(DS.Spacing.md)
                        .background(DS.Color.success.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                        .padding(.horizontal, DS.Spacing.xl)
                    }

                    // ── 后台解析进度指示器 ──
                    if showBgProgress {
                        BgProgressView(statusMessage: bgStatusMessage)
                            .padding(.horizontal, DS.Spacing.xl)
                    }

                    // ── 解析结果 ──
                    if let result = result {
                        ParseResultView(result: result, onManualAdd: {
                            showManualAddSheet = true
                        })
                        .padding(.horizontal, DS.Spacing.xl)
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
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                    }
                    .disabled(linkText.isEmpty || isLoading)
                    .padding(.horizontal, DS.Spacing.xl)
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
            return DS.Color.info
        } else {
            return DS.Color.brand
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
                    userId: authState.userId,
                    scope: selectedScope == .singleOnly ? "single_only" : "follow_all"
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
        // 用 @MainActor 隔离的 actor 属性替代局部变量，避免 Swift 6 并发警告
        bgPollingFailureCount = 0

        bgProgressTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [self] _ in
            Task { @MainActor in
                do {
                    let status = try await APIService.shared.getParseStatus(authorId: authorId)
                    bgPollingFailureCount = 0  // 成功后重置失败计数

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
                } catch {
                    bgPollingFailureCount += 1
                    print("[轮询错误] 查询后台任务状态失败: \(error)")

                    // 连续失败 3 次后停止轮询并提示用户
                    if bgPollingFailureCount >= 3 {
                        bgProgressTimer?.invalidate()
                        showBgProgress = false
                        errorMessage = "无法获取后台解析进度，请稍后刷新地图查看"
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
        HStack(spacing: DS.Spacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DS.Color.brand))
                .scaleEffect(0.8)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("后台解析中")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.brand)
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.brand.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
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
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // 博主信息
            HStack(spacing: DS.Spacing.md) {
                AsyncImage(url: URL(string: authorAvatar ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(authorName)
                        .font(.subheadline).fontWeight(.semibold)
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: result.status == "cached" ? "arrow.clockwise" : "sparkles")
                            .font(.caption2)
                        Text(_statusText)
                            .font(.caption)
                    }
                    .foregroundColor(result.status == "cached" ? DS.Color.info : DS.Color.success)
                }
                Spacer()
                // 店铺数量徽章
                Text("\(restaurants.count) 家店铺")
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(DS.Color.brand.opacity(0.15))
                    .foregroundColor(DS.Color.brand)
                    .clipShape(Capsule())
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            // 后台解析进度提示（当 is_background_running = true 时显示）
            if result.is_background_running {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(DS.Color.info)
                    Text("博主其他探店视频正在后台解析中，完成后将自动更新地图")
                        .font(.caption)
                        .foregroundColor(DS.Color.info)
                }
                .padding(DS.Spacing.sm)
                .background(DS.Color.info.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }

            // 店铺列表（最多显示 5 条）
            if !restaurants.isEmpty {
                Text("识别到的店铺")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(restaurants.prefix(5)) { restaurant in
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "fork.knife.circle.fill")
                            .foregroundColor(DS.Color.brand)
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
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.caption)
                        Text("手动添加店铺")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(DS.Color.brand)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.brand.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
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

// ─────────────────────────────────────────
// 入库范围选择行（RadioButton 风格）
// ─────────────────────────────────────────
struct ScopeOptionRow: View {
    let icon: String       // SF Symbol 图标名
    let title: String      // 主标题
    let subtitle: String   // 副标题说明
    let isSelected: Bool   // 是否选中
    let onTap: () -> Void  // 点击回调

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                // 左侧图标
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? DS.Color.brand : .secondary)
                    .frame(width: 28)

                // 文字区域
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? DS.Color.brand : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 右侧选中指示圆圈
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DS.Color.brand : Color(.systemGray4))
                    .font(.title3)
            }
            .padding(DS.Spacing.md)
            .background(isSelected ? DS.Color.brand.opacity(0.06) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(isSelected ? DS.Color.brand.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
