// 地图主页面
// v7.0：13项地图UI/交互优化（浅色固定、定位朝向、点位蒙版、搜索历史、卡片升级、删除防误触）

import SwiftUI
import MapKit
import UIKit

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var authState: AuthState

    @Binding var refreshTrigger: Int

    @State private var selectedItem: MapDisplayItem? = nil
    @State private var showFilterPanel = false
    @State private var showAddMenu = false
    @State private var showParseSheet = false
    @State private var showUserAddSheet = false
    @State private var showNavSheet = false

    @State private var pendingParseLink: String? = nil
    @State private var parseAutoStart = false

    @State private var showClipboardPrompt = false
    @State private var clipboardLink = ""

    @State private var lastSelectedRestaurantId: String? = nil
    @State private var stagedDeletionRestaurantIds: Set<String> = []
    @State private var hiddenRestaurantIds: Set<String> = []

    @State private var selectedVideos: [RestaurantVideo] = []
    @State private var videoCache: [String: [RestaurantVideo]] = [:]
    @State private var isLoadingVideos = false

    @State private var showImagePreview = false
    @State private var previewImageURL: String? = nil

    @State private var toastMessage: String? = nil

    @State private var searchHistory: [String] = []
    @FocusState private var isSearchFocused: Bool

    @AppStorage("map_last_handled_clipboard_link") private var lastHandledClipboardLink = ""
    @AppStorage("map_last_clipboard_prompt_at") private var lastClipboardPromptAt = 0.0
    @AppStorage("map_recent_searches") private var searchHistoryStore = ""

    var body: some View {
        ZStack {
            mapLayer
                .zIndex(0)

            if showFilterPanel {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            showFilterPanel = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }

            topOverlay
                .zIndex(2)

            bottomCard
                .zIndex(3)

            if let toastMessage {
                toastView(message: toastMessage)
                    .zIndex(4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .task {
            await reloadAllData()
            locationManager.requestPermission()
            loadSearchHistory()
        }
        .onAppear {
            viewModel.startAutoRefresh(userId: authState.userId)
            detectClipboardLink()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .onChange(of: locationManager.locationUpdateCount) { _, _ in
            if let location = locationManager.userLocation, viewModel.isFirstLocationUpdate {
                viewModel.centerMapOnUserLocation(location)
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task { await reloadAllData() }
        }
        .onChange(of: viewModel.mapRestaurants.count) { _, _ in
            syncSelectionWithLatestData()
        }
        .onChange(of: viewModel.userRestaurants.count) { _, _ in
            syncSelectionWithLatestData()
        }
        .onChange(of: selectedItem?.id) { _, newId in
            handleSelectionTransition(newSelectedId: newId)
        }
        .confirmationDialog("添加店铺", isPresented: $showAddMenu, titleVisibility: .visible) {
            Button("解析抖音链接") {
                pendingParseLink = nil
                parseAutoStart = false
                showParseSheet = true
            }
            Button("手动添加店铺") { showUserAddSheet = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择添加方式")
        }
        .sheet(isPresented: $showParseSheet, onDismiss: {
            pendingParseLink = nil
            parseAutoStart = false
        }) {
            ParseLinkSheet(
                onSuccess: { refreshTrigger += 1 },
                initialLink: pendingParseLink,
                autoStart: parseAutoStart
            )
            .environmentObject(authState)
        }
        .sheet(isPresented: $showUserAddSheet) {
            UserAddRestaurantSheet(onSuccess: {
                refreshTrigger += 1
            })
            .environmentObject(authState)
        }
        .sheet(isPresented: $showImagePreview) {
            ImagePreviewSheet(imageURL: previewImageURL)
        }
        .confirmationDialog("选择导航应用", isPresented: $showNavSheet, titleVisibility: .visible) {
            if let item = selectedItem {
                Button("Apple 地图") { openAppleMaps(for: item) }
                Button("高德地图") { openAmap(for: item) }
                Button("百度地图") { openBaidu(for: item) }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("检测到抖音链接", isPresented: $showClipboardPrompt) {
            Button("确认添加") {
                pendingParseLink = clipboardLink
                parseAutoStart = true
                showParseSheet = true
                lastHandledClipboardLink = clipboardLink
            }
            Button("取消", role: .cancel) {
                // 避免同一链接重复打扰
                lastHandledClipboardLink = clipboardLink
            }
        } message: {
            Text("是否根据该链接添加店铺？")
        }
    }

    private var mapLayer: some View {
        Map(position: $viewModel.mapCameraPosition) {
            if let userLocation = locationManager.userLocation {
                Annotation("", coordinate: userLocation) {
                    UserLocationPinView(heading: locationManager.heading)
                }
            }

            ForEach(
                viewModel.clusteredItems(
                    userLocation: locationManager.userLocation,
                    hiddenRestaurantIds: hiddenRestaurantIds
                )
            ) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    if cluster.isCluster {
                        ClusterPinView(count: cluster.count)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.expandCluster(cluster)
                                }
                            }
                    } else if let item = cluster.primary {
                        RestaurantPinView(
                            avatarURL: item.author?.avatar_url ?? authState.avatarURL,
                            title: item.restaurant.name,
                            status: pinStatus(for: item),
                            isSelected: selectedItem?.id == item.id,
                            isHighlighted: viewModel.highlightedItemId == item.id,
                            isUserCreated: item.isUserCreated,
                            showTitle: viewModel.shouldShowStoreName
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedItem = item
                                viewModel.highlightedItemId = item.id
                            }
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onMapCameraChange(frequency: .continuous) { context in
            viewModel.updateVisibleRegion(context.region)
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedItem = nil
                showFilterPanel = false
                isSearchFocused = false
            }
        }
    }

    private var topOverlay: some View {
        GeometryReader { proxy in
            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    filterTriggerButton
                    Spacer(minLength: DS.Spacing.md)
                    addButton
                }

                HStack(spacing: DS.Spacing.sm) {
                    searchField
                    locateButton
                }

                if showFilterPanel {
                    FilterPanelView(
                        authors: viewModel.availableAuthors,
                        groups: viewModel.userGroups,
                        categories: viewModel.availableCategories,
                        filter: $viewModel.filter,
                        onReset: {
                            viewModel.clearFilters()
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if shouldShowSearchHistory {
                    SearchHistoryPanelView(
                        histories: searchHistory,
                        onSelect: { keyword in
                            applySearchHistory(keyword)
                        },
                        onClear: {
                            searchHistory = []
                            persistSearchHistory()
                        }
                    )
                    .transition(.opacity)
                }

                if shouldShowSearchResults {
                    SearchResultsView(
                        results: viewModel.searchResults(hiddenRestaurantIds: hiddenRestaurantIds)
                    ) { item in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedItem = item
                            viewModel.focus(on: item)
                            isSearchFocused = false
                        }
                        recordSearchHistory(viewModel.searchText)
                    }
                    .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, proxy.safeAreaInsets.top + DS.Spacing.sm)
            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: showFilterPanel)
        }
    }

    private var bottomCard: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                if let item = selectedItem,
                   !hiddenRestaurantIds.contains(item.restaurantId) {
                    MapQuickActionCard(
                        item: item,
                        videos: selectedVideos,
                        isLoadingVideos: isLoadingVideos,
                        isMarkedDeleted: stagedDeletionRestaurantIds.contains(item.restaurantId),
                        onFavorite: { toggleFavorite(item) },
                        onAvoid: { toggleAvoid(item) },
                        onToggleDelete: { toggleDeleteMark(item) },
                        onNavigate: { showNavSheet = true },
                        onSharePlaceholder: { showToast("分享功能即将上线") },
                        onOpenSource: { openVideoSource(for: item) },
                        onCopyName: { copyText(item.restaurant.name, label: "店铺名称") },
                        onCopyAuthor: {
                            if let authorName = item.author?.name {
                                copyText(authorName, label: "博主名称")
                            }
                        },
                        onPreviewImage: {
                            if let photo = item.restaurant.photo_url, !photo.isEmpty {
                                previewImageURL = photo
                                showImagePreview = true
                            }
                        }
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 62, 92))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selectedItem?.id)
                }
            }
        }
    }

    private var filterTriggerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showFilterPanel.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 15, weight: .semibold))
                Text(filterTitle)
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: showFilterPanel ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: 40)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(DS.Color.separator.opacity(0.25), lineWidth: 0.6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    private var filterTitle: String {
        viewModel.hasActiveFilters ? "已筛选(\(viewModel.activeFilterCount))" : "全部"
    }

    private var addButton: some View {
        MapToolCircleButton(icon: "plus", isStrong: true) {
            showAddMenu = true
        }
    }

    private var locateButton: some View {
        MapToolCircleButton(icon: "location") {
            if let location = locationManager.userLocation {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.centerMapOnUserLocation(location)
                }
            } else {
                locationManager.requestPermission()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索店铺或博主", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isSearchFocused)
                .onSubmit {
                    commitSearchTerm(viewModel.searchText)
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.separator.opacity(0.15), lineWidth: 0.5)
        }
    }

    private var shouldShowSearchResults: Bool {
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !keyword.isEmpty && !viewModel.searchResults(hiddenRestaurantIds: hiddenRestaurantIds).isEmpty
    }

    private var shouldShowSearchHistory: Bool {
        isSearchFocused
            && viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !searchHistory.isEmpty
    }

    private func pinStatus(for item: MapDisplayItem) -> PinVisualStatus {
        if item.isAvoided { return .avoided }
        if item.isFavorited { return .favorited }
        return .normal
    }

    private func reloadAllData() async {
        await viewModel.loadMapData(userId: authState.userId)
        await viewModel.loadUserGroups(userId: authState.userId)
        syncSelectionWithLatestData()
    }

    private func syncSelectionWithLatestData() {
        guard let selected = selectedItem else { return }
        if hiddenRestaurantIds.contains(selected.restaurantId) {
            selectedItem = nil
            return
        }

        if let latest = viewModel.allItems.first(where: { $0.id == selected.id }) {
            selectedItem = latest
            return
        }
        if let byRestaurant = viewModel.allItems.first(where: { $0.restaurantId == selected.restaurantId }) {
            selectedItem = byRestaurant
            return
        }
        selectedItem = nil
    }

    private func handleSelectionTransition(newSelectedId: String?) {
        let previousRestaurantId = lastSelectedRestaurantId

        if let newSelectedId,
           let currentItem = viewModel.allItems.first(where: { $0.id == newSelectedId }) {
            lastSelectedRestaurantId = currentItem.restaurantId
            loadVideos(for: currentItem)
        } else {
            lastSelectedRestaurantId = nil
            selectedVideos = []
            isLoadingVideos = false
        }

        if let previousRestaurantId,
           previousRestaurantId != lastSelectedRestaurantId,
           stagedDeletionRestaurantIds.contains(previousRestaurantId) {
            Task {
                await commitDeletion(restaurantIds: [previousRestaurantId])
            }
        }
    }

    private func loadVideos(for item: MapDisplayItem) {
        let restaurantId = item.restaurantId
        if let cached = videoCache[restaurantId] {
            selectedVideos = cached
            isLoadingVideos = false
            return
        }

        isLoadingVideos = true
        Task {
            do {
                let videos = try await APIService.shared.getRestaurantVideos(restaurantId: restaurantId)
                await MainActor.run {
                    videoCache[restaurantId] = videos
                    if selectedItem?.restaurantId == restaurantId {
                        selectedVideos = videos
                    }
                    isLoadingVideos = false
                }
            } catch {
                await MainActor.run {
                    if selectedItem?.restaurantId == restaurantId {
                        selectedVideos = []
                    }
                    isLoadingVideos = false
                }
            }
        }
    }

    private func toggleFavorite(_ item: MapDisplayItem) {
        Task {
            do {
                if item.isFavorited {
                    try await APIService.shared.removeFavorite(userId: authState.userId, restaurantId: item.restaurantId)
                    showToast("已取消收藏")
                } else {
                    try await APIService.shared.addFavorite(userId: authState.userId, restaurantId: item.restaurantId)
                    showToast("已收藏")
                }
                await reloadAllData()
            } catch {
                showToast("收藏操作失败")
                print("[地图] 收藏操作失败: \(error)")
            }
        }
    }

    private func toggleAvoid(_ item: MapDisplayItem) {
        Task {
            do {
                if item.isAvoided {
                    try await APIService.shared.unavoidRestaurant(userId: authState.userId, restaurantId: item.restaurantId)
                    showToast("已取消避雷")
                } else {
                    try await APIService.shared.avoidRestaurant(userId: authState.userId, restaurantId: item.restaurantId)
                    showToast("已标记避雷")
                }
                await reloadAllData()
            } catch {
                showToast("避雷操作失败")
                print("[地图] 避雷操作失败: \(error)")
            }
        }
    }

    private func toggleDeleteMark(_ item: MapDisplayItem) {
        if stagedDeletionRestaurantIds.contains(item.restaurantId) {
            stagedDeletionRestaurantIds.remove(item.restaurantId)
            showToast("已取消删除标记")
        } else {
            stagedDeletionRestaurantIds.insert(item.restaurantId)
            showToast("已标记删除，关闭卡片后生效")
        }
    }

    private func commitDeletion(restaurantIds: [String]) async {
        guard !restaurantIds.isEmpty else { return }

        let targetSet = Set(restaurantIds)
        stagedDeletionRestaurantIds.subtract(targetSet)
        hiddenRestaurantIds.formUnion(targetSet)

        if let currentSelected = selectedItem,
           targetSet.contains(currentSelected.restaurantId) {
            selectedItem = nil
        }

        var failedIds: [String] = []
        for restaurantId in targetSet {
            do {
                try await APIService.shared.deleteRestaurantForUser(userId: authState.userId, restaurantId: restaurantId)
            } catch {
                failedIds.append(restaurantId)
                print("[地图] 删除店铺失败 \(restaurantId): \(error)")
            }
        }

        if !failedIds.isEmpty {
            hiddenRestaurantIds.subtract(failedIds)
            stagedDeletionRestaurantIds.formUnion(failedIds)
            showToast("部分删除失败，请重试")
        } else {
            showToast("删除已生效")
        }

        await reloadAllData()
        hiddenRestaurantIds.subtract(targetSet)
    }

    private func detectClipboardLink() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }

        guard let link = extractURL(from: text), isDouyinURL(link) else { return }
        guard link != lastHandledClipboardLink else { return }

        let now = Date().timeIntervalSince1970
        if now - lastClipboardPromptAt < 10 {
            return
        }

        clipboardLink = link
        lastClipboardPromptAt = now
        showClipboardPrompt = true
    }

    private func extractURL(from text: String) -> String? {
        if isDouyinURL(text) { return text }
        if let range = text.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    private func isDouyinURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("douyin.com") || lower.contains("iesdouyin.com") || lower.contains("v.douyin.com")
    }

    private func commitSearchTerm(_ keyword: String) {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        recordSearchHistory(normalized)
        if let first = viewModel.searchResults(hiddenRestaurantIds: hiddenRestaurantIds).first {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedItem = first
                viewModel.focus(on: first)
                isSearchFocused = false
            }
        }
    }

    private func applySearchHistory(_ keyword: String) {
        viewModel.searchText = keyword
        commitSearchTerm(keyword)
    }

    private func loadSearchHistory() {
        guard let data = searchHistoryStore.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            searchHistory = []
            return
        }
        searchHistory = decoded
    }

    private func persistSearchHistory() {
        guard let data = try? JSONEncoder().encode(searchHistory),
              let text = String(data: data, encoding: .utf8) else {
            searchHistoryStore = ""
            return
        }
        searchHistoryStore = text
    }

    private func recordSearchHistory(_ keyword: String) {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        searchHistory.removeAll(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame })
        searchHistory.insert(normalized, at: 0)
        if searchHistory.count > 10 {
            searchHistory = Array(searchHistory.prefix(10))
        }
        persistSearchHistory()
    }

    private func openVideoSource(for item: MapDisplayItem) {
        if let videoURL = selectedVideos.first?.douyinURL {
            UIApplication.shared.open(videoURL)
            return
        }
        if let profileURL = douyinProfileURL(for: item.author?.douyin_uid) {
            UIApplication.shared.open(profileURL)
            return
        }
        showToast("暂无可跳转的视频源")
    }

    private func douyinProfileURL(for uid: String?) -> URL? {
        guard let uid, !uid.isEmpty else { return nil }
        return URL(string: "https://www.douyin.com/user/\(uid)")
    }

    private func copyText(_ text: String, label: String) {
        UIPasteboard.general.string = text
        showToast("\(label)已复制")
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.18)) {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }

    private func toastView(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.72), in: Capsule())
                .padding(.bottom, 128)
        }
    }

    private func openAppleMaps(for item: MapDisplayItem) {
        let coordinate = item.coordinate
        let placeMark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placeMark)
        mapItem.name = item.restaurant.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openAmap(for item: MapDisplayItem) {
        let coordinate = item.coordinate
        let encodedName = item.restaurant.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.restaurant.name
        let urlString = "iosamap://navi?sourceApplication=FoodMap&backScheme=foodmap&lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&dev=0&style=2&poiname=\(encodedName)"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            openAppleMaps(for: item)
        }
    }

    private func openBaidu(for item: MapDisplayItem) {
        let coordinate = item.coordinate
        let encodedName = item.restaurant.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? item.restaurant.name
        let urlString = "baidumap://map/direction?destination=latlng:\(coordinate.latitude),\(coordinate.longitude)|name:\(encodedName)&mode=driving&coord_type=gcj02"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            openAppleMaps(for: item)
        }
    }
}

// MARK: - Top Buttons
struct MapToolCircleButton: View {
    let icon: String
    var isStrong: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isStrong ? 18 : 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(
                    .ultraThinMaterial,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(DS.Color.separator.opacity(0.25), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .contentShape(Circle())
    }
}

// MARK: - Pins
enum PinVisualStatus {
    case normal
    case favorited
    case avoided
}

struct RestaurantPinView: View {
    let avatarURL: String?
    let title: String
    let status: PinVisualStatus
    let isSelected: Bool
    let isHighlighted: Bool
    let isUserCreated: Bool
    let showTitle: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                AsyncImage(url: URL(string: avatarURL ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: isUserCreated ? "person.crop.circle.badge.plus" : "person.crop.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: size - 4, height: size - 4)
                        .background(
                            Circle().fill(isUserCreated ? Color.purple.opacity(0.8) : DS.Color.brand.opacity(0.8))
                        )
                }
                .frame(width: size, height: size)
                .clipShape(Circle())

                if status != .normal {
                    Circle()
                        .fill(maskColor.opacity(0.42))
                        .frame(width: size, height: size)
                    Image(systemName: maskIcon)
                        .font(.system(size: isSelected ? 14 : 12, weight: .bold))
                        .foregroundColor(.white)
                }

                if isHighlighted {
                    Circle()
                        .stroke(DS.Color.brand, lineWidth: 2)
                        .frame(width: size + 6, height: size + 6)
                }
            }
            .overlay {
                Circle()
                    .stroke(isSelected ? DS.Color.brand : Color.white.opacity(0.55), lineWidth: isSelected ? 2 : 0.8)
            }
            .shadow(color: .black.opacity(isSelected ? 0.25 : 0.15), radius: isSelected ? 6 : 3, y: 2)

            if showTitle {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(DS.Color.separator.opacity(0.2), lineWidth: 0.5)
                    }
                    .frame(maxWidth: 120)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isSelected)
    }

    private var size: CGFloat { isSelected ? 42 : 34 }

    private var maskColor: Color {
        switch status {
        case .normal: return .clear
        case .favorited: return .red
        case .avoided: return .orange
        }
    }

    private var maskIcon: String {
        switch status {
        case .normal: return ""
        case .favorited: return "heart.fill"
        case .avoided: return "exclamationmark.triangle.fill"
        }
    }
}

struct UserLocationPinView: View {
    let heading: CLLocationDirection?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)

            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)

            Image(systemName: "location.north.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.blue)
                .offset(y: -16)
                .rotationEffect(.degrees(heading ?? 0))
        }
    }
}

struct ClusterPinView: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.Color.brand)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Filter Panel
struct FilterPanelView: View {
    let authors: [Author]
    let groups: [RestaurantGroup]
    let categories: [String]
    @Binding var filter: MapFilterState
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("筛选")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("重置") { onReset() }
                    .font(.caption)
                    .foregroundColor(DS.Color.brand)
            }

            section("博主") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        SingleChip(title: "全部", selected: filter.author == .all) {
                            filter.author = .all
                        }
                        SingleChip(title: "我的推荐", selected: filter.author == .mine, tint: .purple) {
                            filter.author = .mine
                        }
                        ForEach(authors) { author in
                            SingleChip(title: author.name, selected: filter.author == .author(author.id)) {
                                filter.author = .author(author.id)
                            }
                        }
                    }
                }
            }

            section("店铺分组") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        SingleChip(title: "全部", selected: filter.group == .all) {
                            filter.group = .all
                        }
                        SingleChip(title: "收藏", selected: filter.group == .favorites, tint: .red) {
                            filter.group = .favorites
                        }
                        SingleChip(title: "避雷", selected: filter.group == .avoided, tint: .orange) {
                            filter.group = .avoided
                        }
                        ForEach(groups) { group in
                            SingleChip(
                                title: group.name,
                                selected: filter.group == .custom(group.id)
                            ) {
                                filter.group = .custom(group.id)
                            }
                        }
                    }
                }
            }

            section("距离") {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(MapDistanceFilter.allCases) { option in
                        SingleChip(title: option.title, selected: filter.distance == option) {
                            filter.distance = option
                        }
                    }
                }
            }

            section("美食分类") {
                if categories.isEmpty {
                    Text("暂无分类数据")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    FlexibleChipGrid(items: categories) { category in
                        filter.categories.toggleMembership(category)
                    } isSelected: { category in
                        filter.categories.contains(category)
                    }
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.separator.opacity(0.18), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
    }
}

struct SingleChip: View {
    let title: String
    let selected: Bool
    var tint: Color = DS.Color.brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 6)
                .background(selected ? tint : DS.Color.surface)
                .clipShape(Capsule())
                .overlay {
                    if !selected {
                        Capsule().stroke(DS.Color.separator.opacity(0.22), lineWidth: 0.6)
                    }
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(selected ? 1.02 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: selected)
    }
}

struct FlexibleChipGrid: View {
    let items: [String]
    let onTap: (String) -> Void
    let isSelected: (String) -> Bool

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 72), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                SingleChip(title: item, selected: isSelected(item), action: {
                    onTap(item)
                })
            }
        }
    }
}

// MARK: - Search
struct SearchHistoryPanelView: View {
    let histories: [String]
    let onSelect: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("近期搜索")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("清空") {
                    onClear()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            FlexibleHistoryGrid(items: histories, onSelect: onSelect)
        }
        .padding(DS.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.separator.opacity(0.18), lineWidth: 0.6)
        }
    }
}

struct FlexibleHistoryGrid: View {
    let items: [String]
    let onSelect: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(item)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(DS.Color.surface, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(DS.Color.separator.opacity(0.2), lineWidth: 0.6)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SearchResultsView: View {
    let results: [MapDisplayItem]
    let onSelect: (MapDisplayItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(results.prefix(6)) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.restaurant.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(searchSubtitle(for: item))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if item.id != results.prefix(6).last?.id {
                    Divider()
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.separator.opacity(0.18), lineWidth: 0.6)
        }
    }

    private func searchSubtitle(for item: MapDisplayItem) -> String {
        let authorText = item.author?.name ?? "我的推荐"
        if let address = item.restaurant.address, !address.isEmpty {
            return "\(authorText) · \(address)"
        }
        return authorText
    }
}

// MARK: - Bottom Card
struct MapQuickActionCard: View {
    let item: MapDisplayItem
    let videos: [RestaurantVideo]
    let isLoadingVideos: Bool
    let isMarkedDeleted: Bool
    let onFavorite: () -> Void
    let onAvoid: () -> Void
    let onToggleDelete: () -> Void
    let onNavigate: () -> Void
    let onSharePlaceholder: () -> Void
    let onOpenSource: () -> Void
    let onCopyName: () -> Void
    let onCopyAuthor: () -> Void
    let onPreviewImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Button(action: onPreviewImage) {
                    AsyncImage(url: URL(string: item.restaurant.photo_url ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.Color.surfaceAlt)
                            .overlay(Image(systemName: "photo").foregroundColor(.gray))
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(item.restaurant.name)
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(2)
                        Button(action: onCopyName) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if let address = item.restaurant.address, !address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    HStack(spacing: 6) {
                        if item.isUserCreated {
                            MiniTag(text: "我的推荐", color: .purple)
                        }
                        if item.isAvoided {
                            MiniTag(text: "避雷", color: .orange)
                        } else if item.isFavorited {
                            MiniTag(text: "收藏", color: .red)
                        }
                        if let category = item.restaurant.category, !category.isEmpty {
                            MiniTag(text: category, color: DS.Color.brand)
                        }
                    }
                }
            }

            authorModule

            if isMarkedDeleted {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                    Text("已标记删除，关闭卡片后从地图移除")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                CardActionButton(
                    title: item.isFavorited ? "取消收藏" : "收藏",
                    icon: item.isFavorited ? "heart.slash" : "heart.fill",
                    tint: .red,
                    action: onFavorite
                )
                CardActionButton(
                    title: item.isAvoided ? "取消避雷" : "避雷",
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    action: onAvoid
                )
                CardActionButton(
                    title: isMarkedDeleted ? "取消删除" : "标记删除",
                    icon: isMarkedDeleted ? "trash.slash" : "trash",
                    tint: .gray,
                    action: onToggleDelete
                )
                CardActionButton(
                    title: "导航",
                    icon: "arrow.triangle.turn.up.right.diamond.fill",
                    tint: .blue,
                    action: onNavigate
                )
                CardActionButton(
                    title: "分享",
                    icon: "square.and.arrow.up",
                    tint: .gray,
                    action: onSharePlaceholder
                )
                CardActionButton(
                    title: isLoadingVideos ? "加载中" : "视频源",
                    icon: "play.rectangle.fill",
                    tint: .purple,
                    action: onOpenSource
                )
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.separator.opacity(0.12), lineWidth: 0.6)
        }
        .shadow(color: DS.Shadow.cardColor, radius: DS.Shadow.cardRadius, y: DS.Shadow.cardY)
    }

    private var authorModule: some View {
        HStack(spacing: DS.Spacing.sm) {
            AsyncImage(url: URL(string: item.author?.avatar_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle()
                    .fill(DS.Color.surfaceAlt)
                    .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())

            Text(item.author?.name ?? "我的推荐")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Button(action: onCopyAuthor) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onOpenSource) {
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                    Text(videos.isEmpty ? "抖音主页" : "探店视频")
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Color.brand)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DS.Color.brand.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct MiniTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct CardActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
}

struct ImagePreviewSheet: View {
    let imageURL: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: URL(string: imageURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
    }
}

private extension Set where Element == String {
    mutating func toggleMembership(_ value: String) {
        if contains(value) {
            remove(value)
        } else {
            insert(value)
        }
    }
}

struct PressableScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
