import SwiftUI

struct AuthorDetailView: View {
    let author: Author

    @EnvironmentObject private var authState: AuthState

    @State private var stats: AuthorStats?
    @State private var restaurants: [MapRestaurant] = []
    @State private var favoriteRestaurantIds: Set<String> = []
    @State private var avoidedRestaurantIds: Set<String> = []
    @State private var isFollowing = false
    @State private var isLoading = true
    @State private var isResolvingFollowState = true
    @State private var showUnfollowConfirm = false
    @State private var selectedRestaurant: RestaurantDestination?

    var body: some View {
        List {
            headerRow
            statsRow
            FavoritesSectionHeader("博主推荐", trailing: "\(restaurants.count) 家")

            if isLoading {
                loadingRow
            } else if restaurants.isEmpty {
                emptyRow
            } else {
                ForEach(restaurants) { item in
                    restaurantRow(item)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(author.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRestaurant) { destination in
            RestaurantDetailView(
                restaurant: destination.restaurant,
                restaurantId: destination.restaurantId
            )
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .confirmationDialog("取消关注", isPresented: $showUnfollowConfirm) {
            Button("取消关注", role: .destructive) {
                Task { await toggleFollow() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("取消关注后，该博主推荐的店铺（已收藏店铺除外）将不再在地图上显示。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .restaurantStateDidChange)) { notification in
            handleRestaurantStateChange(notification)
        }
        .favoritesMinimalBackButton()
        .favoritesPageChrome()
    }

    private var headerRow: some View {
        FavoritesCard {
            HStack(spacing: DS.Spacing.lg) {
                AsyncImage(url: URL(string: author.avatar_url ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(FavoritesTheme.surfaceElevated)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(FavoritesTheme.secondary)
                        )
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(author.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(FavoritesTheme.title)

                    Text("抖音达人")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FavoritesTheme.secondary)
                }

                Spacer()

                Button(action: followButtonTapped) {
                    Text(followButtonTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isFollowing ? FavoritesTheme.body : Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            isFollowing ? FavoritesTheme.surfaceElevated : FavoritesTheme.accent,
                            in: Capsule()
                        )
                    }
                .buttonStyle(.plain)
                .disabled(isResolvingFollowState)
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var statsRow: some View {
        FavoritesCard {
            HStack(spacing: 0) {
                statColumn(value: stats?.restaurant_count ?? 0, label: "餐厅")
                statDivider
                statColumn(value: stats?.follower_count ?? 0, label: "粉丝")
                statDivider
                statColumn(value: stats?.city_count ?? 0, label: "城市")
            }
            .padding(.vertical, DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(FavoritesTheme.separator)
            .frame(width: 1, height: 36)
    }

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(FavoritesTheme.title)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FavoritesTheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingRow: some View {
        FavoritesCard {
            HStack {
                Spacer()
                ProgressView()
                    .tint(FavoritesTheme.accent)
                    .padding(.vertical, DS.Spacing.xxl)
                Spacer()
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptyRow: some View {
        FavoritesEmptyStateCard(
            icon: "play.slash",
            title: "暂无推荐店铺",
            subtitle: "这个博主目前还没有同步到可展示的店铺。"
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func restaurantRow(_ item: MapRestaurant) -> some View {
        FavoritesCard {
            if let restaurant = item.restaurants {
                FavoritesRestaurantRow(
                    restaurant: restaurant,
                    configuration: FavoritesRestaurantRowConfiguration(
                        addressText: restaurant.address,
                        badgeText: favoriteRestaurantIds.contains(item.restaurant_id) ? "已收藏" : restaurant.category,
                        badgeTint: favoriteRestaurantIds.contains(item.restaurant_id) ? FavoritesTheme.note : FavoritesTheme.accent,
                        trailing: .chevron
                    )
                )
                .onTapGesture {
                    selectedRestaurant = RestaurantDestination(
                        restaurant: restaurant,
                        restaurantId: item.restaurant_id
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deleteRestaurant(item.restaurant_id) }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        Task { await toggleAvoid(item.restaurant_id) }
                    } label: {
                        Label(
                            avoidedRestaurantIds.contains(item.restaurant_id) ? "取消避雷" : "避雷",
                            systemImage: avoidedRestaurantIds.contains(item.restaurant_id) ? "shield.slash" : "exclamationmark.shield"
                        )
                    }
                    .tint(.gray)

                    Button {
                        Task { await toggleFavorite(item.restaurant_id) }
                    } label: {
                        Label(
                            favoriteRestaurantIds.contains(item.restaurant_id) ? "取消收藏" : "收藏",
                            systemImage: favoriteRestaurantIds.contains(item.restaurant_id) ? "bookmark.slash" : "bookmark"
                        )
                    }
                    .tint(.orange)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var followButtonTitle: String {
        if isResolvingFollowState {
            return "加载中"
        }
        return isFollowing ? "已关注" : "关注"
    }

    private func followButtonTapped() {
        guard !isResolvingFollowState else { return }
        if isFollowing {
            showUnfollowConfirm = true
        } else {
            Task { await toggleFollow() }
        }
    }

    private func loadData() async {
        isLoading = true
        async let statsTask: Void = loadStats()
        async let restaurantsTask: Void = loadRestaurants()
        async let followStateTask: Void = loadFollowState()
        _ = await (statsTask, restaurantsTask, followStateTask)
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
            let loadedRestaurants = try await APIService.shared.getAuthorRestaurants(authorId: author.id)
            restaurants = loadedRestaurants
            favoriteRestaurantIds = Set(
                loadedRestaurants.compactMap { item in
                    item.is_favorited == true ? item.restaurant_id : nil
                }
            )
            avoidedRestaurantIds = Set(
                loadedRestaurants.compactMap { item in
                    item.is_avoided == true ? item.restaurant_id : nil
                }
            )
        } catch {
            print("[博主详情] 加载店铺失败: \(error)")
        }
    }

    private func loadFollowState() async {
        isResolvingFollowState = true
        defer { isResolvingFollowState = false }

        do {
            let followingAuthors = try await APIService.shared.getFollowingAuthors(userId: authState.userId)
            isFollowing = followingAuthors.contains(where: { $0.id == author.id })
        } catch {
            print("[博主详情] 加载关注状态失败: \(error)")
        }
    }

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
            if favoriteRestaurantIds.contains(restaurantId) {
                try await APIService.shared.removeFavorite(userId: authState.userId, restaurantId: restaurantId)
                favoriteRestaurantIds.remove(restaurantId)
            } else {
                try await APIService.shared.addFavorite(userId: authState.userId, restaurantId: restaurantId)
                favoriteRestaurantIds.insert(restaurantId)
            }

            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: favoriteRestaurantIds.contains(restaurantId),
                isAvoided: avoidedRestaurantIds.contains(restaurantId),
                favoriteNote: nil,
                isDeleted: false
            ).post()
        } catch {
            print("[博主详情] 收藏失败: \(error)")
        }
    }

    private func toggleAvoid(_ restaurantId: String) async {
        do {
            if avoidedRestaurantIds.contains(restaurantId) {
                try await APIService.shared.unavoidRestaurant(userId: authState.userId, restaurantId: restaurantId)
                avoidedRestaurantIds.remove(restaurantId)
            } else {
                try await APIService.shared.avoidRestaurant(userId: authState.userId, restaurantId: restaurantId)
                avoidedRestaurantIds.insert(restaurantId)
            }

            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: favoriteRestaurantIds.contains(restaurantId),
                isAvoided: avoidedRestaurantIds.contains(restaurantId),
                favoriteNote: nil,
                isDeleted: false
            ).post()
        } catch {
            print("[博主详情] 避雷失败: \(error)")
        }
    }

    private func deleteRestaurant(_ restaurantId: String) async {
        do {
            try await APIService.shared.deleteRestaurantForUser(userId: authState.userId, restaurantId: restaurantId)
            restaurants.removeAll { $0.restaurant_id == restaurantId }
            favoriteRestaurantIds.remove(restaurantId)
            avoidedRestaurantIds.remove(restaurantId)

            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: false,
                isAvoided: false,
                favoriteNote: nil,
                isDeleted: true
            ).post()
        } catch {
            print("[博主详情] 删除失败: \(error)")
        }
    }

    private func handleRestaurantStateChange(_ notification: Notification) {
        guard let change = RestaurantStateChange(notification) else { return }

        if change.isDeleted {
            restaurants.removeAll { $0.restaurant_id == change.restaurantId }
            favoriteRestaurantIds.remove(change.restaurantId)
            avoidedRestaurantIds.remove(change.restaurantId)
            return
        }

        if let isFavorited = change.isFavorited {
            if isFavorited {
                favoriteRestaurantIds.insert(change.restaurantId)
            } else {
                favoriteRestaurantIds.remove(change.restaurantId)
            }
        }

        if let isAvoided = change.isAvoided {
            if isAvoided {
                avoidedRestaurantIds.insert(change.restaurantId)
            } else {
                avoidedRestaurantIds.remove(change.restaurantId)
            }
        }
    }
}
