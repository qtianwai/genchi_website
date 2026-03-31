// 收藏页面
// 显示用户收藏的所有店铺，支持取消收藏和导航

import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var authState: AuthState
    @State private var favorites: [Favorite] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if favorites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("还没有收藏任何店铺")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("在地图上点击店铺，点击心形图标即可收藏")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(favorites) { fav in
                            if let restaurant = fav.restaurants {
                                FavoriteRow(restaurant: restaurant) {
                                    removeFavorite(fav)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("我的收藏")
            .task { await loadFavorites() }
            .refreshable { await loadFavorites() }
        }
    }

    func loadFavorites() async {
        isLoading = true
        do {
            favorites = try await APIService.shared.getFavorites(userId: authState.userId)
        } catch {}
        isLoading = false
    }

    func removeFavorite(_ fav: Favorite) {
        Task {
            try? await APIService.shared.removeFavorite(userId: authState.userId, restaurantId: fav.restaurant_id)
            favorites.removeAll { $0.id == fav.id }
        }
    }
}

struct FavoriteRow: View {
    let restaurant: Restaurant
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 分类图标
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "fork.knife")
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
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
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            // 导航按钮
            if let coordinate = restaurant.coordinate {
                Button(action: { openNavigation(coordinate: coordinate) }) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // 取消收藏
            Button(action: onRemove) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    func openNavigation(coordinate: CLLocationCoordinate2D) {
        let url = URL(string: "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d")!
        UIApplication.shared.open(url)
    }
}

// 需要导入 CoreLocation
import CoreLocation
