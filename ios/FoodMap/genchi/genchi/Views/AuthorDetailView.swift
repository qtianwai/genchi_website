// 博主详情页（v5.0 新增）
// 展示博主完整信息、统计数据和推荐的所有店铺
// 从收藏页点击博主进入

import SwiftUI

struct AuthorDetailView: View {
    // 博主信息
    let author: Author
    // 认证状态（用于获取 userId）
    @EnvironmentObject var authState: AuthState

    // 页面状态
    @State private var stats: AuthorStats?
    @State private var restaurants: [MapRestaurant] = []
    @State private var isFollowing = true  // 从收藏页进入默认已关注
    @State private var isLoading = true
    @State private var showUnfollowConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 顶部博主信息卡片
                authorInfoCard

                // 统计数据栏
                if let stats = stats {
                    statsBar(stats)
                        .padding(.top, DS.Spacing.lg)
                }

                // 推荐店铺列表
                restaurantList
                    .padding(.top, DS.Spacing.lg)
            }
        }
        .navigationTitle(author.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        // 取消关注二次确认
        .confirmationDialog("取消关注", isPresented: $showUnfollowConfirm) {
            Button("取消关注", role: .destructive) {
                Task { await toggleFollow() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("取消关注后，该博主推荐的店铺（已收藏店铺除外）将不再在地图上显示。")
        }
    }

    // MARK: - 博主信息卡片
    private var authorInfoCard: some View {
        HStack(spacing: DS.Spacing.lg) {
            // 博主头像（72pt 圆形）
            AsyncImage(url: URL(string: author.avatar_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(DS.Color.surfaceAlt)
                    .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(author.name)
                    .font(.title2.bold())
                Text("抖音达人")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 关注/取消关注按钮
            Button {
                if isFollowing {
                    showUnfollowConfirm = true
                } else {
                    Task { await toggleFollow() }
                }
            } label: {
                Text(isFollowing ? "已关注" : "关注")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isFollowing ? Color.gray.opacity(0.15) : DS.Color.brand)
                    .foregroundColor(isFollowing ? .primary : .white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }

    // MARK: - 统计数据栏
    private func statsBar(_ stats: AuthorStats) -> some View {
        HStack {
            statItem(value: stats.restaurant_count, label: "餐厅")
            Divider().frame(height: 30)
            statItem(value: stats.follower_count, label: "粉丝")
            Divider().frame(height: 30)
            statItem(value: stats.city_count, label: "城市")
        }
        .padding()
        .background(DS.Color.surfaceAlt)
        .cornerRadius(DS.Radius.lg)
        .padding(.horizontal)
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Text("\(value)")
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 推荐店铺列表
    private var restaurantList: some View {
        LazyVStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if restaurants.isEmpty {
                Text("暂无推荐店铺")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else {
                ForEach(restaurants) { item in
                    if let restaurant = item.restaurants {
                        NavigationLink {
                            RestaurantDetailView(
                                restaurant: restaurant,
                                restaurantId: item.restaurant_id
                            )
                        } label: {
                            restaurantRow(restaurant)
                        }
                        .buttonStyle(.plain)
                        // 左滑操作：收藏、避雷、删除
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await deleteRestaurant(item.restaurant_id) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                Task { await avoidRestaurant(item.restaurant_id) }
                            } label: {
                                Label("避雷", systemImage: "exclamationmark.shield")
                            }
                            .tint(.gray)
                            Button {
                                Task { await toggleFavorite(item.restaurant_id) }
                            } label: {
                                Label("收藏", systemImage: "bookmark")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
    }

    // 店铺行
    private func restaurantRow(_ restaurant: Restaurant) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // 店铺图片
            AsyncImage(url: URL(string: restaurant.photo_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Color.surfaceAlt)
                    .overlay(Image(systemName: "fork.knife").foregroundColor(.gray))
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(restaurant.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if let address = restaurant.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let category = restaurant.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.Color.brand.opacity(0.1))
                        .foregroundColor(DS.Color.brand)
                        .cornerRadius(4)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surface)
    }

    // MARK: - 数据加载
    private func loadData() async {
        isLoading = true
        async let statsTask: () = loadStats()
        async let restaurantsTask: () = loadRestaurants()
        _ = await (statsTask, restaurantsTask)
        isLoading = false
    }

    private func loadStats() async {
        do {
            stats = try await APIService.shared.getAuthorStats(authorId: author.id)
        } catch {
            print("[博主详情] 加载统计失败: \(error)")
        }
    }

    private func loadRestaurants() async {
        do {
            struct Response: Codable { let restaurants: [MapRestaurant] }
            // 复用现有接口获取博主推荐的店铺
            let data = try await APIService.shared.getAuthorRestaurants(authorId: author.id)
            restaurants = data
        } catch {
            print("[博主详情] 加载店铺失败: \(error)")
        }
    }

    // MARK: - 操作
    private func toggleFollow() async {
        do {
            if isFollowing {
                try await APIService.shared.unfollowAuthor(userId: authState.userId, authorId: author.id)
                isFollowing = false
            } else {
                try await APIService.shared.followAuthor(userId: authState.userId, authorId: author.id)
                isFollowing = true
            }
        } catch {
            print("[博主详情] 关注操作失败: \(error)")
        }
    }

    private func toggleFavorite(_ restaurantId: String) async {
        do {
            try await APIService.shared.addFavorite(userId: authState.userId, restaurantId: restaurantId)
        } catch {
            print("[博主详情] 收藏失败: \(error)")
        }
    }

    private func avoidRestaurant(_ restaurantId: String) async {
        do {
            try await APIService.shared.avoidRestaurant(userId: authState.userId, restaurantId: restaurantId)
        } catch {
            print("[博主详情] 避雷失败: \(error)")
        }
    }

    private func deleteRestaurant(_ restaurantId: String) async {
        do {
            try await APIService.shared.deleteRestaurantForUser(userId: authState.userId, restaurantId: restaurantId)
            // 从列表中移除
            restaurants.removeAll { $0.restaurant_id == restaurantId }
        } catch {
            print("[博主详情] 删除失败: \(error)")
        }
    }
}
