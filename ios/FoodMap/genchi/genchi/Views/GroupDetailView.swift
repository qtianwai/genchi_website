import SwiftUI

struct GroupDetailView: View {
    let group: RestaurantGroup

    @EnvironmentObject private var authState: AuthState

    @State private var restaurants: [GroupRestaurant] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var selectedRestaurant: RestaurantDestination?

    var body: some View {
        List {
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
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FavoritesTheme.accent)
                }
            }
        }
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
        .sheet(isPresented: $showAddSheet) {
            AddToGroupSheet(group: group) {
                Task { await loadData() }
            }
            .presentationDetents([.large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .restaurantStateDidChange)) { notification in
            handleRestaurantStateChange(notification)
        }
        .favoritesMinimalBackButton()
        .favoritesPageChrome()
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
        .padding(.top, 8)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptyRow: some View {
        FavoritesEmptyStateCard(
            icon: "folder",
            title: "分组里还没有店铺",
            subtitle: "点击右上角加号，把收藏里的店铺加入这个分组。"
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func restaurantRow(_ item: GroupRestaurant) -> some View {
        FavoritesCard {
            if let restaurant = item.restaurants {
                FavoritesRestaurantRow(
                    restaurant: restaurant,
                    configuration: FavoritesRestaurantRowConfiguration(
                        addressText: restaurant.address,
                        badgeText: restaurant.category,
                        badgeTint: FavoritesTheme.purple,
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
                    Button("移除", role: .destructive) {
                        Task { await removeFromGroup(item) }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, restaurants.first?.id == item.id ? 8 : 0)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func loadData() async {
        isLoading = true
        do {
            restaurants = try await APIService.shared.getGroupRestaurants(
                groupId: group.id,
                userId: authState.userId
            )
        } catch {
            print("[分组详情] 加载失败: \(error)")
        }
        isLoading = false
    }

    private func removeFromGroup(_ item: GroupRestaurant) async {
        do {
            try await APIService.shared.removeFromGroup(
                userId: authState.userId,
                groupId: group.id,
                restaurantId: item.restaurant_id
            )
            restaurants.removeAll { $0.id == item.id }
        } catch {
            print("[分组详情] 移除失败: \(error)")
        }
    }

    private func handleRestaurantStateChange(_ notification: Notification) {
        guard let change = RestaurantStateChange(notification) else { return }
        if change.isDeleted {
            restaurants.removeAll { $0.restaurant_id == change.restaurantId }
        }
    }
}

struct AddToGroupSheet: View {
    let group: RestaurantGroup
    let onAdded: () -> Void

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var favorites: [Favorite] = []
    @State private var existingRestaurantIds: Set<String> = []
    @State private var isLoading = true

    private var orderedFavorites: [Favorite] {
        favorites.sorted { left, right in
            let leftAdded = existingRestaurantIds.contains(left.restaurant_id)
            let rightAdded = existingRestaurantIds.contains(right.restaurant_id)
            if leftAdded == rightAdded {
                return (left.restaurants?.name ?? "") < (right.restaurants?.name ?? "")
            }
            return !leftAdded && rightAdded
        }
    }

    var body: some View {
        NavigationStack {
            List {
                FavoritesSectionHeader("可加入的收藏店铺", trailing: "\(favorites.count) 家")

                if isLoading {
                    loadingRow
                } else if favorites.isEmpty {
                    emptyRow
                } else {
                    ForEach(orderedFavorites) { favorite in
                        row(for: favorite)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("添加到分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                await loadData()
            }
            .favoritesPageChrome()
        }
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
            icon: "bookmark.slash",
            title: "还没有可添加的收藏店铺",
            subtitle: "先去收藏页把店铺收藏起来，再回来分组。"
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func row(for favorite: Favorite) -> some View {
        let alreadyAdded = existingRestaurantIds.contains(favorite.restaurant_id)

        return FavoritesCard {
            if let restaurant = favorite.restaurants {
                HStack(spacing: DS.Spacing.md) {
                    FavoritesRestaurantRow(
                        restaurant: restaurant,
                        configuration: FavoritesRestaurantRowConfiguration(
                            noteText: favorite.note,
                            addressText: restaurant.address,
                            badgeText: alreadyAdded ? "已添加" : restaurant.category,
                            badgeTint: alreadyAdded ? FavoritesTheme.purple : FavoritesTheme.accent,
                            trailing: .none
                        )
                    )

                    Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(alreadyAdded ? FavoritesTheme.purple : FavoritesTheme.accent)
                        .padding(.trailing, DS.Spacing.lg)
                }
                .contentShape(Rectangle())
                .opacity(alreadyAdded ? 0.72 : 1)
                .onTapGesture {
                    guard !alreadyAdded else { return }
                    Task { await addToGroup(favorite.restaurant_id) }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func loadData() async {
        isLoading = true
        do {
            async let favoritesTask = APIService.shared.getFavorites(userId: authState.userId)
            async let groupRestaurantsTask = APIService.shared.getGroupRestaurants(
                groupId: group.id,
                userId: authState.userId
            )

            let loadedFavorites = try await favoritesTask
            let groupRestaurants = try await groupRestaurantsTask

            favorites = loadedFavorites
            existingRestaurantIds = Set(groupRestaurants.map(\.restaurant_id))
        } catch {
            print("[添加到分组] 加载失败: \(error)")
        }
        isLoading = false
    }

    private func addToGroup(_ restaurantId: String) async {
        do {
            try await APIService.shared.addToGroup(
                userId: authState.userId,
                groupId: group.id,
                restaurantId: restaurantId
            )
            existingRestaurantIds.insert(restaurantId)
            onAdded()
            dismiss()
        } catch {
            print("[添加到分组] 失败: \(error)")
        }
    }
}
