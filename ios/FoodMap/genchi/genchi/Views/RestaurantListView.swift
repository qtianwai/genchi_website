import SwiftUI

private struct SystemGroupRoute: Identifiable, Hashable {
    let title: String
    let groupType: SystemGroupType

    var id: String { title }
}

struct RestaurantListView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var allCount = 0
    @State private var favCount = 0
    @State private var avoidedCount = 0
    @State private var customGroups: [RestaurantGroup] = []
    @State private var isLoading = true

    @State private var showCreateGroupSheet = false
    @State private var selectedSystemGroup: SystemGroupRoute?
    @State private var selectedCustomGroup: RestaurantGroup?

    var body: some View {
        List {
            FavoritesSectionHeader("系统分组")

            if isLoading {
                loadingRow
            } else {
                systemGroupsRow
            }

            FavoritesSectionHeader("我的分组")

            if isLoading {
                loadingRow
            } else if customGroups.isEmpty {
                customGroupsEmptyRow
            } else {
                ForEach(customGroups) { group in
                    customGroupRow(group)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("店铺列表")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateGroupSheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FavoritesTheme.accent)
                }
            }
        }
        .navigationDestination(item: $selectedSystemGroup) { route in
            GroupRestaurantListView(title: route.title, groupType: route.groupType)
        }
        .navigationDestination(item: $selectedCustomGroup) { group in
            GroupDetailView(group: group)
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(isPresented: $showCreateGroupSheet) {
            CreateGroupSheet(
                onCreate: { name in
                    Task { await createGroup(named: name) }
                }
            )
            .presentationDetents([.medium])
        }
        .onReceive(NotificationCenter.default.publisher(for: .restaurantStateDidChange)) { _ in
            Task { await loadData() }
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
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var systemGroupsRow: some View {
        FavoritesCard {
            VStack(spacing: 0) {
                Button {
                    selectedSystemGroup = SystemGroupRoute(title: "全部店铺", groupType: .all)
                } label: {
                    FavoritesGroupRow(
                        icon: "square.grid.2x2",
                        iconTint: .blue,
                        title: "全部店铺",
                        countText: "\(allCount)"
                    )
                }
                .buttonStyle(.plain)

                systemDivider

                Button {
                    dismiss()
                } label: {
                    FavoritesGroupRow(
                        icon: "bookmark.fill",
                        iconTint: FavoritesTheme.accent,
                        title: "收藏的店铺",
                        countText: "\(favCount)"
                    )
                }
                .buttonStyle(.plain)

                systemDivider

                Button {
                    selectedSystemGroup = SystemGroupRoute(title: "避雷的店铺", groupType: .avoided)
                } label: {
                    FavoritesGroupRow(
                        icon: "exclamationmark.shield.fill",
                        iconTint: FavoritesTheme.avoid,
                        title: "避雷的店铺",
                        countText: "\(avoidedCount)"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 16)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var systemDivider: some View {
        Divider()
            .overlay(FavoritesTheme.separator)
            .padding(.leading, 54)
    }

    private var customGroupsEmptyRow: some View {
        FavoritesEmptyStateCard(
            icon: "folder.badge.plus",
            title: "还没有自定义分组",
            subtitle: "新建分组后，可以把收藏店铺整理到自己的分类里。"
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func customGroupRow(_ group: RestaurantGroup) -> some View {
        FavoritesCard {
            FavoritesGroupRow(
                icon: "folder.fill",
                iconTint: FavoritesTheme.purple,
                title: group.name,
                countText: "\(group.restaurant_count ?? 0)"
            )
            .onTapGesture {
                selectedCustomGroup = group
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("删除", role: .destructive) {
                    Task { await deleteGroup(group) }
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
            async let mapTask = APIService.shared.getMapRestaurants(userId: authState.userId)
            async let favoritesTask = APIService.shared.getFavorites(userId: authState.userId)
            async let avoidedTask = APIService.shared.getAvoidedRestaurants(userId: authState.userId)
            async let groupsTask = APIService.shared.getGroups(userId: authState.userId)

            let mapResponse = try await mapTask
            let favorites = try await favoritesTask
            let avoided = try await avoidedTask
            let groups = try await groupsTask

            var restaurantIds = Set<String>()
            for item in mapResponse.restaurants {
                restaurantIds.insert(item.restaurant_id)
            }
            for item in mapResponse.user_restaurants {
                restaurantIds.insert(item.restaurant_id)
            }

            allCount = restaurantIds.count
            favCount = favorites.count
            avoidedCount = avoided.count
            customGroups = groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            print("[店铺列表] 加载失败: \(error)")
        }
        isLoading = false
    }

    private func createGroup(named name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            let group = try await APIService.shared.createGroup(userId: authState.userId, name: trimmedName)
            customGroups.append(group)
            customGroups.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            showCreateGroupSheet = false
        } catch {
            print("[店铺列表] 创建分组失败: \(error)")
        }
    }

    private func deleteGroup(_ group: RestaurantGroup) async {
        do {
            try await APIService.shared.deleteGroup(userId: authState.userId, groupId: group.id)
            customGroups.removeAll { $0.id == group.id }
        } catch {
            print("[店铺列表] 删除分组失败: \(error)")
        }
    }
}

enum SystemGroupType: Hashable {
    case all
    case favorites
    case avoided
}

struct GroupRestaurantListView: View {
    let title: String
    let groupType: SystemGroupType

    @EnvironmentObject private var authState: AuthState

    @State private var restaurants: [Restaurant] = []
    @State private var isLoading = true
    @State private var selectedRestaurant: RestaurantDestination?

    var body: some View {
        List {
            if isLoading {
                loadingRow
            } else if restaurants.isEmpty {
                emptyRow
            } else {
                ForEach(restaurants) { restaurant in
                    restaurantRow(restaurant)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
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
            icon: "tray",
            title: "暂无店铺",
            subtitle: "这里会展示当前分组下可访问的店铺。"
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func restaurantRow(_ restaurant: Restaurant) -> some View {
        FavoritesCard {
            FavoritesRestaurantRow(
                restaurant: restaurant,
                configuration: FavoritesRestaurantRowConfiguration(
                    addressText: restaurant.address,
                    badgeText: restaurant.category,
                    trailing: .chevron
                )
            )
            .onTapGesture {
                selectedRestaurant = RestaurantDestination(
                    restaurant: restaurant,
                    restaurantId: restaurant.id
                )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, restaurants.first?.id == restaurant.id ? 8 : 0)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func loadData() async {
        isLoading = true
        do {
            switch groupType {
            case .all:
                let mapResponse = try await APIService.shared.getMapRestaurants(userId: authState.userId)
                var seen = Set<String>()
                var allRestaurants: [Restaurant] = []

                for item in mapResponse.restaurants {
                    if let restaurant = item.restaurants, seen.insert(restaurant.id).inserted {
                        allRestaurants.append(restaurant)
                    }
                }

                for item in mapResponse.user_restaurants {
                    if let restaurant = item.restaurants, seen.insert(restaurant.id).inserted {
                        allRestaurants.append(restaurant)
                    }
                }

                restaurants = allRestaurants
            case .favorites:
                let favorites = try await APIService.shared.getFavorites(userId: authState.userId)
                restaurants = favorites.compactMap(\.restaurants)
            case .avoided:
                let avoided = try await APIService.shared.getAvoidedRestaurants(userId: authState.userId)
                restaurants = avoided.compactMap(\.restaurants)
            }
        } catch {
            print("[系统分组] 加载失败: \(error)")
        }
        isLoading = false
    }

    private func handleRestaurantStateChange(_ notification: Notification) {
        guard let change = RestaurantStateChange(notification) else { return }

        if change.isDeleted {
            restaurants.removeAll { $0.id == change.restaurantId }
            return
        }

        switch groupType {
        case .favorites:
            if change.isFavorited == false {
                restaurants.removeAll { $0.id == change.restaurantId }
            } else if change.isFavorited == true {
                Task { await loadData() }
            }
        case .avoided:
            if change.isAvoided == false {
                restaurants.removeAll { $0.id == change.restaurantId }
            } else if change.isAvoided == true {
                Task { await loadData() }
            }
        case .all:
            break
        }
    }
}

private struct FavoritesGroupRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let countText: String

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FavoritesTheme.body)

            Spacer()

            Text(countText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FavoritesTheme.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FavoritesTheme.tertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

private struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""

    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                FavoritesTheme.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    Text("给你的店铺集合起个名字，后续可以继续添加收藏店铺。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FavoritesTheme.secondary)

                    FavoritesCard {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text("分组名称")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FavoritesTheme.body)

                            TextField("例如：火锅 / 夜宵 / 想带朋友去", text: $groupName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(FavoritesTheme.title)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(FavoritesTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(DS.Spacing.lg)
                    }

                    Spacer()
                }
                .padding(DS.Spacing.lg)
            }
            .navigationTitle("新建分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        onCreate(groupName)
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .favoritesPageChrome()
        }
    }
}
