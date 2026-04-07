// 复核列表页
// 顶部 Tab 切换「待复核」/「已复核」
// 待复核：P0（AI未识别）优先显示，支持下拉刷新和分页加载
// 已复核：按复核时间倒序，支持点击进入详情进行二次调整

import SwiftUI

struct ReviewListView: View {
    @StateObject private var viewModel = ReviewViewModel()
    @EnvironmentObject var authState: AuthState

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ── 顶部 Tab 切换 ──
                Picker("", selection: $viewModel.selectedTab) {
                    Text("待复核（\(viewModel.pendingTotal)）").tag(ReviewTab.pending)
                    Text("已复核（\(viewModel.reviewedTotal)）").tag(ReviewTab.reviewed)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: viewModel.selectedTab) { _, newTab in
                    Task { await viewModel.switchTab(newTab, userId: authState.userId) }
                }

                // ── 列表内容 ──
                Group {
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        Spacer()
                        ProgressView("加载中...")
                        Spacer()
                    } else if viewModel.items.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: viewModel.selectedTab == .pending ? "checkmark.shield" : "clock.badge.checkmark")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text(viewModel.selectedTab == .pending ? "暂无待复核记录" : "暂无已复核记录")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(viewModel.items) { item in
                                NavigationLink(destination: ReviewDetailView(item: item, viewModel: viewModel)) {
                                    if viewModel.selectedTab == .pending {
                                        ReviewRowView(item: item)
                                    } else {
                                        ReviewedRowView(item: item)
                                    }
                                }
                            }
                            // 加载更多
                            if viewModel.hasMore {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                                .onAppear {
                                    Task { await viewModel.loadMore(userId: authState.userId) }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await viewModel.loadItems(userId: authState.userId)
                        }
                    }
                }
            }
            .navigationTitle("复核")
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("确定") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            if viewModel.pendingItems.isEmpty && viewModel.reviewedItems.isEmpty {
                await viewModel.initialLoad(userId: authState.userId)
            }
        }
    }
}

// ── 待复核列表行 ──
struct ReviewRowView: View {
    let item: ReviewItem

    private var priorityColor: Color {
        if item.isUserCorrectionPriority { return .pink }
        if item.isP0 { return .red }
        return .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // 优先级标签
                Text(item.review_priority ?? "P1")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor)
                    .cornerRadius(4)

                if item.isUserCorrectionPriority {
                    Text("用户反馈")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(4)
                }

                // AI 解析失败标签（failed 状态显示）
                if item.isFailed {
                    Text("AI失败")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple)
                        .cornerRadius(4)
                }

                // v14.0 新增：冷启动录入标签
                if item.isColdStart {
                    Text("冷启动")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                }

                // 博主名
                Text(item.authors?.name ?? "未知博主")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // 创建时间（只显示日期）
                if let createdAt = item.created_at {
                    Text(String(createdAt.prefix(10)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // 勘误摘要（有待处理勘误时展示，紧跟标签行）
            if let corrections = item.user_corrections, !corrections.isEmpty {
                let pending = corrections.filter { $0.status == "pending" }
                if !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(pending.prefix(3))) { c in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(correctionTypeLabel(c.correction_type))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                                if let detail = c.correction_detail, !detail.isEmpty {
                                    Text("· \(detail)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        if pending.count > 3 {
                            Text("还有 \(pending.count - 3) 条勘误...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }
            }

            // AI 解析说明（截取前 60 字）
            Text(item.parse_reason ?? "无解析说明")
                .font(.subheadline)
                .lineLimit(2)

            // AI 识别的店铺名（若有）
            if let name = item.restaurant_name {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// ── 已复核列表行 ──
struct ReviewedRowView: View {
    let item: ReviewItem

    // 复核结果标签文字和颜色
    var statusLabel: (text: String, color: Color) {
        switch item.review_status {
        case "approved":  return ("已确认", .green)
        case "corrected": return ("已修正", .blue)
        case "confirmed": return ("无店铺", .gray)
        default:          return ("已复核", .secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // 复核结果标签（视觉重心）
                Text(statusLabel.text)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusLabel.color)
                    .cornerRadius(4)

                // 博主名
                Text(item.authors?.name ?? "未知博主")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // 复核时间（倒序排列的依据）
                if let reviewedAt = item.reviewed_at {
                    Text(String(reviewedAt.prefix(10)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // 最终店铺名（主要内容，无店铺时显示提示）
            if let name = item.restaurant_name {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            } else {
                Text("无关联店铺")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // AI 解析说明（次要内容，截取前两行）
            if let reason = item.parse_reason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // 已处理勘误摘要（灰色调，表示已处理）
            if let corrections = item.user_corrections, !corrections.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("勘误已处理 · \(corrections.count) 条")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let first = corrections.first {
                        Text("(\(correctionTypeLabel(first.correction_type)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// ── 勘误类型中文映射（供 ReviewRowView / ReviewedRowView 使用）──
private func correctionTypeLabel(_ type: String) -> String {
    switch type {
    case "wrong_restaurant": return "店铺识别错误"
    case "wrong_address":    return "地址/位置不对"
    case "closed":           return "店铺已关闭"
    case "duplicate":        return "重复店铺"
    default:                 return "其他问题"
    }
}
