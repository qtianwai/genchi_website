// 地图主页面
// 显示博主推荐店铺的地图，支持按博主筛选，点击标注查看详情

import SwiftUI
import MapKit

struct MapView: View {
    @StateObject private var viewModel = MapViewModel()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var authState: AuthState

    // 当前选中的店铺（用于显示底部详情卡片）
    @State private var selectedRestaurant: MapRestaurant? = nil
    // 是否显示解析链接的弹窗
    @State private var showParseSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── 地图主体 ──
            Map(coordinateRegion: $viewModel.region,
                showsUserLocation: true,
                annotationItems: viewModel.filteredRestaurants) { item in
                MapAnnotation(coordinate: item.restaurants?.coordinate ?? CLLocationCoordinate2D()) {
                    // 自定义地图标注：博主头像 + 店铺名
                    MapPinView(
                        avatarURL: item.authors?.avatar_url,
                        isSelected: selectedRestaurant?.id == item.id
                    )
                    .onTapGesture {
                        withAnimation(.spring()) {
                            selectedRestaurant = item
                        }
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── 顶部博主筛选栏 ──
                AuthorFilterBar(
                    restaurants: viewModel.mapRestaurants,
                    selectedAuthorId: $viewModel.selectedAuthorId
                )
                .padding(.top, 8)

                Spacer()

                // ── 底部店铺详情卡片（点击标注后显示）──
                if let selected = selectedRestaurant,
                   let restaurant = selected.restaurants {
                    RestaurantCard(
                        restaurant: restaurant,
                        author: selected.authors,
                        userId: authState.userId
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                }
            }

            // ── 右下角：粘贴链接按钮 ──
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showParseSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link.badge.plus")
                            Text("粘贴链接")
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                    }
                    .padding(.trailing, 20)
                    // 根据是否有选中店铺调整按钮位置，避免与详情卡片重合
                    .padding(.bottom, selectedRestaurant != nil ? 320 : 100)
                }
            }
        }
        .sheet(isPresented: $showParseSheet) {
            ParseLinkSheet(onSuccess: {
                // 解析成功后刷新地图数据
                Task { await viewModel.loadMapData(userId: authState.userId) }
            })
            .environmentObject(authState)
        }
        .task {
            await viewModel.loadMapData(userId: authState.userId)
            // 请求定位权限并开始定位
            locationManager.requestPermission()
        }
        // 点击地图空白处关闭详情卡片
        .onTapGesture {
            withAnimation { selectedRestaurant = nil }
        }
        // 监听用户位置变化，自动调整地图中心
        .onChange(of: locationManager.userLocation) { newLocation in
            if let location = newLocation, viewModel.isFirstLocationUpdate {
                viewModel.centerMapOnUserLocation(location)
            }
        }
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
                    .fill(isSelected ? Color.orange : Color.white)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(radius: isSelected ? 6 : 3)

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
                .fill(isSelected ? Color.orange : Color.white)
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
    @Binding var selectedAuthorId: String?

    // 从店铺列表中提取不重复的博主
    var authors: [Author] {
        var seen = Set<String>()
        return restaurants.compactMap { $0.authors }.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "全部" 按钮
                FilterChip(
                    label: "全部",
                    avatarURL: nil,
                    isSelected: selectedAuthorId == nil
                ) {
                    selectedAuthorId = nil
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

struct FilterChip: View {
    let label: String
    let avatarURL: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let url = avatarURL {
                    AsyncImage(url: URL(string: url)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.orange : Color.white)
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.1), radius: 2)
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

    @State private var isFavorited = false
    @State private var videos: [RestaurantVideo] = []
    @State private var isLoadingVideos = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(restaurant.name)
                        .font(.headline)
                    if let category = restaurant.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
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
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            // 博主推荐信息
            if let author = author {
                HStack(spacing: 6) {
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("相关视频")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
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
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .task {
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
            HStack(spacing: 8) {
                // 博主头像
                AsyncImage(url: URL(string: video.author_avatar_url ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
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
                    .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    func openVideo() {
        if let url = video.douyinURL {
            UIApplication.shared.open(url)
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
        HStack(spacing: 8) {
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
        // 百度地图 URL Scheme - 使用 UTF-8 编码
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
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
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption).fontWeight(.medium)
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
