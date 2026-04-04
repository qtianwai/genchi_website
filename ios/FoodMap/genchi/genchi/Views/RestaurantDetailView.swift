// 店铺详情全屏页（v5.0 新增）
// 替代原地图底部卡片，提供店铺完整信息和所有操作入口
// 从地图标注、收藏列表、博主详情店铺列表均可进入

import SwiftUI
import MapKit

struct RestaurantDetailView: View {
    // 店铺信息
    let restaurant: Restaurant
    let restaurantId: String

    @EnvironmentObject var authState: AuthState

    // 页面状态
    @State private var isFavorited = false
    @State private var isAvoided = false
    @State private var favoriteNote = ""
    @State private var videos: [RestaurantVideo] = []
    @State private var isLoading = true
    @State private var showDeleteConfirm = false
    @State private var showGroupSheet = false
    @State private var showNoteEditor = false
    @State private var showNavSheet = false
    @State private var groups: [RestaurantGroup] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 店铺封面图（全宽，高度 220pt）
                coverImage

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // 店铺名称 + 分类标签
                    nameAndCategory

                    // 地址行
                    addressRow

                    // 操作按钮网格
                    actionGrid

                    // 收藏理由区域
                    if isFavorited {
                        noteSection
                    }

                    // 关联博主推荐
                    if !videos.isEmpty {
                        videoSection
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        // 删除二次确认
        .alert("删除店铺", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                Task { await deleteRestaurant() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后该店铺将不再显示在地图和列表中。")
        }
        // 分组选择 Sheet
        .sheet(isPresented: $showGroupSheet) {
            groupSelectionSheet
        }
        // 收藏理由编辑 Sheet
        .sheet(isPresented: $showNoteEditor) {
            noteEditorSheet
        }
        // 导航选择 Sheet
        .confirmationDialog("选择导航应用", isPresented: $showNavSheet) {
            if let coord = restaurant.coordinate {
                Button("Apple 地图") {
                    openInAppleMaps(coordinate: coord)
                }
                Button("高德地图") {
                    openInAmap(coordinate: coord)
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 封面图
    private var coverImage: some View {
        AsyncImage(url: URL(string: restaurant.photo_url ?? "")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(DS.Color.surfaceAlt)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.5))
                )
        }
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
        .clipped()
    }

    // MARK: - 名称和分类
    private var nameAndCategory: some View {
        HStack {
            Text(restaurant.name)
                .font(.title2.bold())
            Spacer()
            if let category = restaurant.category, !category.isEmpty {
                Text(category)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Color.brand.opacity(0.1))
                    .foregroundColor(DS.Color.brand)
                    .cornerRadius(DS.Radius.sm)
            }
        }
    }

    // MARK: - 地址行
    private var addressRow: some View {
        Group {
            if let address = restaurant.address, !address.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    Text(address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 操作按钮网格
    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            actionButton(icon: "location.fill", title: "导航", color: .blue) {
                showNavSheet = true
            }
            actionButton(
                icon: isFavorited ? "bookmark.fill" : "bookmark",
                title: isFavorited ? "已收藏" : "收藏",
                color: .orange
            ) {
                Task { await toggleFavorite() }
            }
            actionButton(icon: "square.and.arrow.up", title: "分享", color: .gray) {
                // 占位，后续实现
            }
            actionButton(icon: "folder.badge.plus", title: "分组", color: .purple) {
                showGroupSheet = true
            }
            actionButton(
                icon: isAvoided ? "exclamationmark.shield.fill" : "exclamationmark.shield",
                title: isAvoided ? "已避雷" : "避雷",
                color: isAvoided ? .red : .gray
            ) {
                Task { await toggleAvoid() }
            }
            actionButton(icon: "trash", title: "删除", color: .red) {
                showDeleteConfirm = true
            }
        }
    }

    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.surfaceAlt)
            .cornerRadius(DS.Radius.md)
        }
    }

    // MARK: - 收藏理由区域
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("收藏理由")
                    .font(.headline)
                Spacer()
                Button {
                    showNoteEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(DS.Color.brand)
                }
            }
            if favoriteNote.isEmpty {
                Text("点击右上角编辑，记录你喜欢这家店的理由")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text(favoriteNote)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(DS.Color.surfaceAlt)
        .cornerRadius(DS.Radius.md)
    }

    // MARK: - 关联博主推荐
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("博主推荐")
                .font(.headline)
            ForEach(videos) { video in
                HStack(spacing: DS.Spacing.md) {
                    // 博主头像
                    AsyncImage(url: URL(string: video.author_avatar_url ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(DS.Color.surfaceAlt)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.author_name)
                            .font(.subheadline.bold())
                        Text(video.created_at.prefix(10))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 打开抖音视频
                    if let url = video.douyinURL {
                        Link(destination: url) {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(DS.Color.brand)
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.xs)
            }
        }
    }

    // MARK: - 分组选择 Sheet
    private var groupSelectionSheet: some View {
        NavigationStack {
            List {
                if groups.isEmpty {
                    Text("暂无自定义分组")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(groups) { group in
                        Button {
                            Task {
                                try? await APIService.shared.addToGroup(
                                    userId: authState.userId,
                                    groupId: group.id,
                                    restaurantId: restaurantId
                                )
                                showGroupSheet = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.purple)
                                Text(group.name)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("添加到分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showGroupSheet = false }
                }
            }
            .task {
                groups = (try? await APIService.shared.getGroups(userId: authState.userId)) ?? []
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 收藏理由编辑 Sheet
    private var noteEditorSheet: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.lg) {
                Text("记录你喜欢这家店的理由")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $favoriteNote)
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
                            try? await APIService.shared.updateFavoriteNote(
                                userId: authState.userId,
                                restaurantId: restaurantId,
                                note: favoriteNote
                            )
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
        // 并行加载视频和收藏状态
        async let videosTask: () = loadVideos()
        async let favTask: () = checkFavoriteStatus()
        async let avoidTask: () = checkAvoidStatus()
        _ = await (videosTask, favTask, avoidTask)
        isLoading = false
    }

    private func loadVideos() async {
        do {
            videos = try await APIService.shared.getRestaurantVideos(restaurantId: restaurantId)
        } catch {
            print("[店铺详情] 加载视频失败: \(error)")
        }
    }

    private func checkFavoriteStatus() async {
        do {
            let favorites = try await APIService.shared.getFavorites(userId: authState.userId)
            if let fav = favorites.first(where: { $0.restaurant_id == restaurantId }) {
                isFavorited = true
                favoriteNote = fav.note ?? ""
            }
        } catch {
            print("[店铺详情] 检查收藏状态失败: \(error)")
        }
    }

    private func checkAvoidStatus() async {
        do {
            let avoided = try await APIService.shared.getAvoidedRestaurants(userId: authState.userId)
            isAvoided = avoided.contains { $0.restaurant_id == restaurantId }
        } catch {
            print("[店铺详情] 检查避雷状态失败: \(error)")
        }
    }

    // MARK: - 操作
    private func toggleFavorite() async {
        do {
            if isFavorited {
                try await APIService.shared.removeFavorite(userId: authState.userId, restaurantId: restaurantId)
                isFavorited = false
                favoriteNote = ""
            } else {
                try await APIService.shared.addFavorite(userId: authState.userId, restaurantId: restaurantId)
                isFavorited = true
            }
        } catch {
            print("[店铺详情] 收藏操作失败: \(error)")
        }
    }

    private func toggleAvoid() async {
        do {
            if isAvoided {
                try await APIService.shared.unavoidRestaurant(userId: authState.userId, restaurantId: restaurantId)
                isAvoided = false
            } else {
                try await APIService.shared.avoidRestaurant(userId: authState.userId, restaurantId: restaurantId)
                isAvoided = true
            }
        } catch {
            print("[店铺详情] 避雷操作失败: \(error)")
        }
    }

    private func deleteRestaurant() async {
        do {
            try await APIService.shared.deleteRestaurantForUser(userId: authState.userId, restaurantId: restaurantId)
            dismiss()
        } catch {
            print("[店铺详情] 删除失败: \(error)")
        }
    }

    // MARK: - 导航
    private func openInAppleMaps(coordinate: CLLocationCoordinate2D) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = restaurant.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openInAmap(coordinate: CLLocationCoordinate2D) {
        let urlStr = "iosamap://path?sourceApplication=genchi&dname=\(restaurant.name)&dlat=\(coordinate.latitude)&dlon=\(coordinate.longitude)&dev=0&t=0"
        if let encoded = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // 高德地图未安装，用 Apple 地图兜底
            openInAppleMaps(coordinate: coordinate)
        }
    }
}
