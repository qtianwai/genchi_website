// 地图主页面
// v6.0：地图全屏重构、单一添加入口、多维筛选、搜索定位、聚合、防重叠、卡片快捷操作、剪贴板识别

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

    @AppStorage("map_last_handled_clipboard_link") private var lastHandledClipboardLink = ""
    @AppStorage("map_last_clipboard_prompt_at") private var lastClipboardPromptAt = 0.0

    var body: some View {
        ZStack {
            mapLayer
            if showFilterPanel {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            showFilterPanel = false
                        }
                    }
                    .transition(.opacity)
            }
            topOverlay
            bottomCard
        }
        .ignoresSafeArea()
        .task {
            await reloadAllData()
            locationManager.requestPermission()
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
            UserAnnotation()

            ForEach(viewModel.clusteredItems(userLocation: locationManager.userLocation)) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    if cluster.isCluster {
                        ClusterPinView(count: cluster.count)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.zoomIn(on: cluster)
                                }
                            }
                    } else if let item = cluster.primary {
                        RestaurantPinView(
                            avatarURL: item.author?.avatar_url ?? authState.avatarURL,
                            isSelected: selectedItem?.id == item.id,
                            isFavorited: item.isFavorited,
                            isAvoided: item.isAvoided,
                            isUserCreated: item.isUserCreated,
                            isHighlighted: viewModel.highlightedItemId == item.id
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
        .onMapCameraChange(frequency: .continuous) { context in
            viewModel.updateVisibleRegion(context.region)
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedItem = nil
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

                if !viewModel.searchResults().isEmpty && !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchResultsView(results: viewModel.searchResults()) { item in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedItem = item
                            viewModel.focus(on: item)
                        }
                    }
                    .transition(.opacity)
                }

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, proxy.safeAreaInsets.top + DS.Spacing.sm)
            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: showFilterPanel)
        }
    }

    private var bottomCard: some View {
        VStack {
            Spacer()
            if let item = selectedItem {
                MapQuickActionCard(
                    item: item,
                    onFavorite: { toggleFavorite(item) },
                    onAvoid: { toggleAvoid(item) },
                    onDelete: { deleteItem(item) },
                    onNavigate: { showNavSheet = true }
                )
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, 94)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selectedItem?.id)
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
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(DS.Color.separator.opacity(0.2), lineWidth: 0.6)
            }
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    private var filterTitle: String {
        viewModel.hasActiveFilters ? "已筛选(\(viewModel.activeFilterCount))" : "全部"
    }

    private var addButton: some View {
        Button {
            showAddMenu = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(DS.Color.brand)
                .clipShape(Circle())
                .shadow(color: DS.Shadow.cardColor, radius: 6, y: 2)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }

    private var locateButton: some View {
        Button {
            if let location = locationManager.userLocation {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.centerMapOnUserLocation(location)
                }
            } else {
                locationManager.requestPermission()
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Color.brand)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
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
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func reloadAllData() async {
        await viewModel.loadMapData(userId: authState.userId)
        await viewModel.loadUserGroups(userId: authState.userId)
        syncSelectionWithLatestData()
    }

    private func syncSelectionWithLatestData() {
        guard let selected = selectedItem else { return }
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

    private func toggleFavorite(_ item: MapDisplayItem) {
        Task {
            do {
                if item.isFavorited {
                    try await APIService.shared.removeFavorite(userId: authState.userId, restaurantId: item.restaurantId)
                } else {
                    try await APIService.shared.addFavorite(userId: authState.userId, restaurantId: item.restaurantId)
                }
                await reloadAllData()
            } catch {
                print("[地图] 收藏操作失败: \(error)")
            }
        }
    }

    private func toggleAvoid(_ item: MapDisplayItem) {
        Task {
            do {
                if item.isAvoided {
                    try await APIService.shared.unavoidRestaurant(userId: authState.userId, restaurantId: item.restaurantId)
                } else {
                    try await APIService.shared.avoidRestaurant(userId: authState.userId, restaurantId: item.restaurantId)
                }
                await reloadAllData()
            } catch {
                print("[地图] 避雷操作失败: \(error)")
            }
        }
    }

    private func deleteItem(_ item: MapDisplayItem) {
        Task {
            do {
                try await APIService.shared.deleteRestaurantForUser(userId: authState.userId, restaurantId: item.restaurantId)
                selectedItem = nil
                await reloadAllData()
            } catch {
                print("[地图] 删除店铺失败: \(error)")
            }
        }
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

// MARK: - Pins
struct RestaurantPinView: View {
    let avatarURL: String?
    let isSelected: Bool
    let isFavorited: Bool
    let isAvoided: Bool
    let isUserCreated: Bool
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(pinBackground)
                    .frame(width: isSelected ? 46 : 38, height: isSelected ? 46 : 38)
                    .shadow(color: .black.opacity(0.2), radius: isSelected ? 7 : 3, y: 2)

                AsyncImage(url: URL(string: avatarURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: isUserCreated ? "person.crop.circle.fill.badge.plus" : "person.fill")
                        .foregroundColor(.gray)
                }
                .frame(width: isSelected ? 38 : 30, height: isSelected ? 38 : 30)
                .clipShape(Circle())

                HStack(spacing: 4) {
                    if isFavorited {
                        StatusBadge(icon: "heart.fill", color: .red)
                    }
                    if isAvoided {
                        StatusBadge(icon: "exclamationmark.triangle.fill", color: .orange)
                    }
                }
                .offset(x: 6, y: -8)
            }
            Triangle()
                .fill(pinBackground)
                .frame(width: 10, height: 6)
        }
        .overlay {
            if isHighlighted {
                Circle()
                    .stroke(DS.Color.brand, lineWidth: 2)
                    .frame(width: isSelected ? 54 : 46, height: isSelected ? 54 : 46)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSelected)
    }

    private var pinBackground: Color {
        if isAvoided { return Color.orange.opacity(0.95) }
        if isFavorited { return Color.red.opacity(0.9) }
        if isUserCreated { return Color.purple.opacity(0.85) }
        return isSelected ? DS.Color.brand : DS.Color.surface
    }
}

struct ClusterPinView: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.Color.brand)
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct StatusBadge: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 15, height: 15)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
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

// MARK: - Search Result
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
                        Image(systemName: item.isUserCreated ? "person.crop.circle.badge.plus" : "mappin.circle.fill")
                            .foregroundColor(item.isUserCreated ? .purple : DS.Color.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.restaurant.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(item.author?.name ?? "我的推荐")
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
}

// MARK: - Bottom Card
struct MapQuickActionCard: View {
    let item: MapDisplayItem
    let onFavorite: () -> Void
    let onAvoid: () -> Void
    let onDelete: () -> Void
    let onNavigate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                AsyncImage(url: URL(string: item.restaurant.photo_url ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.surfaceAlt)
                        .overlay(Image(systemName: "fork.knife").foregroundColor(.gray))
                }
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(item.restaurant.name)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: DS.Spacing.xs) {
                        if item.isUserCreated {
                            MiniTag(text: "我的推荐", color: .purple)
                        }
                        if item.isFavorited {
                            MiniTag(text: "已收藏", color: .red)
                        }
                        if item.isAvoided {
                            MiniTag(text: "已避雷", color: .orange)
                        }
                        if let category = item.restaurant.category, !category.isEmpty {
                            MiniTag(text: category, color: DS.Color.brand)
                        }
                    }
                    if let address = item.restaurant.address, !address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let author = item.author {
                        Text("\(author.name) 推荐")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: DS.Spacing.sm
            ) {
                ActionBtn(
                    title: item.isFavorited ? "取消收藏" : "收藏",
                    icon: item.isFavorited ? "heart.slash" : "heart.fill",
                    tint: .red,
                    action: onFavorite
                )
                ActionBtn(
                    title: item.isAvoided ? "取消避雷" : "避雷",
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    action: onAvoid
                )
                ActionBtn(
                    title: "删除",
                    icon: "trash",
                    tint: .gray,
                    action: onDelete
                )
                ActionBtn(
                    title: "导航",
                    icon: "arrow.triangle.turn.up.right.diamond.fill",
                    tint: .blue,
                    action: onNavigate
                )
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .shadow(color: DS.Shadow.cardColor, radius: DS.Shadow.cardRadius, y: DS.Shadow.cardY)
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

struct ActionBtn: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tint.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(PressableScaleButtonStyle())
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
