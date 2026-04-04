// 收藏页面（v5.0 完全重写）
// 合并原【博主】Tab 和【收藏】Tab 为统一入口
// 上半部分：关注的博主列表（含自己）
// 下半部分：收藏的店铺列表（左滑操作 + 卡片图标）

import SwiftUI
import CoreLocation

struct FavoritesView: View {
    @EnvironmentObject var authState: AuthState

    // 数据
    @State private var authors: [Author] = []
    @State private var favorites: [Favorite] = []
    @State private var isLoading = true

    // 搜索
    @State private var showSearch = false
    @State private var searchText = ""

    // 收藏理由编辑
    @State private var showNoteEditor = false
    @State private var editingFav: Favorite?
    @State private var editingNote = ""

    var body: some View {
        NavigationStack {
            List {
                // 搜索栏（展开时显示）
                if showSearch {
                    searchBar
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // 关注的博主区域
                Section("关注的博主") {
                    // 自己（第一行，点击进入店铺列表页）
                    NavigationLink {
                        RestaurantListView()
                    } label: {
                        authorRow(
                            avatarURL: authState.avatarURL,
                            name: authState.nickname,
                            subtitle: "我",
                            isMe: true
                        )
                    }

                    // 已关注博主列表
                    ForEach(filteredAuthors) { author in
                        NavigationLink {
                            AuthorDetailView(author: author)
                        } label: {
                            authorRow(
                                avatarURL: author.avatar_url,
                                name: author.name,
                                subtitle: "抖音达人",
                                isMe: false
                            )
                        }
                    }

                    if authors.isEmpty && !isLoading {
                        Text("还没有关注任何博主")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 收藏的店铺区域
                Section {
                    if filteredFavorites.isEmpty && !isLoading {
                        VStack(spacing: DS.Spacing.md) {
                            Image(systemName: "bookmark.slash")
                                .font(.largeTitle)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("还没有收藏任何店铺")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("在地图上点击店铺，即可收藏")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredFavorites) { fav in
                            if let restaurant = fav.restaurants {
                                NavigationLink {
                                    RestaurantDetailView(
                                        restaurant: restaurant,
                                        restaurantId: fav.restaurant_id
                                    )
                                } label: {
                                    favoriteRestaurantRow(fav: fav, restaurant: restaurant)
                                }
                                // 左滑操作（List 内才生效）
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await deleteRestaurant(fav.restaurant_id) }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        Task { await avoidRestaurant(fav.restaurant_id) }
                                    } label: {
                                        Label("避雷", systemImage: "exclamationmark.shield")
                                    }
                                    .tint(.gray)
                                    Button {
                                        Task { await removeFavorite(fav) }
                                    } label: {
                                        Label("取消收藏", systemImage: "bookmark.slash")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("收藏的店铺")
                        Spacer()
                        Text("\(filteredFavorites.count) 家")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("收藏")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { showSearch.toggle() }
                    } label: {
                        Image(systemName: "magnifyingglass")
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
            // 收藏理由编辑 Sheet
            .sheet(isPresented: $showNoteEditor) {
                noteEditorSheet
            }
        }
    }

    // MARK: - 搜索栏
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索店铺或博主", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceAlt)
        .cornerRadius(DS.Radius.sm)
    }

    // 过滤后的博主列表
    private var filteredAuthors: [Author] {
        if searchText.isEmpty { return authors }
        return authors.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // 过滤后的收藏列表
    private var filteredFavorites: [Favorite] {
        if searchText.isEmpty { return favorites }
        return favorites.filter {
            $0.restaurants?.name.localizedCaseInsensitiveContains(searchText) == true ||
            $0.restaurants?.address?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    // MARK: - 博主行
    private func authorRow(avatarURL: String?, name: String, subtitle: String, isMe: Bool) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // 头像（44pt 圆形）
            AsyncImage(url: URL(string: avatarURL ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(isMe ? DS.Color.brand.opacity(0.15) : DS.Color.surfaceAlt)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(isMe ? DS.Color.brand : .gray)
                            .font(.body)
                    )
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - 收藏店铺行
    private func favoriteRestaurantRow(fav: Favorite, restaurant: Restaurant) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // 店铺图片（56pt 圆角）
            AsyncImage(url: URL(string: restaurant.photo_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(DS.Color.surfaceAlt)
                    .overlay(Image(systemName: "fork.knife").foregroundColor(.gray))
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            // 店铺信息
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(restaurant.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                // 收藏理由（若有）
                if let note = fav.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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

            // 卡片右侧图标：留言（编辑收藏理由）+ 导航
            VStack(spacing: DS.Spacing.md) {
                Button {
                    editingFav = fav
                    editingNote = fav.note ?? ""
                    showNoteEditor = true
                } label: {
                    Image(systemName: fav.note?.isEmpty == false ? "text.bubble.fill" : "text.bubble")
                        .font(.subheadline)
                        .foregroundColor(fav.note?.isEmpty == false ? DS.Color.brand : .gray)
                }
                .buttonStyle(.plain)

                if let coordinate = restaurant.coordinate {
                    Button {
                        openNavigation(coordinate: coordinate, name: restaurant.name)
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 收藏理由编辑 Sheet
    private var noteEditorSheet: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.lg) {
                Text("记录你喜欢这家店的理由")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $editingNote)
                    .frame(minHeight: 120)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surfaceAlt)
                    .cornerRadius(DS.Radius.md)
                Spacer()
            }
            .padding()
            .navigationTitle("收藏理由")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showNoteEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if let fav = editingFav {
                                try? await APIService.shared.updateFavoriteNote(
                                    userId: authState.userId,
                                    restaurantId: fav.restaurant_id,
                                    note: editingNote
                                )
                                // 更新本地数据
                                if let idx = favorites.firstIndex(where: { $0.id == fav.id }) {
                                    // 重新加载以获取更新后的数据
                                    await loadFavorites()
                                }
                            }
                            showNoteEditor = false
                        }
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 数据加载
    private func loadData() async {
        isLoading = true
        async let authorsTask: () = loadAuthors()
        async let favsTask: () = loadFavorites()
        _ = await (authorsTask, favsTask)
        isLoading = false
    }

    private func loadAuthors() async {
        do {
            authors = try await APIService.shared.getFollowingAuthors(userId: authState.userId)
        } catch {
            print("[收藏页] 加载博主失败: \(error)")
        }
    }

    private func loadFavorites() async {
        do {
            favorites = try await APIService.shared.getFavorites(userId: authState.userId)
        } catch {
            print("[收藏页] 加载收藏失败: \(error)")
        }
    }

    // MARK: - 操作
    private func removeFavorite(_ fav: Favorite) async {
        do {
            try await APIService.shared.removeFavorite(userId: authState.userId, restaurantId: fav.restaurant_id)
            favorites.removeAll { $0.id == fav.id }
        } catch {
            print("[收藏页] 取消收藏失败: \(error)")
        }
    }

    private func avoidRestaurant(_ restaurantId: String) async {
        do {
            try await APIService.shared.avoidRestaurant(userId: authState.userId, restaurantId: restaurantId)
        } catch {
            print("[收藏页] 避雷失败: \(error)")
        }
    }

    private func deleteRestaurant(_ restaurantId: String) async {
        do {
            try await APIService.shared.deleteRestaurantForUser(userId: authState.userId, restaurantId: restaurantId)
            favorites.removeAll { $0.restaurant_id == restaurantId }
        } catch {
            print("[收藏页] 删除失败: \(error)")
        }
    }

    private func openNavigation(coordinate: CLLocationCoordinate2D, name: String) {
        let url = URL(string: "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d")!
        UIApplication.shared.open(url)
    }
}
