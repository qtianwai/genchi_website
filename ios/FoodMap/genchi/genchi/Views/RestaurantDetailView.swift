import SwiftUI
import MapKit
import UIKit

struct RestaurantDetailView: View {
    let restaurant: Restaurant
    let restaurantId: String

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var isFavorited = false
    @State private var isAvoided = false
    @State private var favoriteNote = ""
    @State private var videos: [RestaurantVideo] = []
    @State private var groups: [RestaurantGroup] = []
    @State private var selectedGroupIds: Set<String> = []

    @State private var isLoading = true
    @State private var isLoadingGroups = false
    @State private var showDeleteConfirm = false
    @State private var showGroupSheet = false
    @State private var showNoteEditor = false
    @State private var showNavSheet = false

    private var trimmedFavoriteNote: String {
        favoriteNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            FavoritesTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    coverImage

                    VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                        summaryCard

                        if isFavorited {
                            noteSection
                        }

                        if !videos.isEmpty {
                            videosSection
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)
                }
            }
            .opacity(isLoading ? 0.35 : 1)

            if isLoading {
                ProgressView()
                    .tint(FavoritesTheme.accent)
                    .scaleEffect(1.15)
            }
        }
        .navigationTitle("店铺详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .alert("删除店铺", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                Task { await deleteRestaurant() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后该店铺将不再显示在地图和列表中。")
        }
        .sheet(isPresented: $showGroupSheet) {
            groupSelectionSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNoteEditor) {
            DetailNoteEditorSheet(
                restaurantName: restaurant.name,
                text: $favoriteNote,
                onCancel: { showNoteEditor = false },
                onSave: {
                    Task { await saveFavoriteNote() }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("选择导航应用", isPresented: $showNavSheet, titleVisibility: .visible) {
            if let coordinate = restaurant.coordinate {
                Button("Apple 地图") {
                    openInAppleMaps(coordinate: coordinate)
                }
                Button("高德地图") {
                    openInAmap(coordinate: coordinate)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .restaurantStateDidChange)) { notification in
            handleRestaurantStateChange(notification)
        }
        .favoritesMinimalBackButton()
        .favoritesPageChrome()
    }

    private var coverImage: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: restaurant.photo_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(FavoritesTheme.surfaceElevated)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(FavoritesTheme.secondary)
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 260)
            .clipped()

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 130)

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var summaryCard: some View {
        FavoritesCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(restaurant.name)
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(FavoritesTheme.title)

                        if let address = restaurant.address, !address.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(FavoritesTheme.secondary)
                                    .padding(.top, 2)
                                Text(address)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(FavoritesTheme.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    Spacer(minLength: DS.Spacing.sm)

                    if let category = restaurant.category, !category.isEmpty {
                        FavoritesPill(text: category, color: FavoritesTheme.accent)
                    }
                    if let avgPrice = restaurant.avg_price, avgPrice > 0 {
                        FavoritesPill(text: "人均¥\(avgPrice)", color: .secondary)
                    }
                }

                HStack(spacing: 6) {
                    if isFavorited {
                        MiniTag(text: "已收藏", color: .red)
                    }
                    if isAvoided {
                        MiniTag(text: "已避雷", color: .orange)
                    }
                    if !isFavorited && !isAvoided {
                        MiniTag(text: "可加入收藏", color: DS.Color.brand)
                    }
                }

                summaryNotePreview

                VStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        CardActionButton(
                            title: "导航",
                            icon: "arrow.triangle.turn.up.right.diamond.fill",
                            tint: .blue,
                            emphasis: .primary,
                            action: { showNavSheet = true }
                        )
                        if let tel = restaurant.tel, !tel.isEmpty {
                            CardActionButton(
                                title: "电话",
                                icon: "phone.fill",
                                tint: .green,
                                emphasis: .primary,
                                action: { callPhone(tel) }
                            )
                        }
                        CardActionButton(
                            title: isFavorited ? "取消收藏" : "收藏",
                            icon: isFavorited ? "heart.slash" : "heart.fill",
                            tint: .red,
                            emphasis: .primary,
                            action: { Task { await toggleFavorite() } }
                        )
                        CardActionButton(
                            title: isAvoided ? "取消避雷" : "避雷",
                            icon: "exclamationmark.triangle.fill",
                            tint: .orange,
                            emphasis: .primary,
                            action: { Task { await toggleAvoid() } }
                        )
                    }

                    HStack(spacing: DS.Spacing.sm) {
                        CardActionButton(
                            title: "分享",
                            icon: "square.and.arrow.up",
                            tint: .gray,
                            emphasis: .secondary,
                            action: shareRestaurant
                        )
                        CardActionButton(
                            title: "分组",
                            icon: "folder.badge.plus",
                            tint: FavoritesTheme.purple,
                            emphasis: .secondary,
                            action: { showGroupSheet = true }
                        )
                        CardActionButton(
                            title: "删除",
                            icon: "trash",
                            tint: .gray,
                            emphasis: .secondary,
                            action: { showDeleteConfirm = true }
                        )
                    }
                }
            }
            .padding(DS.Spacing.lg)
        }
        .offset(y: -34)
        .padding(.bottom, -34)
    }

    private var summaryNotePreview: some View {
        Group {
            if isFavorited && !trimmedFavoriteNote.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FavoritesTheme.accent)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("收藏理由")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FavoritesTheme.secondary)
                        Text(trimmedFavoriteNote)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FavoritesTheme.body)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        showNoteEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FavoritesTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(FavoritesTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FavoritesTheme.secondary)
                        .padding(.top, 2)
                    Text("将收藏、避雷、分组和探店信息放在同一张卡片里管理。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FavoritesTheme.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(FavoritesTheme.surfaceElevated.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var noteSection: some View {
        FavoritesCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Text("收藏理由")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FavoritesTheme.title)

                    Spacer()

                    Button {
                        showNoteEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FavoritesTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if favoriteNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("记录你喜欢这家店的理由，下次再来会更快想起它。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FavoritesTheme.secondary)
                } else {
                    Text(favoriteNote)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(FavoritesTheme.body)
                        .lineSpacing(4)
                }
            }
            .padding(DS.Spacing.lg)
        }
    }

    private var videosSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("博主推荐")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(FavoritesTheme.title)

            FavoritesCard {
                VStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        HStack(spacing: DS.Spacing.md) {
                            AsyncImage(url: URL(string: video.author_avatar_url ?? "")) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(FavoritesTheme.surfaceElevated)
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(video.author_name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(FavoritesTheme.body)
                                Text(String(video.created_at.prefix(10)))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(FavoritesTheme.secondary)
                            }

                            Spacer()

                            if let url = video.douyinURL {
                                Link(destination: url) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(FavoritesTheme.accent)
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, 14)

                        if index != videos.count - 1 {
                            Divider()
                                .overlay(FavoritesTheme.separator)
                                .padding(.leading, 72)
                        }
                    }
                }
            }
        }
    }

    private var groupSelectionSheet: some View {
        NavigationStack {
            List {
                FavoritesSectionHeader("选择分组", trailing: isLoadingGroups ? "加载中" : "\(groups.count) 个")

                if isLoadingGroups {
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
                } else if groups.isEmpty {
                    FavoritesEmptyStateCard(
                        icon: "folder.badge.plus",
                        title: "还没有自定义分组",
                        subtitle: "先去店铺列表里新建分组，再把这家店加入进去。"
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, 12)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(groups) { group in
                        groupRow(group)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("添加到分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showGroupSheet = false }
                }
            }
            .task {
                await loadGroupsAndMembership()
            }
            .favoritesPageChrome()
        }
    }

    private func groupRow(_ group: RestaurantGroup) -> some View {
        let isSelected = selectedGroupIds.contains(group.id)

        return FavoritesCard {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FavoritesTheme.purple)

                Text(group.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FavoritesTheme.body)

                Spacer()

                if isSelected {
                    Text("已添加")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FavoritesTheme.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(FavoritesTheme.purple.opacity(0.16), in: Capsule())

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FavoritesTheme.purple)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FavoritesTheme.accent)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .opacity(isSelected ? 0.76 : 1)
            .onTapGesture {
                guard !isSelected else { return }
                Task { await addToGroup(group) }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, 12)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func loadData() async {
        isLoading = true
        async let videosTask: Void = loadVideos()
        async let favoriteTask: Void = checkFavoriteStatus()
        async let avoidTask: Void = checkAvoidStatus()
        _ = await (videosTask, favoriteTask, avoidTask)
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
            if let favorite = favorites.first(where: { $0.restaurant_id == restaurantId }) {
                isFavorited = true
                favoriteNote = favorite.note ?? ""
            } else {
                isFavorited = false
                favoriteNote = ""
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

    private func loadGroupsAndMembership() async {
        isLoadingGroups = true
        defer { isLoadingGroups = false }

        do {
            let loadedGroups = try await APIService.shared.getGroups(userId: authState.userId)
            groups = loadedGroups

            var groupIds = Set<String>()
            for group in loadedGroups {
                let restaurants = try? await APIService.shared.getGroupRestaurants(
                    groupId: group.id,
                    userId: authState.userId
                )
                if restaurants?.contains(where: { $0.restaurant_id == restaurantId }) == true {
                    groupIds.insert(group.id)
                }
            }
            selectedGroupIds = groupIds
        } catch {
            print("[店铺详情] 加载分组失败: \(error)")
        }
    }

    private func addToGroup(_ group: RestaurantGroup) async {
        do {
            try await APIService.shared.addToGroup(
                userId: authState.userId,
                groupId: group.id,
                restaurantId: restaurantId
            )
            selectedGroupIds.insert(group.id)
        } catch {
            print("[店铺详情] 添加到分组失败: \(error)")
        }
    }

    private func saveFavoriteNote() async {
        let trimmedNote = favoriteNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await APIService.shared.updateFavoriteNote(
                userId: authState.userId,
                restaurantId: restaurantId,
                note: trimmedNote
            )
            favoriteNote = trimmedNote
            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: isFavorited,
                isAvoided: isAvoided,
                favoriteNote: trimmedNote,
                isDeleted: false
            ).post()
            showNoteEditor = false
        } catch {
            print("[店铺详情] 更新收藏理由失败: \(error)")
        }
    }

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

            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: isFavorited,
                isAvoided: isAvoided,
                favoriteNote: favoriteNote,
                isDeleted: false
            ).post()
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

            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: isFavorited,
                isAvoided: isAvoided,
                favoriteNote: favoriteNote,
                isDeleted: false
            ).post()
        } catch {
            print("[店铺详情] 避雷操作失败: \(error)")
        }
    }

    private func shareRestaurant() {
        let address = restaurant.address ?? ""
        let shareText = address.isEmpty ? restaurant.name : "\(restaurant.name)\n\(address)"
        let controller = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
            rootViewController.present(controller, animated: true)
        }
    }

    private func deleteRestaurant() async {
        do {
            try await APIService.shared.deleteRestaurantForUser(userId: authState.userId, restaurantId: restaurantId)
            RestaurantStateChange(
                restaurantId: restaurantId,
                isFavorited: false,
                isAvoided: false,
                favoriteNote: nil,
                isDeleted: true
            ).post()
            dismiss()
        } catch {
            print("[店铺详情] 删除失败: \(error)")
        }
    }

    private func handleRestaurantStateChange(_ notification: Notification) {
        guard let change = RestaurantStateChange(notification), change.restaurantId == restaurantId else { return }

        if change.isDeleted {
            dismiss()
            return
        }

        if let isFavorited = change.isFavorited {
            self.isFavorited = isFavorited
        }

        if let isAvoided = change.isAvoided {
            self.isAvoided = isAvoided
        }

        if let favoriteNote = change.favoriteNote {
            self.favoriteNote = favoriteNote
        }
    }

    private func openInAppleMaps(coordinate: CLLocationCoordinate2D) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = restaurant.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openInAmap(coordinate: CLLocationCoordinate2D) {
        let urlString = "iosamap://path?sourceApplication=genchi&dname=\(restaurant.name)&dlat=\(coordinate.latitude)&dlon=\(coordinate.longitude)&dev=0&t=0"
        if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            openInAppleMaps(coordinate: coordinate)
        }
    }

    /// 拨打商家电话（高德 tel 可能含多个号码用 ";" 分隔，取第一个）
    private func callPhone(_ tel: String) {
        let firstNumber = tel.components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? tel
        let cleaned = firstNumber.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "tel:\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }
}

private struct DetailNoteEditorSheet: View {
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
