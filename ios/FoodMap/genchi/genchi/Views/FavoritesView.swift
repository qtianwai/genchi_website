// 收藏页面
// v4.0：新增分段控制器，切换「我的收藏」和「我的推荐」两个分区

import SwiftUI
import CoreLocation

struct FavoritesView: View {
    @EnvironmentObject var authState: AuthState

    // 分段控制器选中项：0 = 我的收藏，1 = 我的推荐
    @State private var selectedTab = 0

    // 收藏数据
    @State private var favorites: [Favorite] = []
    @State private var isLoadingFavorites = false

    // 用户自建推荐数据（v4.0 新增）
    @State private var userRestaurants: [UserCreatedRestaurant] = []
    @State private var isLoadingUserRestaurants = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ── 分段控制器 ──
                Picker("", selection: $selectedTab) {
                    Text("我的收藏").tag(0)
                    Text("我的推荐").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                // ── 内容区域 ──
                if selectedTab == 0 {
                    favoritesContent
                } else {
                    userRestaurantsContent
                }
            }
            .navigationTitle(selectedTab == 0 ? "我的收藏" : "我的推荐")
            .task {
                await loadFavorites()
                await loadUserRestaurants()
            }
            .refreshable {
                if selectedTab == 0 {
                    await loadFavorites()
                } else {
                    await loadUserRestaurants()
                }
            }
        }
    }

    // ── 我的收藏内容 ──
    @ViewBuilder
    var favoritesContent: some View {
        if isLoadingFavorites {
            Spacer()
            ProgressView("加载中...")
            Spacer()
        } else if favorites.isEmpty {
            emptyView(
                icon: "heart.slash",
                title: "还没有收藏任何店铺",
                subtitle: "在地图上点击店铺，点击心形图标即可收藏"
            )
        } else {
            List {
                ForEach(favorites) { fav in
                    if let restaurant = fav.restaurants {
                        FavoriteRow(restaurant: restaurant, accentColor: DS.Color.brand) {
                            removeFavorite(fav)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // ── 我的推荐内容（v4.0 新增）──
    @ViewBuilder
    var userRestaurantsContent: some View {
        if isLoadingUserRestaurants {
            Spacer()
            ProgressView("加载中...")
            Spacer()
        } else if userRestaurants.isEmpty {
            emptyView(
                icon: "person.crop.circle.badge.plus",
                title: "还没有添加推荐店铺",
                subtitle: "点击底部「+」按钮，选择「手动添加店铺」来添加你知道的好店"
            )
        } else {
            List {
                ForEach(userRestaurants) { item in
                    if let restaurant = item.restaurants {
                        FavoriteRow(restaurant: restaurant, accentColor: .purple) {
                            removeUserRestaurant(item)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // ── 空状态视图 ──
    func emptyView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // ── 数据加载 ──
    func loadFavorites() async {
        isLoadingFavorites = true
        do {
            favorites = try await APIService.shared.getFavorites(userId: authState.userId)
        } catch {}
        isLoadingFavorites = false
    }

    func loadUserRestaurants() async {
        isLoadingUserRestaurants = true
        do {
            userRestaurants = try await APIService.shared.getUserRestaurants(userId: authState.userId)
        } catch {}
        isLoadingUserRestaurants = false
    }

    func removeFavorite(_ fav: Favorite) {
        Task {
            try? await APIService.shared.removeFavorite(userId: authState.userId, restaurantId: fav.restaurant_id)
            favorites.removeAll { $0.id == fav.id }
        }
    }

    func removeUserRestaurant(_ item: UserCreatedRestaurant) {
        Task {
            try? await APIService.shared.deleteUserRestaurant(userId: authState.userId, restaurantId: item.restaurant_id)
            userRestaurants.removeAll { $0.id == item.id }
        }
    }
}

// ── 通用店铺行（收藏和我的推荐共用，accentColor 区分样式）──
struct FavoriteRow: View {
    let restaurant: Restaurant
    var accentColor: Color = DS.Color.brand
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // 分类图标
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "fork.knife")
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(restaurant.name)
                    .font(.subheadline).fontWeight(.semibold)
                if let address = restaurant.address {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let category = restaurant.category {
                    Text(category)
                        .font(.caption2)
                        .foregroundColor(accentColor)
                }
            }

            Spacer()

            // 导航按钮
            if let coordinate = restaurant.coordinate {
                Button(action: { openNavigation(coordinate: coordinate) }) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .padding(DS.Spacing.sm)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // 移除按钮（收藏用红心，我的推荐用紫色 minus）
            Button(action: onRemove) {
                Image(systemName: accentColor == DS.Color.brand ? "heart.fill" : "minus.circle.fill")
                    .foregroundColor(accentColor == DS.Color.brand ? .red : .purple)
                    .padding(8)
                    .background((accentColor == DS.Color.brand ? Color.red : Color.purple).opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    func openNavigation(coordinate: CLLocationCoordinate2D) {
        let url = URL(string: "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d")!
        UIApplication.shared.open(url)
    }
}
