// 分组详情页（v5.0 新增）
// 展示某个自定义分组内的店铺列表，支持添加/移除店铺

import SwiftUI

struct GroupDetailView: View {
    let group: RestaurantGroup

    @EnvironmentObject var authState: AuthState

    @State private var restaurants: [GroupRestaurant] = []
    @State private var isLoading = true
    @State private var showAddSheet = false

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if restaurants.isEmpty {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("分组内暂无店铺")
                        .foregroundColor(.secondary)
                    Text("点击右上角添加按钮添加店铺")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowSeparator(.hidden)
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
                        .swipeActions(edge: .trailing) {
                            Button("移除", role: .destructive) {
                                Task { await removeFromGroup(item) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await loadData() }
        .refreshable { await loadData() }
        .sheet(isPresented: $showAddSheet) {
            AddToGroupSheet(groupId: group.id) {
                Task { await loadData() }
            }
        }
    }

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
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if let address = restaurant.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
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
}

// MARK: - 添加店铺到分组的 Sheet
// 从用户已收藏的店铺中选择添加
struct AddToGroupSheet: View {
    let groupId: String
    let onAdded: () -> Void

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var favorites: [Favorite] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                } else if favorites.isEmpty {
                    Text("暂无收藏的店铺")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(favorites) { fav in
                        if let restaurant = fav.restaurants {
                            Button {
                                Task { await addToGroup(fav.restaurant_id) }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    AsyncImage(url: URL(string: restaurant.photo_url ?? "")) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                                            .fill(DS.Color.surfaceAlt)
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

                                    VStack(alignment: .leading) {
                                        Text(restaurant.name)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        if let city = restaurant.city {
                                            Text(city)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(DS.Color.brand)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择店铺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                isLoading = true
                favorites = (try? await APIService.shared.getFavorites(userId: authState.userId)) ?? []
                isLoading = false
            }
        }
    }

    private func addToGroup(_ restaurantId: String) async {
        do {
            try await APIService.shared.addToGroup(
                userId: authState.userId,
                groupId: groupId,
                restaurantId: restaurantId
            )
            onAdded()
            dismiss()
        } catch {
            print("[添加到分组] 失败: \(error)")
        }
    }
}
