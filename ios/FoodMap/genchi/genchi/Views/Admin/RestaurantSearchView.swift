// 店铺模糊搜索视图（多选模式）
// 管理员修正店铺时使用：搜索高德 POI，支持选择多家店铺后批量提交
// v9.0 重构：从单选改为多选，内联分类编辑，批量提交

import SwiftUI
import Combine

// 已选店铺条目：候选 + 可编辑分类
struct SelectedRestaurantEntry: Identifiable {
    let candidate: RestaurantCandidate
    var category: String  // 可编辑，默认来自 candidate.category_mapped

    var id: String { candidate.amap_id }
}

struct RestaurantSearchView: View {
    let item: ReviewItem
    @ObservedObject var viewModel: ReviewViewModel
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    // 搜索相关
    @State private var keyword = ""
    @State private var city = ""
    @State private var candidates: [RestaurantCandidate] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    // 多选：已选店铺列表
    @State private var selectedEntries: [SelectedRestaurantEntry] = []

    // 提交状态
    @State private var isSubmitting = false

    // 防抖搜索
    @State private var searchTask: Task<Void, Never>?

    // 是否来自已复核列表（决定提交后行为）
    var isFromReviewed: Bool { viewModel.selectedTab == .reviewed }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ── 搜索栏 ──
                searchBar

                // ── 已选店铺区域 ──
                if !selectedEntries.isEmpty {
                    selectedSection
                }

                // ── 候选列表 ──
                candidateList

                // ── 底部提交按钮 ──
                if !selectedEntries.isEmpty {
                    submitButton
                }

                // 错误提示
                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("搜索店铺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("输入店铺名称", text: $keyword)
                    .autocorrectionDisabled()
                    .onChange(of: keyword) { triggerSearch() }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            HStack {
                Image(systemName: "location")
                    .foregroundColor(.secondary)
                TextField("城市（可选，如：成都）", text: $city)
                    .autocorrectionDisabled()
                    .onChange(of: city) { triggerSearch() }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .padding()
    }

    // MARK: - 已选店铺区域

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已选 \(selectedEntries.count) 家店铺")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // 已选列表（每项含分类编辑和删除按钮）
            ForEach(Array(selectedEntries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 8) {
                    // 店铺名
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.candidate.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(entry.candidate.address)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 分类编辑
                    TextField("分类", text: $selectedEntries[index].category)
                        .font(.caption)
                        .frame(width: 70)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)

                    // 删除按钮
                    Button(action: { selectedEntries.remove(at: index) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            Divider()
                .padding(.top, 4)
        }
        .background(Color.green.opacity(0.05))
    }

    // MARK: - 候选列表

    private var candidateList: some View {
        Group {
            if isSearching {
                Spacer()
                ProgressView("搜索中...")
                Spacer()
            } else if candidates.isEmpty && !keyword.isEmpty {
                Spacer()
                Text("未找到相关店铺，请调整关键词")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(candidates) { candidate in
                    Button(action: { toggleSelection(candidate) }) {
                        HStack {
                            CandidateRowView(candidate: candidate)
                            Spacer()
                            // 勾选状态
                            if isSelected(candidate) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - 底部提交按钮

    private var submitButton: some View {
        Button(action: { Task { await submitAll() } }) {
            if isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                Text("确认 \(selectedEntries.count) 家店铺入库")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .disabled(isSubmitting || selectedEntries.isEmpty || selectedEntries.contains(where: { $0.category.isEmpty }))
    }

    // MARK: - 选择/取消选择

    private func isSelected(_ candidate: RestaurantCandidate) -> Bool {
        selectedEntries.contains(where: { $0.candidate.amap_id == candidate.amap_id })
    }

    private func toggleSelection(_ candidate: RestaurantCandidate) {
        if let idx = selectedEntries.firstIndex(where: { $0.candidate.amap_id == candidate.amap_id }) {
            // 已选中 → 取消
            selectedEntries.remove(at: idx)
        } else {
            // 未选中 → 添加，默认分类来自高德映射
            selectedEntries.append(SelectedRestaurantEntry(
                candidate: candidate,
                category: candidate.category_mapped
            ))
        }
    }

    // MARK: - 批量提交

    @MainActor
    private func submitAll() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let restaurants = selectedEntries.map { (candidate: $0.candidate, category: $0.category) }
            if restaurants.count == 1 {
                // 单店铺：走原有接口（兼容）
                try await APIService.shared.adminCorrect(
                    cacheId: item.id,
                    candidate: restaurants[0].candidate,
                    category: restaurants[0].category,
                    userId: authState.userId
                )
            } else {
                // 多店铺：走新接口
                try await APIService.shared.adminCorrectMulti(
                    cacheId: item.id,
                    restaurants: restaurants,
                    userId: authState.userId
                )
            }
            // 提交成功后的处理
            if isFromReviewed {
                Task { await viewModel.refreshReviewed(userId: authState.userId) }
            } else {
                viewModel.removeFromPending(id: item.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }

    // MARK: - 防抖搜索

    private func triggerSearch() {
        searchTask?.cancel()
        guard !keyword.isEmpty else {
            candidates = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms 防抖
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    @MainActor
    private func performSearch() async {
        isSearching = true
        errorMessage = nil
        do {
            candidates = try await APIService.shared.searchRestaurantForReview(
                name: keyword,
                city: city,
                userId: authState.userId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}

// 候选店铺行视图（复用原有样式）
struct CandidateRowView: View {
    let candidate: RestaurantCandidate

    var body: some View {
        HStack(spacing: 10) {
            // 店铺缩略图（有图时显示，无图时显示占位图标）
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 48, height: 48)
                if let photoUrl = candidate.photo_url, !photoUrl.isEmpty {
                    AsyncImage(url: URL(string: photoUrl)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Image(systemName: "fork.knife")
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "fork.knife")
                        .foregroundColor(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(candidate.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(candidate.city)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(candidate.category_mapped)
                        .font(.caption2)
                        .foregroundColor(.orange)
                    // 均价标签
                    if let price = candidate.avg_price {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "yensign.circle")
                                .font(.system(size: 8))
                            Text("人均 ¥\(price)")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
