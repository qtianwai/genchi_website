// 店铺模糊搜索视图
// 管理员修正店铺时使用：输入关键词搜索高德 POI，选择后进入确认步骤

import SwiftUI
import Combine

struct RestaurantSearchView: View {
    let item: ReviewItem
    @ObservedObject var viewModel: ReviewViewModel
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    @State private var keyword = ""
    @State private var city = ""
    @State private var candidates: [RestaurantCandidate] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedCandidate: RestaurantCandidate?

    // 防抖：输入停顿 300ms 后触发搜索
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ── 搜索栏 ──
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

                // ── 候选列表 ──
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
                        Button(action: { selectedCandidate = candidate }) {
                            CandidateRowView(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }

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
            .sheet(item: $selectedCandidate) { candidate in
                ConfirmRestaurantView(
                    item: item,
                    candidate: candidate,
                    viewModel: viewModel
                )
                .environmentObject(authState)
            }
        }
    }

    // 防抖搜索：取消上一个任务，300ms 后触发新搜索
    private func triggerSearch() {
        searchTask?.cancel()
        guard !keyword.isEmpty else {
            candidates = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
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

// 候选店铺行视图
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
