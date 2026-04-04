// 店铺列表页（v5.0 新增）
// 从收藏页点击"自己"进入，管理用户所有店铺的分组视图
// 包含系统预设分组（全部、收藏、避雷）和用户自定义分组

import SwiftUI

struct RestaurantListView: View {
    @EnvironmentObject var authState: AuthState

    // 数据
    @State private var allCount = 0
    @State private var favCount = 0
    @State private var avoidedCount = 0
    @State private var customGroups: [RestaurantGroup] = []
    @State private var isLoading = true

    // 创建分组
    @State private var showCreateGroup = false
    @State private var newGroupName = ""

    var body: some View {
        List {
            // 系统预设分组（不可编辑/删除）
            Section("系统分组") {
                NavigationLink {
                    GroupRestaurantListView(
                        title: "全部店铺",
                        groupType: .all
                    )
                } label: {
                    groupRow(icon: "square.grid.2x2", title: "全部店铺", count: allCount, color: .blue)
                }

                NavigationLink {
                    GroupRestaurantListView(
                        title: "收藏的店铺",
                        groupType: .favorites
                    )
                } label: {
                    groupRow(icon: "bookmark.fill", title: "收藏的店铺", count: favCount, color: .orange)
                }

                NavigationLink {
                    GroupRestaurantListView(
                        title: "避雷的店铺",
                        groupType: .avoided
                    )
                } label: {
                    groupRow(icon: "exclamationmark.shield.fill", title: "避雷的店铺", count: avoidedCount, color: .red)
                }
            }

            // 自定义分组
            if !customGroups.isEmpty {
                Section("我的分组") {
                    ForEach(customGroups) { group in
                        NavigationLink {
                            GroupDetailView(group: group)
                        } label: {
                            groupRow(
                                icon: "folder.fill",
                                title: group.name,
                                count: group.restaurant_count ?? 0,
                                color: .purple
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
                                Task { await deleteGroup(group) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("店铺列表")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateGroup = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task { await loadData() }
        .refreshable { await loadData() }
        // 创建分组弹窗
        .alert("新建分组", isPresented: $showCreateGroup) {
            TextField("分组名称", text: $newGroupName)
            Button("创建") {
                Task { await createGroup() }
            }
            Button("取消", role: .cancel) {
                newGroupName = ""
            }
        } message: {
            Text("请输入分组名称（最多 20 字）")
        }
    }

    // 分组行
    private func groupRow(icon: String, title: String, count: Int, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            Text(title)
                .font(.body)
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - 数据加载
    private func loadData() async {
        isLoading = true
        do {
            // 并行加载各项数据
            async let favsTask = APIService.shared.getFavorites(userId: authState.userId)
            async let avoidedTask = APIService.shared.getAvoidedRestaurants(userId: authState.userId)
            async let groupsTask = APIService.shared.getGroups(userId: authState.userId)

            let favs = try await favsTask
            let avoided = try await avoidedTask
            let groups = try await groupsTask

            favCount = favs.count
            avoidedCount = avoided.count
            // 全部 = 收藏 + 避雷（去重后的总数，简化处理）
            let allIds = Set(favs.map { $0.restaurant_id } + avoided.map { $0.restaurant_id })
            allCount = allIds.count
            customGroups = groups
        } catch {
            print("[店铺列表] 加载失败: \(error)")
        }
        isLoading = false
    }

    private func createGroup() async {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let group = try await APIService.shared.createGroup(userId: authState.userId, name: name)
            customGroups.append(group)
            newGroupName = ""
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

// MARK: - 系统分组类型
enum SystemGroupType {
    case all
    case favorites
    case avoided
}

// MARK: - 系统分组店铺列表页（全部/收藏/避雷）
struct GroupRestaurantListView: View {
    let title: String
    let groupType: SystemGroupType

    @EnvironmentObject var authState: AuthState
    @State private var restaurants: [Restaurant] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if restaurants.isEmpty {
                Text("暂无店铺")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(restaurants) { restaurant in
                    NavigationLink {
                        RestaurantDetailView(
                            restaurant: restaurant,
                            restaurantId: restaurant.id
                        )
                    } label: {
                        restaurantRow(restaurant)
                    }
                }
            }
        }
        .navigationTitle(title)
        .task { await loadData() }
    }

    private func restaurantRow(_ restaurant: Restaurant) -> some View {
        HStack(spacing: DS.Spacing.md) {
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
            switch groupType {
            case .all:
                // 合并收藏和避雷的店铺（去重）
                let favs = try await APIService.shared.getFavorites(userId: authState.userId)
                let avoided = try await APIService.shared.getAvoidedRestaurants(userId: authState.userId)
                var seen = Set<String>()
                var all: [Restaurant] = []
                for f in favs {
                    if let r = f.restaurants, seen.insert(r.id).inserted { all.append(r) }
                }
                for a in avoided {
                    if let r = a.restaurants, seen.insert(r.id).inserted { all.append(r) }
                }
                restaurants = all
            case .favorites:
                let favs = try await APIService.shared.getFavorites(userId: authState.userId)
                restaurants = favs.compactMap { $0.restaurants }
            case .avoided:
                let avoided = try await APIService.shared.getAvoidedRestaurants(userId: authState.userId)
                restaurants = avoided.compactMap { $0.restaurants }
            }
        } catch {
            print("[分组列表] 加载失败: \(error)")
        }
        isLoading = false
    }
}
