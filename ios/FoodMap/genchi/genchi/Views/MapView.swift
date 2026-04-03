// 地图主页面
// 显示博主推荐店铺的地图，支持按博主筛选，点击标注查看详情

import SwiftUI
import MapKit

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var authState: AuthState

    // 外部触发刷新（MainTabView 添加成功后通知）
    @Binding var refreshTrigger: Int
    // 当前选中的博主推荐店铺
    @State private var selectedRestaurant: MapRestaurant? = nil
    // 当前选中的用户自建推荐店铺（v4.0 新增）
    @State private var selectedUserRestaurant: UserCreatedRestaurant? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── 地图主体（iOS 17+ 新 API）──
            Map(position: $viewModel.mapCameraPosition) {
                // 用户位置蓝点
                UserAnnotation()
                // 博主推荐店铺标注
                ForEach(viewModel.filteredRestaurants) { item in
                    Annotation("", coordinate: item.restaurants?.coordinate ?? CLLocationCoordinate2D()) {
                        MapPinView(
                            avatarURL: item.authors?.avatar_url,
                            isSelected: selectedRestaurant?.id == item.id
                        )
                        .onTapGesture {
                            withAnimation(.spring()) {
                                selectedRestaurant = item
                                selectedUserRestaurant = nil
                            }
                        }
                    }
                }
                // 用户自建推荐店铺标注（v4.0 新增）
                ForEach(viewModel.filteredUserRestaurants) { item in
                    Annotation("", coordinate: item.restaurants?.coordinate ?? CLLocationCoordinate2D()) {
                        UserPinView(
                            isSelected: selectedUserRestaurant?.id == item.id,
                            avatarURL: authState.avatarURL
                        )
                        .onTapGesture {
                            withAnimation(.spring()) {
                                selectedUserRestaurant = item
                                selectedRestaurant = nil
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── 顶部博主筛选栏 ──
                AuthorFilterBar(
                    restaurants: viewModel.mapRestaurants,
                    userRestaurantCount: viewModel.userRestaurants.count,
                    selectedAuthorId: $viewModel.selectedAuthorId
                )
                .padding(.top, 8)

                Spacer()

                // ── 底部店铺详情卡片（点击博主推荐标注后显示）──
                if let selected = selectedRestaurant,
                   let restaurant = selected.restaurants {
                    RestaurantCard(
                        restaurant: restaurant,
                        author: selected.authors,
                        userId: authState.userId
                    )
                    .id(restaurant.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                }

                // ── 底部店铺详情卡片（点击用户自建标注后显示）──
                if let selected = selectedUserRestaurant,
                   let restaurant = selected.restaurants {
                    RestaurantCard(
                        restaurant: restaurant,
                        author: nil,
                        userId: authState.userId,
                        isUserCreated: true
                    )
                    .id(restaurant.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                }
            }

        }
        .task {
            await viewModel.loadMapData(userId: authState.userId)
            locationManager.requestPermission()
        }
        .onAppear {
            viewModel.startAutoRefresh(userId: authState.userId)
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        // 点击地图空白处关闭详情卡片
        .onTapGesture {
            withAnimation {
                selectedRestaurant = nil
                selectedUserRestaurant = nil
            }
        }
        .onChange(of: locationManager.locationUpdateCount) { oldValue, newValue in
            if let location = locationManager.userLocation, viewModel.isFirstLocationUpdate {
                viewModel.centerMapOnUserLocation(location)
            }
        }
        // 监听外部刷新触发器（MainTabView 添加成功后通知）
        .onChange(of: refreshTrigger) { _, _ in
            Task { await viewModel.loadMapData(userId: authState.userId) }
        }
    }
}

// ─────────────────────────────────────────
// 用户自建推荐标注视图（v4.0 新增）
// 有头像时显示用户头像（与博主标注风格一致），无头像时显示紫色 person 图标
// ─────────────────────────────────────────
struct UserPinView: View {
    let isSelected: Bool
    let avatarURL: String?  // 用户头像 URL，nil 时显示紫色占位图标
    private let pinColor = Color.purple

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? pinColor : DS.Color.surface)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(radius: isSelected ? DS.Shadow.pinSelectedRadius : DS.Shadow.pinNormalRadius)

                if let urlStr = avatarURL, let url = URL(string: urlStr) {
                    // 有头像：与 MapPinView 风格一致
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill").foregroundColor(.gray)
                    }
                    .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                    .clipShape(Circle())
                } else {
                    // 无头像：保持原有紫色 person 图标
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundColor(isSelected ? .white : pinColor)
                        .font(.system(size: isSelected ? 20 : 16))
                }
            }
            Triangle()
                .fill(isSelected ? pinColor : DS.Color.surface)
                .frame(width: 10, height: 6)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// ─────────────────────────────────────────
// 地图标注视图：博主头像圆形图标
// ─────────────────────────────────────────
struct MapPinView: View {
    let avatarURL: String?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? DS.Color.brand : DS.Color.surface)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(radius: isSelected ? DS.Shadow.pinSelectedRadius : DS.Shadow.pinNormalRadius)

                // 博主头像（异步加载）
                AsyncImage(url: URL(string: avatarURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.fill")
                        .foregroundColor(.gray)
                }
                .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                .clipShape(Circle())
            }
            // 小三角形指针
            Triangle()
                .fill(isSelected ? DS.Color.brand : DS.Color.surface)
                .frame(width: 10, height: 6)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// 三角形 Shape（地图标注的指针）
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

// ─────────────────────────────────────────
// 博主筛选栏：横向滚动的博主头像列表
// ─────────────────────────────────────────
struct AuthorFilterBar: View {
    let restaurants: [MapRestaurant]
    let userRestaurantCount: Int   // 用户自建推荐数量（v4.0 新增）
    @Binding var selectedAuthorId: String?

    // 从店铺列表中提取不重复的博主
    var authors: [Author] {
        var seen = Set<String>()
        return restaurants.compactMap { $0.authors }.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.md) {
                // "全部" 按钮
                FilterChip(
                    label: "全部",
                    avatarURL: nil,
                    isSelected: selectedAuthorId == nil
                ) {
                    selectedAuthorId = nil
                }

                // "我的推荐" 筛选 chip（有自建推荐时显示）
                if userRestaurantCount > 0 {
                    FilterChip(
                        label: "我的推荐",
                        avatarURL: nil,
                        isSelected: selectedAuthorId == "my",
                        accentColor: .purple
                    ) {
                        selectedAuthorId = selectedAuthorId == "my" ? nil : "my"
                    }
                }

                // 每个博主的筛选按钮
                ForEach(authors) { author in
                    FilterChip(
                        label: author.name,
                        avatarURL: author.avatar_url,
                        isSelected: selectedAuthorId == author.id
                    ) {
                        selectedAuthorId = selectedAuthorId == author.id ? nil : author.id
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Color.separator.opacity(0.25))
                .frame(height: 0.5)
        }
    }
}

struct FilterChip: View {
    let label: String
    let avatarURL: String?
    let isSelected: Bool
    var accentColor: Color = DS.Color.brand  // 默认橙色，我的推荐用紫色
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                if let url = avatarURL, !url.isEmpty {
                    AsyncImage(url: URL(string: url)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                } else if label == "我的推荐" {
                    // 我的推荐用 person 图标
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : accentColor)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(isSelected ? accentColor : DS.Color.surface)
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: DS.Shadow.chipColor, radius: DS.Shadow.chipRadius, y: DS.Shadow.chipY)
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: isSelected)
        }
    }
}

// ─────────────────────────────────────────
// 店铺详情卡片（地图底部弹出）
// ─────────────────────────────────────────
struct RestaurantCard: View {
    let restaurant: Restaurant
    let author: Author?
    let userId: String
    var isUserCreated: Bool = false  // 是否为用户自建推荐（v4.0 新增）

    @State private var isFavorited = false
    @State private var videos: [RestaurantVideo] = []
    @State private var isLoadingVideos = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    // 店铺名 + 标签行
                    HStack(spacing: DS.Spacing.sm) {
                        Text(restaurant.name)
                            .font(.headline)
                        // 用户自建推荐标识（v4.0）
                        if isUserCreated {
                            HStack(spacing: 2) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("我的推荐")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .cornerRadius(4)
                        }
                        // 已验证角标（v3.0）
                        if restaurant.verified == true {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("已验证")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(DS.Color.success)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.Color.success.opacity(0.12))
                            .cornerRadius(4)
                        }
                    }
                    if let category = restaurant.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(isUserCreated ? .purple : DS.Color.brand)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background((isUserCreated ? Color.purple : DS.Color.brand).opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                // 收藏按钮
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .foregroundColor(isFavorited ? .red : .gray)
                        .font(.title3)
                }
            }

            if let address = restaurant.address {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            // 博主推荐信息（非用户自建时显示）
            if let author = author {
                HStack(spacing: DS.Spacing.sm) {
                    AsyncImage(url: URL(string: author.avatar_url ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    Text("\(author.name) 推荐")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 关联视频列表
            if !videos.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("相关视频")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(videos) { video in
                                VideoThumbnail(video: video)
                            }
                        }
                    }
                }
            }

            // 导航按钮组
            if let coordinate = restaurant.coordinate {
                NavigationButtons(
                    name: restaurant.name,
                    coordinate: coordinate
                )
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .shadow(color: DS.Shadow.cardColor, radius: DS.Shadow.cardRadius, y: DS.Shadow.cardY)
        // 关键修复：用 restaurant.id 作为 task 的 id，店铺切换时自动取消旧任务并重新执行
        .task(id: restaurant.id) {
            videos = []  // 先清空旧数据，避免状态复用
            await loadVideos()
        }
    }

    func toggleFavorite() {
        isFavorited.toggle()
        Task {
            do {
                if isFavorited {
                    try await APIService.shared.addFavorite(userId: userId, restaurantId: restaurant.id)
                } else {
                    try await APIService.shared.removeFavorite(userId: userId, restaurantId: restaurant.id)
                }
            } catch {
                // 失败时回滚状态
                isFavorited.toggle()
            }
        }
    }

    func loadVideos() async {
        isLoadingVideos = true
        do {
            videos = try await APIService.shared.getRestaurantVideos(restaurantId: restaurant.id)
        } catch {
            print("加载视频失败：\(error)")
        }
        isLoadingVideos = false
    }
}

// ─────────────────────────────────────────
// 视频缩略图卡片
// ─────────────────────────────────────────
struct VideoThumbnail: View {
    let video: RestaurantVideo

    var body: some View {
        Button(action: openVideo) {
            HStack(spacing: DS.Spacing.sm) {
                AsyncImage(url: URL(string: video.author_avatar_url ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(video.author_name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.caption2)
                        Text("查看视频")
                            .font(.caption2)
                    }
                    .foregroundColor(DS.Color.brand)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
    }

    func openVideo() {
        // 优先尝试抖音 URL Scheme（snssdk1128://），确保在抖音 App 内打开
        let douyinSchemeURL = URL(string: "snssdk1128://aweme/detail/\(video.video_id)")!
        if UIApplication.shared.canOpenURL(douyinSchemeURL) {
            UIApplication.shared.open(douyinSchemeURL)
        } else if let fallbackURL = video.douyinURL {
            // 抖音未安装时，降级用浏览器打开分享链接
            UIApplication.shared.open(fallbackURL)
        }
    }
}

// ─────────────────────────────────────────
// 导航按钮：支持苹果地图、高德、百度
// ─────────────────────────────────────────
struct NavigationButtons: View {
    let name: String
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            NavButton(title: "苹果地图", icon: "map.fill", color: .blue) {
                openAppleMaps()
            }
            NavButton(title: "高德地图", icon: "location.fill", color: .orange) {
                openAmap()
            }
            NavButton(title: "百度地图", icon: "location.north.fill", color: .red) {
                openBaiduMap()
            }
        }
    }

    func openAppleMaps() {
        // 使用 UTF-8 编码店铺名称
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlString = "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&q=\(encodedName)&dirflg=d"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    func openAmap() {
        // 高德地图 URL Scheme - 使用 UTF-8 编码
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlString = "iosamap://navi?sourceApplication=FoodMap&backScheme=foodmap&lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&dev=0&style=2&poiname=\(encodedName)"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // 未安装高德，跳转 App Store
            if let appStoreURL = URL(string: "https://apps.apple.com/cn/app/id461703208") {
                UIApplication.shared.open(appStoreURL)
            }
        }
    }

    func openBaiduMap() {
        // 百度地图 URL Scheme - 使用完整的百分号编码
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        let urlString = "baidumap://map/direction?destination=latlng:\(coordinate.latitude),\(coordinate.longitude)|name:\(encodedName)&mode=driving&coord_type=gcj02"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            if let appStoreURL = URL(string: "https://apps.apple.com/cn/app/id452186370") {
                UIApplication.shared.open(appStoreURL)
            }
        }
    }
}


struct NavButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption).fontWeight(.medium)
            }
            .foregroundColor(color)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
    }
}
