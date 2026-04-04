// 复核详情页
// 待复核记录：提供四个操作按钮
// 已复核记录：顶部显示当前复核状态，支持二次调整（复用同一视图）

import SwiftUI

struct ReviewDetailView: View {
    let item: ReviewItem
    @ObservedObject var viewModel: ReviewViewModel
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSearchSheet = false

    // 是否来自已复核列表（用于决定操作完成后的行为）
    var isFromReviewed: Bool { viewModel.selectedTab == .reviewed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── 当前复核状态（已复核记录显示）──
                if isFromReviewed {
                    currentStatusBanner
                }

                // ── 优先级 & 状态（待复核记录显示）──
                if !isFromReviewed {
                    HStack {
                        Text(item.review_priority ?? "P1")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.isP0 ? Color.red : Color.orange)
                            .cornerRadius(6)
                        // AI 解析失败标签
                        if item.isFailed {
                            Text("AI解析失败")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple)
                                .cornerRadius(6)
                        }
                        Text(item.isFailed ? "AI 解析失败，需人工兜底" : (item.isP0 ? "AI 未识别店铺" : "AI 已识别，待确认"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                // ── 博主信息 ──
                if let author = item.authors {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.gray)
                        Text(author.name ?? "未知博主")
                            .font(.subheadline)
                    }
                }

                // ── AI 解析说明 ──
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 解析说明")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.parse_reason ?? "无")
                        .font(.body)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }

                // ── 当前关联店铺（有 restaurant_name 时显示）──
                if let name = item.restaurant_name {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isFromReviewed ? "当前关联店铺" : "AI 识别结果")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            // 店铺图片 + 名称横排
                            HStack(spacing: 10) {
                                // 店铺封面图
                                if let photoUrl = item.restaurant_photo_url, !photoUrl.isEmpty {
                                    AsyncImage(url: URL(string: photoUrl)) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Color.gray.opacity(0.15)
                                        }
                                    }
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(name, systemImage: "fork.knife")
                                    if let addr = item.restaurant_address {
                                        Label(addr, systemImage: "mappin")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let cat = item.restaurant_category {
                                        Label(cat, systemImage: "tag")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            // 均价标签
                            if let price = item.restaurant_avg_price {
                                HStack(spacing: 2) {
                                    Image(systemName: "yensign.circle")
                                        .font(.caption)
                                    Text("人均 ¥\(price)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }

                // ── 在抖音中查看 ──
                if item.video_id != nil {
                    Button(action: openInDouyin) {
                        Label("在抖音中查看原视频", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.black)
                }

                Divider()

                // ── 操作按钮 ──
                if isProcessing {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    VStack(spacing: 10) {
                        // 确认正确（有关联店铺时显示）
                        if item.restaurant_id != nil {
                            Button(action: { Task { await confirmCorrect() } }) {
                                Label(isFromReviewed ? "重新确认正确" : "确认正确", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }

                        // 修正店铺
                        Button(action: { showSearchSheet = true }) {
                            Label("修正店铺", systemImage: "pencil.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        // 确认无店铺
                        Button(action: { Task { await confirmEmpty() } }) {
                            Label("确认无店铺", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.gray)

                        // 跳过（仅待复核显示）
                        if !isFromReviewed {
                            Button(action: { Task { await skip() } }) {
                                Label("跳过", systemImage: "arrow.right.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
        .navigationTitle(isFromReviewed ? "二次调整" : "复核详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSearchSheet) {
            RestaurantSearchView(item: item, viewModel: viewModel)
                .environmentObject(authState)
        }
    }

    // 当前复核状态横幅（已复核记录顶部显示）
    private var currentStatusBanner: some View {
        let (label, color): (String, Color) = {
            switch item.review_status {
            case "approved":  return ("当前状态：已确认正确", .green)
            case "corrected": return ("当前状态：已人工修正", .blue)
            case "confirmed": return ("当前状态：已确认无店铺", .gray)
            default:          return ("当前状态：已复核", .secondary)
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            if let reviewedAt = item.reviewed_at {
                Text(String(reviewedAt.prefix(10)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(color)
        .padding(10)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // 跳转抖音：优先 App，降级网页
    private func openInDouyin() {
        guard let appURL = item.douyinAppURL else { return }
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = item.douyinWebURL {
            UIApplication.shared.open(webURL)
        }
    }

    private func confirmCorrect() async {
        isProcessing = true
        do {
            try await APIService.shared.adminConfirmCorrect(cacheId: item.id, userId: authState.userId)
            handleActionComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    private func confirmEmpty() async {
        isProcessing = true
        do {
            try await APIService.shared.adminConfirmEmpty(cacheId: item.id, userId: authState.userId)
            handleActionComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    private func skip() async {
        isProcessing = true
        do {
            try await APIService.shared.adminSkip(cacheId: item.id, userId: authState.userId)
            viewModel.removeFromPending(id: item.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    // 操作完成后的统一处理：
    // 待复核 → 从 pending 列表移除并返回
    // 已复核 → 刷新 reviewed 列表并返回
    private func handleActionComplete() {
        if isFromReviewed {
            Task { await viewModel.refreshReviewed(userId: authState.userId) }
        } else {
            viewModel.removeFromPending(id: item.id)
        }
        dismiss()
    }
}
