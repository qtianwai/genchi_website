// 解析抖音链接的底部弹窗
// 用户粘贴抖音链接后，调用后端解析并展示结果
// 支持后台异步解析：当前视频优先快速返回，博主其他视频在后台处理

import SwiftUI

struct ParseLinkSheet: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    let onSuccess: () -> Void
    var initialLink: String? = nil
    var autoStart: Bool = false

    // v10.0 新增：异步解析开始回调（通知 MapView 开始轮询）
    var onParsingStarted: ((String) -> Void)? = nil

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
    @State private var selectedScope: ParseScope = .singleOnly
    // 预填链接自动解析只触发一次
    @State private var hasAutoStarted = false
    @AppStorage("parse_link_last_scope") private var lastSelectedScopeRawValue = ""

    enum ParseScope: String {
        case followAll
        case singleOnly  // 仅添加本店铺
    }

    private var normalizedLinkText: String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        VStack(spacing: DS.Spacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.brand.opacity(0.12))
                                    .frame(width: 68, height: 68)
                                Image(systemName: "link.badge.plus")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(DS.Color.brand)
                            }

                            Text("从抖音添加")
                                .font(.title2.bold())
                            Text("复制一条抖音视频链接，系统会帮你识别里面提到的店铺")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            sectionHeader(
                                title: "贴上视频链接",
                                subtitle: "支持直接粘贴，也可以一键读取剪贴板"
                            )

                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                TextField("把抖音链接粘贴到这里", text: $linkText, axis: .vertical)
                                    .lineLimit(4)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)

                                if !linkText.isEmpty {
                                    Button(action: { linkText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(14)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DS.Color.separator.opacity(0.14), lineWidth: 0.8)
                            }

                            Button(action: pasteFromClipboard) {
                                Label("从剪贴板带入", systemImage: "doc.on.clipboard")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DS.Color.brand)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(DS.Color.brand.opacity(0.10), in: Capsule())
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)

                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            sectionHeader(
                                title: "添加方式",
                                subtitle: "选择关注博主全部推荐，或仅添加本店铺"
                            )

                            ScopeOptionRow(
                                icon: "fork.knife.circle",
                                title: "仅添加本店铺",
                                subtitle: "只添加这条视频的店铺，不关注博主",
                                badgeText: lastSelectedScopeBadge(for: .singleOnly),
                                isSelected: selectedScope == .singleOnly
                            ) { updateSelectedScope(.singleOnly) }

                            ScopeOptionRow(
                                icon: "person.crop.circle.badge.plus",
                                title: "关注博主全部推荐",
                                subtitle: "关注这个博主后，地图会补齐他推荐过的店，后续新推荐也会自动更新",
                                badgeText: lastSelectedScopeBadge(for: .followAll),
                                isSelected: selectedScope == .followAll
                            ) { updateSelectedScope(.followAll) }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)

                        if let error = errorMessage {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if let completedMsg = bgCompletedMessage {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DS.Color.success)
                                Text(completedMsg)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: {
                                    bgCompletedMessage = nil
                                    onSuccess()
                                }) {
                                    Text("刷新地图")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(DS.Color.brand)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(DS.Color.brand.opacity(0.10), in: Capsule())
                                }
                            }
                            .padding(12)
                            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if showBgProgress {
                            BgProgressView(statusMessage: bgStatusMessage)
                        }

                        if let result = result {
                            ParseResultView(result: result, onManualAdd: {
                                showManualAddSheet = true
                            })
                        }

                        Button(action: parseLink) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: parseCompleted ? "arrow.clockwise" : "sparkles")
                                }

                                Text(buttonText)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(buttonBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundColor(.white)
                        }
                        .disabled(normalizedLinkText.isEmpty || isLoading)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("从抖音添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        bgProgressTimer?.invalidate()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            bgProgressTimer?.invalidate()
        }
        .onAppear {
            selectedScope = restoredScope
            if let initialLink, !initialLink.isEmpty {
                linkText = initialLink
            }
            if autoStart, !hasAutoStarted, !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasAutoStarted = true
                parseLink()
            }
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

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // 按钮文本
    var buttonText: String {
        if isLoading {
            return "识别中..."
        } else if parseCompleted {
            return "重新识别"
        } else {
            return "开始识别"
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
        parseCompleted = false
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

                // v10.0：无论什么状态都直接关闭弹框
                // parsing → 通知 MapView 开始轮询，后台解析完弹框通知
                // cached/parsed → 直接刷新地图
                if response.status == "parsing", let videoCacheId = response.video_cache_id, !videoCacheId.isEmpty {
                    onParsingStarted?(videoCacheId)
                } else {
                    // 缓存命中或同步返回，直接刷新地图
                    onSuccess()
                }
                isLoading = false
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
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

    private var restoredScope: ParseScope {
        ParseScope(rawValue: lastSelectedScopeRawValue) ?? .singleOnly
    }

    private func updateSelectedScope(_ scope: ParseScope) {
        selectedScope = scope
        lastSelectedScopeRawValue = scope.rawValue
    }

    private func lastSelectedScopeBadge(for scope: ParseScope) -> String? {
        lastSelectedScopeRawValue == scope.rawValue ? "上次选择" : nil
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
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.brand.opacity(0.12), lineWidth: 0.8)
        }
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
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
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
    let badgeText: String?
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
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(isSelected ? DS.Color.brand : .primary)

                        if let badgeText {
                            Text(badgeText)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.brand)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DS.Color.brand.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                }

                Spacer()

                // 右侧选中指示圆圈
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DS.Color.brand : Color(.systemGray4))
                    .font(.title3)
            }
            .padding(DS.Spacing.md)
            .background(isSelected ? DS.Color.brand.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(
                        isSelected ? DS.Color.brand.opacity(0.35) : DS.Color.separator.opacity(0.12),
                        lineWidth: 0.9
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
