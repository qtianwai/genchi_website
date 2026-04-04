import SwiftUI
import UIKit

private struct FavoriteNoteEditorContext: Identifiable {
    let favoriteId: String
    let restaurantId: String
    let restaurantName: String

    var id: String { favoriteId }
}

struct FavoritesView: View {
    @EnvironmentObject private var authState: AuthState
    @FocusState private var isSearchFocused: Bool

    @State private var authors: [Author] = []
    @State private var favorites: [Favorite] = []
    @State private var avoidedRestaurantIds: Set<String> = []
    @State private var isLoading = true

    @State private var showSearch = false
    @State private var searchText = ""

    @State private var selectedAuthor: Author?
    @State private var selectedRestaurant: RestaurantDestination?

    @State private var noteEditorContext: FavoriteNoteEditorContext?
    @State private var editingNote = ""
    @State private var showRestaurantList = false

    var body: some View {
        NavigationStack {
            List {
                titleRow

                if showSearch {
                    searchRow
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                FavoritesSectionHeader("关注的博主")

                if isLoading {
                    loadingRow
                } else if filteredAuthors.isEmpty {
                    authorsEmptyRow
                } else {
                    authorsRow
                }

                FavoritesSectionHeader("收藏的店铺", trailing: "\(filteredFavorites.count) 家")

                if isLoading {
                    loadingRow
                } else if filteredFavorites.isEmpty {
                    favoritesEmptyRow
                } else {
                    ForEach(filteredFavorites) { favorite in
                        favoriteRow(favorite)
                    }
                }
            }
            .listStyle(.plain)
            .animation(.easeInOut(duration: 0.22), value: showSearch)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showRestaurantList) {
                RestaurantListView()
            }
            .navigationDestination(item: $selectedAuthor) { author in
                AuthorDetailView(author: author)
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
            .onReceive(NotificationCenter.default.publisher(for: .restaurantStateDidChange)) { notification in
                handleRestaurantStateChange(notification)
            }
            .sheet(item: $noteEditorContext) { context in
                FavoriteNoteEditorSheet(
                    restaurantName: context.restaurantName,
                    text: $editingNote,
                    onCancel: { noteEditorContext = nil },
                    onSave: {
                        Task { await saveFavoriteNote(context) }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .favoritesPageChrome(includeTabBar: true)
        }
    }

    private var filteredAuthors: [Author] {
        guard !searchText.isEmpty else { return authors }
        return authors.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredFavorites: [Favorite] {
        guard !searchText.isEmpty else { return favorites }
        return favorites.filter { favorite in
            favorite.restaurants?.name.localizedCaseInsensitiveContains(searchText) == true ||
            favorite.restaurants?.address?.localizedCaseInsensitiveContains(searchText) == true ||
            favorite.note?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    private var titleRow: some View {
        FavoritesCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("收藏")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(FavoritesTheme.title)
                        Text("关注的博主和收藏的店铺都在这里统一管理")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FavoritesTheme.secondary)
                    }

                    Spacer(minLength: DS.Spacing.md)

                    HStack(spacing: DS.Spacing.sm) {
                        headerToolButton(icon: "list.bullet") {
                            showRestaurantList = true
                        }
                        headerToolButton(icon: showSearch ? "xmark" : "magnifyingglass") {
                            toggleSearch()
                        }
                    }
                }

                HStack(spacing: DS.Spacing.sm) {
                    headerStatusPill(text: "\(authors.count) 位博主", tint: FavoritesTheme.secondary)
                    headerStatusPill(text: "\(favorites.count) 家收藏", tint: FavoritesTheme.accent)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func headerToolButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FavoritesTheme.body)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FavoritesTheme.border, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private func headerStatusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private var searchRow: some View {
        FavoritesCard {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FavoritesTheme.secondary)

                TextField("搜索店铺、地址或收藏理由", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(FavoritesTheme.title)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FavoritesTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onAppear {
            isSearchFocused = true
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

    private var authorsEmptyRow: some View {
        FavoritesEmptyStateCard(
            icon: "person.2.slash",
            title: searchText.isEmpty ? "还没有关注任何博主" : "没有匹配的博主",
            subtitle: searchText.isEmpty ? "关注博主后，这里会集中展示你常看的达人。" : "试试更换搜索词。"
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var authorsRow: some View {
        FavoritesCard {
            VStack(spacing: 0) {
                ForEach(Array(filteredAuthors.enumerated()), id: \.element.id) { index, author in
                    Button {
                        selectedAuthor = author
                    } label: {
                        FavoritesAuthorRow(author: author, subtitle: "抖音达人")
                    }
                    .buttonStyle(.plain)

                    if index != filteredAuthors.count - 1 {
                        Divider()
                            .overlay(FavoritesTheme.separator)
                            .padding(.leading, 78)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 16)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var favoritesEmptyRow: some View {
        FavoritesEmptyStateCard(
            icon: "bookmark.slash",
            title: searchText.isEmpty ? "还没有收藏任何店铺" : "没有匹配的收藏店铺",
            subtitle: searchText.isEmpty ? "在地图页点开店铺后收藏，这里会自动同步。" : "试试搜索店名、地址或收藏理由。"
        )
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func favoriteRow(_ favorite: Favorite) -> some View {
        let restaurant = favorite.restaurants
        let isAvoided = avoidedRestaurantIds.contains(favorite.restaurant_id)

        return FavoritesCard {
            if let restaurant {
                FavoritesRestaurantRow(
                    restaurant: restaurant,
                    configuration: FavoritesRestaurantRowConfiguration(
                        noteText: favorite.note,
                        addressText: restaurant.address,
                        badgeText: restaurant.category,
                        trailing: .actions([
                            FavoritesRestaurantRowAction(
                                id: "note-\(favorite.id)",
                                icon: favorite.note?.isEmpty == false ? "bubble.left.fill" : "bubble.left",
                                tint: favorite.note?.isEmpty == false ? FavoritesTheme.note : FavoritesTheme.secondary,
                                action: { beginEditingNote(for: favorite, restaurantName: restaurant.name) }
                            ),
                            FavoritesRestaurantRowAction(
                                id: "nav-\(favorite.id)",
                                icon: "location.fill",
                                tint: FavoritesTheme.nav,
                                action: { openNavigation(for: restaurant) }
                            )
                        ])
                    )
                )
                .onTapGesture {
                    selectedRestaurant = RestaurantDestination(
                        restaurant: restaurant,
                        restaurantId: favorite.restaurant_id
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deleteRestaurant(favorite) }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        Task { await toggleAvoid(favorite) }
                    } label: {
                        Label(isAvoided ? "取消避雷" : "避雷", systemImage: isAvoided ? "shield.slash" : "exclamationmark.shield")
                    }
                    .tint(.gray)

                    Button {
                        Task { await removeFavorite(favorite) }
                    } label: {
                        Label("取消收藏", systemImage: "bookmark.slash")
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

    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showSearch.toggle()
            if !showSearch {
                searchText = ""
                isSearchFocused = false
            }
        }
    }

    private func beginEditingNote(for favorite: Favorite, restaurantName: String) {
        editingNote = favorite.note ?? ""
        noteEditorContext = FavoriteNoteEditorContext(
            favoriteId: favorite.id,
            restaurantId: favorite.restaurant_id,
            restaurantName: restaurantName
        )
    }

    private func loadData() async {
        isLoading = true
        async let authorsTask: Void = loadAuthors()
        async let favoritesTask: Void = loadFavorites()
        async let avoidedTask: Void = loadAvoidedIds()
        _ = await (authorsTask, favoritesTask, avoidedTask)
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

    private func loadAvoidedIds() async {
        do {
            let avoided = try await APIService.shared.getAvoidedRestaurants(userId: authState.userId)
            avoidedRestaurantIds = Set(avoided.map(\.restaurant_id))
        } catch {
            print("[收藏页] 加载避雷失败: \(error)")
        }
    }

    private func saveFavoriteNote(_ context: FavoriteNoteEditorContext) async {
        let trimmedNote = editingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await APIService.shared.updateFavoriteNote(
                userId: authState.userId,
                restaurantId: context.restaurantId,
                note: trimmedNote
            )

            if let index = favorites.firstIndex(where: { $0.id == context.favoriteId }) {
                favorites[index].note = trimmedNote.isEmpty ? nil : trimmedNote
            }

            RestaurantStateChange(
                restaurantId: context.restaurantId,
                isFavorited: true,
                isAvoided: nil,
                favoriteNote: trimmedNote,
                isDeleted: false
            ).post()

            noteEditorContext = nil
        } catch {
            print("[收藏页] 更新收藏理由失败: \(error)")
        }
    }

    private func removeFavorite(_ favorite: Favorite) async {
        do {
            try await APIService.shared.removeFavorite(
                userId: authState.userId,
                restaurantId: favorite.restaurant_id
            )
            favorites.removeAll { $0.id == favorite.id }

            RestaurantStateChange(
                restaurantId: favorite.restaurant_id,
                isFavorited: false,
                isAvoided: avoidedRestaurantIds.contains(favorite.restaurant_id),
                favoriteNote: nil,
                isDeleted: false
            ).post()
        } catch {
            print("[收藏页] 取消收藏失败: \(error)")
        }
    }

    private func toggleAvoid(_ favorite: Favorite) async {
        let restaurantId = favorite.restaurant_id
        do {
            if avoidedRestaurantIds.contains(restaurantId) {
                try await APIService.shared.unavoidRestaurant(
                    userId: authState.userId,
                    restaurantId: restaurantId
                )
                avoidedRestaurantIds.remove(restaurantId)
            } else {
                try await APIService.shared.avoidRestaurant(
                    userId: authState.userId,
                    restaurantId: restaurantId
                )
                avoidedRestaurantIds.insert(restaurantId)
            }

            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: true,
                isAvoided: avoidedRestaurantIds.contains(restaurantId),
                favoriteNote: favorite.note,
                isDeleted: false
            ).post()
        } catch {
            print("[收藏页] 避雷操作失败: \(error)")
        }
    }

    private func deleteRestaurant(_ favorite: Favorite) async {
        do {
            try await APIService.shared.deleteRestaurantForUser(
                userId: authState.userId,
                restaurantId: favorite.restaurant_id
            )
            favorites.removeAll { $0.restaurant_id == favorite.restaurant_id }
            avoidedRestaurantIds.remove(favorite.restaurant_id)

            RestaurantStateChange(
                restaurantId: favorite.restaurant_id,
                isFavorited: false,
                isAvoided: false,
                favoriteNote: nil,
                isDeleted: true
            ).post()
        } catch {
            print("[收藏页] 删除失败: \(error)")
        }
    }

    private func openNavigation(for restaurant: Restaurant) {
        guard let latitude = restaurant.latitude, let longitude = restaurant.longitude else { return }
        let urlString = "maps://?daddr=\(latitude),\(longitude)&dirflg=d"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private func handleRestaurantStateChange(_ notification: Notification) {
        guard let change = RestaurantStateChange(notification) else { return }

        if change.isDeleted {
            favorites.removeAll { $0.restaurant_id == change.restaurantId }
            avoidedRestaurantIds.remove(change.restaurantId)
            return
        }

        if let isAvoided = change.isAvoided {
            if isAvoided {
                avoidedRestaurantIds.insert(change.restaurantId)
            } else {
                avoidedRestaurantIds.remove(change.restaurantId)
            }
        }

        if let isFavorited = change.isFavorited {
            if !isFavorited {
                favorites.removeAll { $0.restaurant_id == change.restaurantId }
                return
            }

            if favorites.contains(where: { $0.restaurant_id == change.restaurantId }) {
                if let note = change.favoriteNote,
                   let index = favorites.firstIndex(where: { $0.restaurant_id == change.restaurantId }) {
                    favorites[index].note = note.isEmpty ? nil : note
                }
            } else {
                Task { await loadFavorites() }
            }
        }
    }
}

private struct FavoriteNoteEditorSheet: View {
    let restaurantName: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                FavoritesTheme.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    Text("记录你喜欢这家店的理由")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FavoritesTheme.secondary)

                    FavoritesCard {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            Text(restaurantName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(FavoritesTheme.title)

                            TextEditor(text: $text)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(FavoritesTheme.body)
                                .frame(minHeight: 180)
                                .padding(.horizontal, 2)
                        }
                        .padding(DS.Spacing.lg)
                    }

                    Spacer()
                }
                .padding(DS.Spacing.lg)
            }
            .navigationTitle("收藏理由")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: onSave)
                        .bold()
                }
            }
            .favoritesPageChrome()
        }
    }
}
