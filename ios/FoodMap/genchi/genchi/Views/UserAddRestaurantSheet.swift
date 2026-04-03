// 用户自建推荐店铺表单（v4.0 新增）
// 两步流程：Step 1 搜索高德候选 → Step 2 确认入库
// 入口：MainTabView 底部「+」按钮 → 选择「手动添加店铺」

import SwiftUI

struct UserAddRestaurantSheet: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    let onSuccess: () -> Void

    // ── 表单状态 ──
    @State private var restaurantName = ""
    @State private var selectedCity = "上海"

    // ── 搜索状态 ──
    @State private var isSearching = false
    @State private var candidates: [RestaurantCandidate] = []
    @State private var searchError: String? = nil
    @State private var hasSearched = false

    // ── 提交状态 ──
    @State private var isSubmitting = false
    @State private var successMessage: String? = nil

    // 城市列表（复用 ManualAddRestaurantSheet 的城市列表）
    let cities = ["上海", "北京", "广州", "深圳", "成都", "杭州", "武汉", "南京",
                  "重庆", "西安", "苏州", "天津", "长沙", "郑州", "青岛", "厦门",
                  "宁波", "合肥", "昆明", "大连", "哈尔滨", "沈阳", "济南", "福州",
                  "贵阳", "南昌", "太原", "石家庄", "南宁", "乌鲁木齐", "兰州", "海口"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // ── 顶部说明 ──
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.purple)
                        Text("添加我的推荐")
                            .font(.title2.bold())
                        Text("不依赖博主，直接添加你知道的好店")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // ── Step 1：搜索表单 ──
                    VStack(alignment: .leading, spacing: 16) {
                        Text("搜索店铺")
                            .font(.headline)
                            .foregroundColor(.primary)

                        // 店铺名称输入
                        VStack(alignment: .leading, spacing: 6) {
                            Text("店铺名称")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("输入店铺名称", text: $restaurantName)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.search)
                                .onSubmit { Task { await searchRestaurants() } }
                        }

                        // 城市选择
                        VStack(alignment: .leading, spacing: 6) {
                            Text("所在城市")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("城市", selection: $selectedCity) {
                                ForEach(cities, id: \.self) { city in
                                    Text(city).tag(city)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }

                        // 搜索按钮
                        Button(action: { Task { await searchRestaurants() } }) {
                            HStack {
                                if isSearching {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                                Text(isSearching ? "搜索中..." : "搜索")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(restaurantName.count >= 2 ? Color.purple : Color.gray.opacity(0.4))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(restaurantName.count < 2 || isSearching)
                    }
                    .padding(16)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(16)

                    // ── 错误提示 ──
                    if let error = searchError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                    }

                    // ── Step 2：候选列表 ──
                    if hasSearched {
                        VStack(alignment: .leading, spacing: 12) {
                            if candidates.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "mappin.slash")
                                        .font(.system(size: 32))
                                        .foregroundColor(.gray.opacity(0.5))
                                    Text("未找到相关店铺")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text("请检查店铺名称和城市是否正确")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(24)
                            } else {
                                Text("选择店铺（共 \(candidates.count) 条结果）")
                                    .font(.headline)

                                ForEach(candidates) { candidate in
                                    CandidateRow(
                                        candidate: candidate,
                                        isSubmitting: isSubmitting,
                                        onSelect: { Task { await addRestaurant(candidate) } }
                                    )
                                }
                            }
                        }
                    }

                    // ── 成功提示 ──
                    if let msg = successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(msg)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
                .padding(20)
            }
            .navigationTitle("手动添加店铺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // 搜索高德候选店铺
    func searchRestaurants() async {
        guard restaurantName.count >= 2 else { return }
        isSearching = true
        searchError = nil
        hasSearched = false
        candidates = []
        do {
            candidates = try await APIService.shared.searchUserRestaurant(
                name: restaurantName,
                city: selectedCity
            )
            hasSearched = true
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    // 确认添加选中的候选店铺
    func addRestaurant(_ candidate: RestaurantCandidate) async {
        isSubmitting = true
        do {
            let resp = try await APIService.shared.createUserRestaurant(
                userId: authState.userId,
                candidate: candidate
            )
            successMessage = resp.message
            onSuccess()
            // 1.5 秒后自动关闭
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            searchError = error.localizedDescription
        }
        isSubmitting = false
    }
}

// ── 候选店铺行 ──
struct CandidateRow: View {
    let candidate: RestaurantCandidate
    let isSubmitting: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 左侧图标
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)
                }

                // 店铺信息
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(candidate.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    if !candidate.category_mapped.isEmpty {
                        Text(candidate.category_mapped)
                            .font(.caption2)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                Spacer()

                // 右侧添加按钮
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.purple)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .disabled(isSubmitting)
        .buttonStyle(.plain)
    }
}
