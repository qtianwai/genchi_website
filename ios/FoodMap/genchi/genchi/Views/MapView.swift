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
    @State private var showSearchField = false
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

    // 距离筛选雷达动画
    @State private var radarPhase: Double = 0
    private var radarTimer: Timer? = nil

    private var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

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
            if let location = locationManager.userLocation, viewModel.isFirstLocationUpdate {
                viewModel.centerMapOnUserLocation(location)
            }
        }
        .onAppear {
            viewModel.startAutoRefresh(userId: authState.userId)
            detectClipboardLink()
            startRadarAnimation()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
            stopRadarAnimation()
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
        .onReceive(NotificationCenter.default.publisher(for: .restaurantStateDidChange)) { _ in
            Task { await reloadAllData() }
        }
        .sheet(isPresented: $showAddMenu) {
            MapAddEntrySheet(
                onParseLink: {
                    pendingParseLink = nil
                    parseAutoStart = false
                    presentAddDestination(.parseLink)
                },
                onManualAdd: {
                    presentAddDestination(.manualAdd)
                }
            )
            .presentationDetents([.height(268)])
            .presentationDragIndicator(.visible)
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
                Button("高德地图") { openAmap(for: item) }
                Button("Apple 地图") { openAppleMaps(for: item) }
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

                // v7.1 新增：距离筛选雷达圈（以用户定位为中心）
                if viewModel.filter.distance != .all,
                   let radius = viewModel.filter.distance.kilometers {
                    MapCircle(center: userLocation, radius: radius * 1000)
                        .foregroundStyle(
                            DS.Color.brand.opacity(0.10 + radarPhase * 0.04)
                        )
                        .stroke(
                            DS.Color.brand.opacity(0.35 + radarPhase * 0.15),
                            lineWidth: 1.5 + radarPhase * 0.5
                        )
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
                            isSelected: selectedItem?.id == item.id,
                            isHighlighted: viewModel.highlightedItemId == item.id,
                            isUserCreated: item.isUserCreated,
                            showTitle: viewModel.shouldShowStoreName,
                            recommendSourceCount: item.recommendedBy.count  // v6.0 新增：推荐来源数量
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
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.updateVisibleRegion(context.region, forceRefresh: true)
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedItem = nil
                showFilterPanel = false
                showSearchField = false
                isSearchFocused = false
            }
        }
    }

    private var topOverlay: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top)

            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    filterTriggerButton
                    searchTriggerButton
                    Spacer(minLength: 0)
                    VStack(spacing: DS.Spacing.sm) {
                        addButton
                        locateButton
                    }
                }

                if showSearchField {
                    searchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showFilterPanel {
                    FilterPanelView(
                        authors: viewModel.availableAuthors,
                        groups: viewModel.userGroups,
                        subscriptions: viewModel.mapSubscriptions,  // v6.0 新增：订阅用户列表
                        filter: $viewModel.filter,
                        onReset: {
                            viewModel.clearFilters()
                        }
                    )
                    .padding(.top, 2)
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
                            showSearchField = false
                            isSearchFocused = false
                        }
                        recordSearchHistory(viewModel.searchText)
                    }
                    .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, topInset + 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: showFilterPanel)
            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: showSearchField)
        }
    }

    private var bottomCard: some View {
        GeometryReader { proxy in
            let bottomInset = max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)

            VStack {
                Spacer()
                if let item = selectedItem,
                   !hiddenRestaurantIds.contains(item.restaurantId) {
                    MapQuickActionCard(
                        item: item,
                        videos: selectedVideos,
                        currentUserName: authState.nickname,
                        currentUserAvatarURL: authState.avatarURL,
                        isMarkedDeleted: stagedDeletionRestaurantIds.contains(item.restaurantId),
                        onFavorite: { toggleFavorite(item) },
                        onAvoid: { toggleAvoid(item) },
                        onToggleDelete: { toggleDeleteMark(item) },
                        onNavigate: { showNavSheet = true },
                        onSharePlaceholder: { showToast("分享功能即将上线") },
                        onOpenSource: { openVideoSource(for: item) },
                        onCopyName: { copyText(item.restaurant.name, label: "店铺名称") },
                        onCopyAuthor: { name in
                            copyText(name, label: "推荐人名称")
                        },
                        onPreviewImage: {
                            if let photo = item.restaurant.photo_url, !photo.isEmpty {
                                previewImageURL = photo
                                showImagePreview = true
                            }
                        }
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, max(bottomInset + 62, 92))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selectedItem?.id)
                }
            }
        }
    }

    private var filterTriggerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSearchField = false
                isSearchFocused = false
                if viewModel.filter.author == .mine {
                    viewModel.filter.author = .all
                }
                showFilterPanel.toggle()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)

                if viewModel.hasActiveFilters {
                    Text("\(viewModel.activeFilterCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(DS.Color.brand, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
            .frame(width: 44, height: 44)
            .background(DS.Color.surface.opacity(0.96), in: Circle())
            .overlay {
                Circle()
                    .stroke(DS.Color.separator.opacity(0.18), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    private var addButton: some View {
        Button {
            showAddMenu = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(DS.Color.surfaceAlt.opacity(0.95), in: Circle())
                .overlay {
                    Circle()
                        .stroke(DS.Color.separator.opacity(0.18), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    private var locateButton: some View {
        MapToolCircleButton(icon: "location.fill", style: .neutral) {
            if let location = locationManager.userLocation {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.centerMapOnUserLocation(location)
                }
            } else {
                locationManager.requestPermission()
            }
        }
    }

    private var searchTriggerButton: some View {
        Button {
            let shouldShow = !showSearchField
            withAnimation(.easeInOut(duration: 0.2)) {
                showFilterPanel = false
                showSearchField = shouldShow
                if !shouldShow {
                    viewModel.searchText = ""
                    isSearchFocused = false
                }
            }

            if shouldShow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isSearchFocused = true
                }
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(showSearchField ? DS.Color.brand : .primary)
                .frame(width: 44, height: 44)
                .background(DS.Color.surface.opacity(0.96), in: Circle())
                .overlay {
                    Circle()
                        .stroke(DS.Color.separator.opacity(0.18), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(PressableScaleButtonStyle())
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

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.searchText = ""
                    showSearchField = false
                    isSearchFocused = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(DS.Color.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(height: 46)
        .background(DS.Color.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.separator.opacity(0.15), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private var shouldShowSearchResults: Bool {
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return showSearchField
            && !keyword.isEmpty
            && !viewModel.searchResults(hiddenRestaurantIds: hiddenRestaurantIds).isEmpty
    }

    private var shouldShowSearchHistory: Bool {
        showSearchField
            && isSearchFocused
            && viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !searchHistory.isEmpty
    }

    private func reloadAllData() async {
        await viewModel.loadMapData(userId: authState.userId)
        await viewModel.loadUserGroups(userId: authState.userId)
        syncSelectionWithLatestData()
    }

    private func presentAddDestination(_ destination: MapAddDestination) {
        showAddMenu = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch destination {
            case .parseLink:
                showParseSheet = true
            case .manualAdd:
                showUserAddSheet = true
            }
        }
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
                showSearchField = false
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
        // v7.1 改进：优先从 recommendedBy 中找博主兜底，再 fallback 到 item.author
        if let uid = primaryDouyinAuthorUID(for: item) {
            if let url = URL(string: "snssdk1128://aweme/detail/\(uid)") {
                UIApplication.shared.open(url)
                return
            }
            if let webURL = douyinProfileURL(for: uid) {
                UIApplication.shared.open(webURL)
                return
            }
        }
        showToast("暂无可跳转的视频源")
    }

    /// 从推荐来源链中提取首个有 douyin_uid 的博主（与 MapQuickActionCard.primaryDouyinAuthor 保持一致）
    private func primaryDouyinAuthorUID(for item: MapDisplayItem) -> String? {
        for source in item.recommendedBy {
            if case .author(let author) = source, let uid = author.douyin_uid, !uid.isEmpty {
                return uid
            }
        }
        return item.author?.douyin_uid
    }

    private func douyinProfileURL(for uid: String?) -> URL? {
        guard let uid, !uid.isEmpty else { return nil }
        return URL(string: "https://www.douyin.com/user/\(uid)")
    }

    // ─────────────────────────────────────────
    // 距离筛选雷达动画（v7.1 新增）
    // ─────────────────────────────────────────
    private func startRadarAnimation() {
        radarTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                radarPhase = (radarPhase + 0.04).truncatingRemainder(dividingBy: 1.0)
            }
        }
        radarTimer?.tolerance = 0.01
    }

    private func stopRadarAnimation() {
        radarTimer?.invalidate()
        radarTimer = nil
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
    enum Style {
        case neutral
        case strong
    }

    let icon: String
    var style: Style = .neutral
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: style == .strong ? 18 : 15, weight: .semibold))
                .foregroundColor(style == .strong ? .white : .primary)
                .frame(width: 44, height: 44)
                .background(
                    backgroundColor,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: style == .strong ? 0 : 0.6)
                }
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .contentShape(Circle())
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral:
            return DS.Color.surfaceAlt.opacity(0.95)
        case .strong:
            return DS.Color.brand
        }
    }

    private var borderColor: Color {
        switch style {
        case .neutral:
            return DS.Color.separator.opacity(0.18)
        case .strong:
            return .clear
        }
    }
}

// MARK: - Pins
struct RestaurantPinView: View {
    let avatarURL: String?
    let title: String
    let isSelected: Bool
    let isHighlighted: Bool
    let isUserCreated: Bool
    let showTitle: Bool
    let recommendSourceCount: Int  // v6.0 新增：推荐来源数量

    init(
        avatarURL: String?,
        title: String,
        isSelected: Bool,
        isHighlighted: Bool,
        isUserCreated: Bool,
        showTitle: Bool,
        recommendSourceCount: Int = 1
    ) {
        self.avatarURL = avatarURL
        self.title = title
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.isUserCreated = isUserCreated
        self.showTitle = showTitle
        self.recommendSourceCount = recommendSourceCount
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
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

                // v6.0 新增：多人推荐角标
                if recommendSourceCount > 1 {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 20, height: 20)
                        Text("\(recommendSourceCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                }
            }

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
    let subscriptions: [MapSubscription]  // v6.0 新增：订阅用户列表
    @Binding var filter: MapFilterState
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("筛选")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("重置") { onReset() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Color.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DS.Color.brand.opacity(0.10), in: Capsule())
            }

            sectionCard("关注的人", systemImage: "person.2.fill") {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: DS.Spacing.sm), GridItem(.flexible(), spacing: DS.Spacing.sm)],
                        alignment: .leading,
                        spacing: DS.Spacing.sm
                    ) {
                        SourceFilterPill(
                            name: "全部店铺",
                            avatarURL: nil,
                            systemIcon: "square.grid.2x2.fill",
                            isSelected: filter.author == .all
                        ) {
                            filter.author = .all
                        }

                        ForEach(sourceOptions) { option in
                            SourceFilterPill(
                                name: option.name,
                                avatarURL: option.avatarURL,
                                systemIcon: nil,
                                isSelected: isSourceSelected(option)
                            ) {
                                filter.author = option.filter
                            }
                        }
                    }
                }
            }

            sectionCard("店铺分组", systemImage: "square.grid.2x2.fill") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 78), spacing: DS.Spacing.sm)],
                    alignment: .leading,
                    spacing: DS.Spacing.sm
                ) {
                    Group {
                        SingleChip(title: "全部", selected: filter.group == .all) {
                            filter.group = .all
                        }
                        SingleChip(title: "收藏", selected: filter.group == .favorites) {
                            filter.group = .favorites
                        }
                        SingleChip(title: "避雷", selected: filter.group == .avoided, tint: .orange) {
                            filter.group = .avoided
                        }
                        ForEach(groups) { group in
                            SingleChip(title: group.name, selected: filter.group == .custom(group.id)) {
                                filter.group = .custom(group.id)
                            }
                        }
                    }
                }
            }

            sectionCard("距离范围", systemImage: "location.circle.fill") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 64), spacing: DS.Spacing.sm)],
                    alignment: .leading,
                    spacing: DS.Spacing.sm
                ) {
                    ForEach(MapDistanceFilter.allCases) { option in
                        SingleChip(title: option.title, selected: filter.distance == option) {
                            filter.distance = option
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.Color.separator.opacity(0.14), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private var sourceOptions: [MapSourceOption] {
        let authorOptions = authors.map {
            MapSourceOption(
                id: "author-\($0.id)",
                name: $0.name,
                avatarURL: $0.avatar_url,
                filter: .author($0.id)
            )
        }

        let subscriptionOptions = subscriptions.map {
            MapSourceOption(
                id: "subscription-\($0.target_user_id)",
                name: $0.nickname,
                avatarURL: $0.avatar_url,
                filter: .subscribedUser($0.target_user_id)
            )
        }

        return (authorOptions + subscriptionOptions)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isSourceSelected(_ option: MapSourceOption) -> Bool {
        filter.author == option.filter
    }

    private func sectionCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Color.brand)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            content()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
        }
    }
}

private struct MapSourceOption: Identifiable {
    let id: String
    let name: String
    let avatarURL: String?
    let filter: MapAuthorFilter
}

private struct SourceFilterPill: View {
    let name: String
    let avatarURL: String?
    let systemIcon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                avatarView

                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? DS.Color.brand : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Color.brand)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? DS.Color.brand.opacity(0.10) : DS.Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? DS.Color.brand.opacity(0.22) : DS.Color.separator.opacity(0.14), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let systemIcon {
            Circle()
                .fill(isSelected ? DS.Color.brand.opacity(0.14) : DS.Color.surfaceAlt)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: systemIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? DS.Color.brand : .secondary)
                )
        } else {
            AsyncImage(url: URL(string: avatarURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(DS.Color.surfaceAlt)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    )
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
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
                .foregroundColor(selected ? tint : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? tint.opacity(0.14) : DS.Color.surface)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(selected ? tint.opacity(0.28) : DS.Color.separator.opacity(0.18), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(selected ? 1.02 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: selected)
    }
}

private enum MapAddDestination {
    case parseLink
    case manualAdd
}

private struct MapAddEntrySheet: View {
    let onParseLink: () -> Void
    let onManualAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("添加新店")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text("选一种更顺手的方式，把想去的店放进地图")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: DS.Spacing.sm) {
                addOptionButton(
                    icon: "link.badge.plus",
                    title: "从抖音添加",
                    subtitle: "粘贴视频链接，自动识别店铺和推荐人"
                ) {
                    onParseLink()
                }

                addOptionButton(
                    icon: "fork.knife.circle",
                    title: "搜索店铺添加",
                    subtitle: "输入店名和城市，直接把这家店加入地图"
                ) {
                    onManualAdd()
                }
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }

    private func addOptionButton(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DS.Color.brand.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DS.Color.brand)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.separator.opacity(0.12), lineWidth: 0.8)
            }
        }
        .buttonStyle(PressableScaleButtonStyle())
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
    let currentUserName: String
    let currentUserAvatarURL: String?
    let isMarkedDeleted: Bool
    let onFavorite: () -> Void
    let onAvoid: () -> Void
    let onToggleDelete: () -> Void
    let onNavigate: () -> Void
    let onSharePlaceholder: () -> Void
    let onOpenSource: () -> Void
    let onCopyName: () -> Void
    let onCopyAuthor: (String) -> Void
    let onPreviewImage: () -> Void

    // v7.1 新增：探店视频兜底用（支持推荐来源中首个有效博主）
    private var primaryDouyinAuthor: Author? {
        for source in item.recommendedBy {
            if case .author(let author) = source {
                return author
            }
        }
        return item.author
    }

    // v7.1 新增：视频按钮是否展示（有视频 OR 有博主兜底）
    private var shouldShowVideoButton: Bool {
        !videos.isEmpty || primaryDouyinAuthor != nil
    }

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
                            MiniTag(text: "收藏", color: DS.Color.brand)
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

            // ─────────────────────────────────────────
            // v7.1 重构：操作区（导航高优 + 知乎式次级四键）
            // ─────────────────────────────────────────

            // 第一行：导航主按钮（占满宽，品牌色实心）
            Button(action: onNavigate) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("导航到店铺")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(DS.Color.brand, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .buttonStyle(PressableScaleButtonStyle())

            // 第二行：知乎式次级操作（收藏 避雷 标记删除 分享）
            HStack(spacing: DS.Spacing.sm) {
                // 收藏（红色，已收藏高亮填充）
                CardActionButton(
                    title: item.isFavorited ? "已收藏" : "收藏",
                    icon: item.isFavorited ? "heart.fill" : "heart",
                    tint: .red,
                    emphasis: .secondaryWithCount,
                    action: onFavorite,
                    count: item.favoriteCount
                )

                // 避雷（橙色，已避雷高亮填充）
                CardActionButton(
                    title: item.isAvoided ? "已避雷" : "避雷",
                    icon: item.isAvoided ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                    tint: .orange,
                    emphasis: .secondaryWithCount,
                    action: onAvoid,
                    count: item.avoidCount
                )

                // 标记删除
                CardActionButton(
                    title: isMarkedDeleted ? "取消删除" : "标记删除",
                    icon: isMarkedDeleted ? "trash.slash" : "trash",
                    tint: .gray,
                    emphasis: .secondaryWithCount,
                    action: onToggleDelete
                )

                // 分享
                CardActionButton(
                    title: "分享",
                    icon: "square.and.arrow.up",
                    tint: .gray,
                    emphasis: .secondaryWithCount,
                    action: onSharePlaceholder
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // 主推荐来源
            HStack(spacing: DS.Spacing.sm) {
                AsyncImage(url: URL(string: primarySourceAvatarURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(DS.Color.surfaceAlt)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                Text(primarySourceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Button(action: {
                    onCopyAuthor(primarySourceName)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if shouldShowVideoButton {
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

            // v6.0 新增：其他推荐来源（如果有多个来源）
            if item.recommendedBy.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("其他推荐来源")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    ForEach(item.recommendedBy.dropFirst(), id: \.self) { source in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)

                            switch source {
                            case .author(let author):
                                Text("来自 @\(author.name)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                            case .selfCreated:
                                Text("来自 \(currentUserName)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                            case .subscribedUser(_, let nickname, _):
                                Text("来自 @\(nickname)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                            }

                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(DS.Color.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
        }
    }

    private var primarySourceName: String {
        if item.isUserCreated {
            return currentUserName
        }

        if let first = item.recommendedBy.first {
            switch first {
            case .author(let author):
                return author.name
            case .selfCreated:
                return currentUserName
            case .subscribedUser(_, let nickname, _):
                return nickname
            }
        }

        return item.author?.name ?? currentUserName
    }

    private var primarySourceAvatarURL: String? {
        if item.isUserCreated {
            return currentUserAvatarURL
        }

        if let first = item.recommendedBy.first {
            switch first {
            case .author(let author):
                return author.avatar_url
            case .selfCreated:
                return currentUserAvatarURL
            case .subscribedUser(_, _, let avatarUrl):
                return avatarUrl
            }
        }

        return item.author?.avatar_url
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
    enum Emphasis {
        case primary
        case secondary
        case secondaryWithCount  // v7.1 新增：知乎式 上图标-中数字-下标题
    }

    let title: String
    let icon: String
    let tint: Color
    let emphasis: Emphasis
    let action: () -> Void

    // v7.1 新增：全平台统计数字（收藏/避雷）
    var count: Int? = nil

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    @ViewBuilder
    private var content: some View {
        if emphasis == .secondaryWithCount {
            // 知乎式竖排：图标 → 数字 → 标题
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                if let count = count, count > 0 {
                    Text(count > 999 ? "999+" : "\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("--")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(DS.Color.surfaceAlt.opacity(0.45), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(DS.Color.separator.opacity(0.2), lineWidth: 0.7)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay {
                if emphasis == .secondary {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(DS.Color.separator.opacity(0.2), lineWidth: 0.7)
                }
            }
        }
    }

    private var backgroundColor: Color {
        switch emphasis {
        case .primary:
            return tint.opacity(0.14)
        case .secondary:
            return DS.Color.surfaceAlt.opacity(0.45)
        case .secondaryWithCount:
            return DS.Color.surfaceAlt.opacity(0.45)
        }
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
