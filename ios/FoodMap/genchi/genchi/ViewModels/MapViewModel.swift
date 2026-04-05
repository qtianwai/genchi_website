// 地图页面 ViewModel
// 管理地图数据、筛选、搜索、聚合和相机控制

import Foundation
import SwiftUI
import MapKit

private enum MapZoomBucket {
    case names
    case avatars
    case clusters
}

private actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}

enum MapAuthorFilter: Hashable {
    case all
    case mine
    case author(String)
    case subscribedUser(String)  // v6.0 新增：按订阅用户筛选
}

enum MapGroupFilter: Hashable {
    case all
    case favorites
    case avoided
    case custom(String)
}

enum MapDistanceFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case km1 = 1
    case km3 = 3
    case km5 = 5
    case km10 = 10

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return "不限"
        case .km1: return "1km"
        case .km3: return "3km"
        case .km5: return "5km"
        case .km10: return "10km"
        }
    }

    var kilometers: Double? {
        switch self {
        case .all: return nil
        case .km1: return 1
        case .km3: return 3
        case .km5: return 5
        case .km10: return 10
        }
    }
}

struct MapFilterState {
    var author: MapAuthorFilter = .all
    var group: MapGroupFilter = .all
    var distance: MapDistanceFilter = .all

    var hasActiveFilters: Bool {
        if author != .all { return true }
        if group != .all { return true }
        return distance != .all
    }

    var activeCount: Int {
        var count = 0
        if author != .all { count += 1 }
        if group != .all { count += 1 }
        if distance != .all { count += 1 }
        return count
    }
}

enum MapItemSource {
    case author
    case userCreated
}

// v6.0 新增：推荐来源类型
enum RecommendSourceType: Hashable {
    case author(Author)
    case selfCreated
    case subscribedUser(userId: String, nickname: String, avatarUrl: String?)
}

struct MapDisplayItem: Identifiable {
    let id: String
    let source: MapItemSource
    let sourceRecordId: String
    let restaurantId: String
    let restaurant: Restaurant
    let author: Author?
    let coordinate: CLLocationCoordinate2D
    let isUserCreated: Bool
    let isAvoided: Bool
    let isFavorited: Bool
    let groupIds: [String]
    var recommendedBy: [RecommendSourceType] = []  // v6.0 新增：所有推荐来源
    // v7.1 新增：全平台聚合计数
    let favoriteCount: Int
    let avoidCount: Int

    var category: String {
        (restaurant.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MapCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let members: [MapDisplayItem]

    var isCluster: Bool { members.count > 1 }
    var count: Int { members.count }
    var primary: MapDisplayItem? { members.first }
}

@MainActor
class MapViewModel: ObservableObject {
    @Published var mapRestaurants: [MapRestaurant] = []
    @Published var userRestaurants: [UserCreatedRestaurant] = []
    @Published var userGroups: [RestaurantGroup] = []

    // v6.0 新增：订阅地图数据
    @Published var subscribedMapData: [String: [UserMapRestaurantItem]] = [:]  // key: targetUserId
    @Published var mapSubscriptions: [MapSubscription] = []

    @Published var filter = MapFilterState()
    @Published var searchText = ""
    @Published var highlightedItemId: String? = nil

    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    // iOS 17+ Map API 使用的相机位置
    @Published var mapCameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
    )
    @Published var visibleRegion: MKCoordinateRegion? = nil

    // 是否是首次定位（首次定位时自动移动地图到用户位置）
    var isFirstLocationUpdate = true

    // 缩放阈值（平衡档）+ 滞回防抖
    private let nameShowEnterDelta: CLLocationDegrees = 0.06
    private let nameShowExitDelta: CLLocationDegrees = 0.065
    private let clusterEnterDelta: CLLocationDegrees = 0.11
    private let clusterExitDelta: CLLocationDegrees = 0.105
    private let cameraThrottleInterval: TimeInterval = 0.12

    private var renderRegion: MKCoordinateRegion? = nil
    private var zoomBucket: MapZoomBucket = .clusters
    private var lastCameraRefreshAt = Date.distantPast

    private var refreshTimer: Timer? = nil
    private var lastDataSignature = ""

    var hasActiveFilters: Bool { filter.hasActiveFilters }
    var activeFilterCount: Int { filter.activeCount }

    // MARK: - Derived Data
    var allItems: [MapDisplayItem] {
        // v6.0 改进：使用 mergedAllItems 实现双重去重和来源追踪
        return mergedAllItems()
    }

    var availableAuthors: [Author] {
        var seen = Set<String>()
        return mapRestaurants
            .compactMap { $0.authors }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Filtering / Search
    func filteredItems(
        userLocation: CLLocationCoordinate2D?,
        hiddenRestaurantIds: Set<String> = []
    ) -> [MapDisplayItem] {
        var items = allItems.filter { !hiddenRestaurantIds.contains($0.restaurantId) }

        // Author filter
        switch filter.author {
        case .all:
            break
        case .mine:
            items = items.filter { $0.isUserCreated }
        case .author(let authorId):
            items = items.filter { $0.author?.id == authorId }
        case .subscribedUser(let userId):  // v6.0 新增：按订阅用户筛选
            items = items.filter { item in
                item.recommendedBy.contains { source in
                    if case .subscribedUser(let sourceUserId, _, _) = source {
                        return sourceUserId == userId
                    }
                    return false
                }
            }
        }

        // Group filter
        switch filter.group {
        case .all:
            break
        case .favorites:
            items = items.filter { $0.isFavorited }
        case .avoided:
            items = items.filter { $0.isAvoided }
        case .custom(let groupId):
            items = items.filter { $0.groupIds.contains(groupId) }
        }

        // Distance filter
        if let radius = filter.distance.kilometers, let location = userLocation {
            let center = CLLocation(latitude: location.latitude, longitude: location.longitude)
            items = items.filter { item in
                let point = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
                return point.distance(from: center) <= radius * 1000
            }
        }

        // Search filter (联动筛选结果)
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            items = items.filter { item in
                let inRestaurant = item.restaurant.name.localizedCaseInsensitiveContains(keyword)
                let inAddress = item.restaurant.address?.localizedCaseInsensitiveContains(keyword) == true
                let inAuthor = item.author?.name.localizedCaseInsensitiveContains(keyword) == true
                return inRestaurant || inAddress || inAuthor
            }
        }

        return items
    }

    func searchResults(limit: Int = 8, hiddenRestaurantIds: Set<String> = []) -> [MapDisplayItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        var ranked: [(item: MapDisplayItem, score: Int)] = []
        for item in allItems where !hiddenRestaurantIds.contains(item.restaurantId) {
            let name = item.restaurant.name
            let authorName = item.author?.name ?? ""

            if name.localizedCaseInsensitiveContains(keyword) || authorName.localizedCaseInsensitiveContains(keyword) {
                var score = 0
                if name.localizedCaseInsensitiveContains(keyword) { score += 3 }
                if name.lowercased().hasPrefix(keyword.lowercased()) { score += 2 }
                if authorName.localizedCaseInsensitiveContains(keyword) { score += 1 }
                ranked.append((item, score))
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.restaurant.name.localizedStandardCompare(rhs.item.restaurant.name) == .orderedAscending
            }
            .map(\.item)
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Clustering
    func clusteredItems(
        userLocation: CLLocationCoordinate2D?,
        hiddenRestaurantIds: Set<String> = []
    ) -> [MapCluster] {
        let items = filteredItems(
            userLocation: userLocation,
            hiddenRestaurantIds: hiddenRestaurantIds
        )
        guard shouldCluster else {
            return items.map { item in
                MapCluster(id: "single:\(item.id)", coordinate: item.coordinate, members: [item])
            }
        }

        let region = renderRegion ?? visibleRegion ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
        let grid = max(region.span.latitudeDelta / 8.0, 0.015)

        var buckets: [String: [MapDisplayItem]] = [:]
        for item in items {
            let latKey = Int(floor(item.coordinate.latitude / grid))
            let lngKey = Int(floor(item.coordinate.longitude / grid))
            let key = "\(latKey)_\(lngKey)"
            buckets[key, default: []].append(item)
        }

        return buckets.map { (key, members) in
            if members.count == 1, let item = members.first {
                return MapCluster(id: "single:\(item.id)", coordinate: item.coordinate, members: members)
            }

            let lat = members.map(\.coordinate.latitude).reduce(0, +) / Double(members.count)
            let lng = members.map(\.coordinate.longitude).reduce(0, +) / Double(members.count)
            return MapCluster(
                id: "cluster:\(key)",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                members: members
            )
        }
        .sorted { lhs, rhs in
            if lhs.isCluster != rhs.isCluster { return lhs.isCluster && !rhs.isCluster }
            return lhs.count > rhs.count
        }
    }

    private var shouldCluster: Bool {
        zoomBucket == .clusters
    }

    var shouldShowStoreName: Bool {
        zoomBucket == .names
    }

    // MARK: - Camera
    func updateVisibleRegion(_ region: MKCoordinateRegion, forceRefresh: Bool = false) {
        visibleRegion = region

        let nextBucket = computeNextBucket(for: region.span.latitudeDelta)
        let now = Date()
        let shouldRefreshByTime = now.timeIntervalSince(lastCameraRefreshAt) >= cameraThrottleInterval
        let bucketChanged = nextBucket != zoomBucket

        if bucketChanged || forceRefresh || shouldRefreshByTime {
            zoomBucket = nextBucket
            renderRegion = region
            lastCameraRefreshAt = now
        }
    }

    func centerMapOnUserLocation(_ location: CLLocationCoordinate2D) {
        mapCameraPosition = .region(
            MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        )
        isFirstLocationUpdate = false
    }

    func focus(on item: MapDisplayItem) {
        highlightedItemId = item.id
        mapCameraPosition = .region(
            MKCoordinateRegion(
                center: item.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }

    func expandCluster(_ cluster: MapCluster) {
        guard !cluster.members.isEmpty else { return }
        let latitudes = cluster.members.map(\.coordinate.latitude)
        let longitudes = cluster.members.map(\.coordinate.longitude)

        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLng = longitudes.min(),
              let maxLng = longitudes.max() else {
            return
        }

        let latSpan = max((maxLat - minLat) * 1.8, 0.015)
        let lngSpan = max((maxLng - minLng) * 1.8, 0.015)
        let targetSpan = min(max(latSpan, lngSpan), 0.08)

        mapCameraPosition = .region(
            MKCoordinateRegion(
                center: cluster.coordinate,
                span: MKCoordinateSpan(latitudeDelta: targetSpan, longitudeDelta: targetSpan)
            )
        )
        zoomBucket = .avatars
    }

    func clearFilters() {
        filter = MapFilterState()
    }

    private func computeNextBucket(for latitudeDelta: CLLocationDegrees) -> MapZoomBucket {
        switch zoomBucket {
        case .names:
            if latitudeDelta >= clusterEnterDelta { return .clusters }
            if latitudeDelta >= nameShowExitDelta { return .avatars }
            return .names
        case .avatars:
            if latitudeDelta >= clusterEnterDelta { return .clusters }
            if latitudeDelta <= nameShowEnterDelta { return .names }
            return .avatars
        case .clusters:
            if latitudeDelta <= nameShowEnterDelta { return .names }
            if latitudeDelta <= clusterExitDelta { return .avatars }
            return .clusters
        }
    }

    // MARK: - Data Loading
    func loadMapData(userId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let resp = try await APIService.shared.getMapRestaurants(userId: userId)
            mapRestaurants = resp.restaurants
            userRestaurants = resp.user_restaurants
            lastDataSignature = makeDataSignature(restaurants: resp.restaurants, userRestaurants: resp.user_restaurants)
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadUserGroups(userId: String) async {
        do {
            userGroups = try await APIService.shared.getGroups(userId: userId)
        } catch {
            print("[地图] 加载分组失败: \(error)")
        }
    }

    func silentRefreshMapData(userId: String) async {
        do {
            let resp = try await APIService.shared.getMapRestaurants(userId: userId)
            let signature = makeDataSignature(restaurants: resp.restaurants, userRestaurants: resp.user_restaurants)
            if signature != lastDataSignature {
                mapRestaurants = resp.restaurants
                userRestaurants = resp.user_restaurants
                lastDataSignature = signature
                print("[地图自动刷新] 检测到数据变更，已更新")
            }
        } catch {
            print("[地图自动刷新] 静默刷新失败: \(error)")
        }
    }

    private func makeDataSignature(restaurants: [MapRestaurant], userRestaurants: [UserCreatedRestaurant]) -> String {
        let authorPart = restaurants
            .map { "\($0.id)|\($0.restaurant_id)|\($0.is_avoided ?? false)|\($0.is_favorited ?? false)" }
            .sorted()
            .joined(separator: ",")
        let userPart = userRestaurants
            .map { "\($0.id)|\($0.restaurant_id)|\($0.is_avoided ?? false)|\($0.is_favorited ?? false)" }
            .sorted()
            .joined(separator: ",")
        return "\(authorPart)#\(userPart)"
    }

    // MARK: - Auto Refresh
    func startAutoRefresh(userId: String) {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.silentRefreshMapData(userId: userId)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // ─────────────────────────────────────────
    // v6.0 订阅地图数据加载（并发限制 + 双重去重）
    // ─────────────────────────────────────────

    /// 加载订阅地图数据（最多并发3个，支持附近筛选）
    func loadSubscribedMapData(userId: String, userLocation: CLLocationCoordinate2D?) async {
        let enabledSubs = mapSubscriptions.filter { $0.is_enabled }
        guard !enabledSubs.isEmpty else { return }

        // 并发限制：最多同时加载3个
        let semaphore = AsyncSemaphore(value: 3)
        await withTaskGroup(of: Void.self) { group in
            for sub in enabledSubs {
                group.addTask {
                    await semaphore.wait()

                    do {
                        let data = try await APIService.shared.getUserMapRestaurants(
                            targetUserId: sub.target_user_id,
                            page: 1,
                            lat: userLocation?.latitude,
                            lng: userLocation?.longitude,
                            radiusKm: 10
                        )

                        await MainActor.run {
                            self.subscribedMapData[sub.target_user_id] = data.restaurants
                        }
                    } catch {
                        print("[订阅地图] 加载 \(sub.target_user_id) 失败: \(error)")
                    }

                    await semaphore.signal()
                }
            }
        }
    }

    /// 刷新订阅列表（App onAppear时调用，保证多端一致）
    func refreshSubscriptions(userId: String) async {
        do {
            let subs = try await APIService.shared.getMapSubscriptions(userId: userId)
            await MainActor.run {
                self.mapSubscriptions = subs
            }
        } catch {
            print("[订阅列表] 刷新失败: \(error)")
        }
    }

    /// 订阅用户地图
    func subscribeMap(subscriberId: String, targetUserId: String) async throws {
        try await APIService.shared.subscribeUserMap(subscriberId: subscriberId, targetUserId: targetUserId)
        // 订阅成功后，刷新订阅列表
        await refreshSubscriptions(userId: subscriberId)
    }

    /// 取消订阅
    func unsubscribeMap(subscriberId: String, targetUserId: String) async throws {
        try await APIService.shared.unsubscribeUserMap(subscriberId: subscriberId, targetUserId: targetUserId)
        // 取消订阅后，移除本地数据并刷新列表
        await MainActor.run {
            _ = self.subscribedMapData.removeValue(forKey: targetUserId)
        }
        await refreshSubscriptions(userId: subscriberId)
    }

    /// 切换订阅开关
    func toggleSubscription(subscriberId: String, targetUserId: String, isEnabled: Bool) async throws {
        try await APIService.shared.toggleMapSubscription(
            subscriberId: subscriberId,
            targetUserId: targetUserId,
            isEnabled: isEnabled
        )
        // 切换成功后，更新本地订阅列表
        await MainActor.run {
            if let idx = self.mapSubscriptions.firstIndex(where: { $0.target_user_id == targetUserId }) {
                self.mapSubscriptions[idx].is_enabled = isEnabled
            }
        }
    }

    // ─────────────────────────────────────────
    // 双重去重 + 信息优先级
    // ─────────────────────────────────────────

    /// 生成坐标网格键（用于50m内同名店铺兜底合并）
    /// 精度约111m，使用0.0005精度约50m
    private func nearbyKey(coordinate: CLLocationCoordinate2D, name: String) -> String {
        let lat = (coordinate.latitude * 2000).rounded() / 2000
        let lng = (coordinate.longitude * 2000).rounded() / 2000
        return "\(name)_\(lat)_\(lng)"
    }

    /// 合并所有数据源（博主 + 自建 + 订阅用户），执行双重去重和优先级排序
    func mergedAllItems(hiddenRestaurantIds: Set<String> = []) -> [MapDisplayItem] {
        var itemsByRestaurantId: [String: MapDisplayItem] = [:]
        var itemsByCoord: [String: MapDisplayItem] = [:]

        func appendRecommendation(
            _ source: RecommendSourceType,
            to existingItem: MapDisplayItem,
            restaurantId: String,
            coordKey: String
        ) {
            var updated = existingItem
            if !updated.recommendedBy.contains(source) {
                updated.recommendedBy.append(source)
            }
            itemsByRestaurantId[restaurantId] = updated
            itemsByCoord[coordKey] = updated
        }

        // 1. 添加自建推荐（优先级最高）
        for item in userRestaurants {
            guard let restaurant = item.restaurants,
                  let coordinate = restaurant.coordinate,
                  !hiddenRestaurantIds.contains(item.restaurant_id) else { continue }

            var displayItem = MapDisplayItem(
                id: "user:\(item.id)",
                source: .userCreated,
                sourceRecordId: item.id,
                restaurantId: item.restaurant_id,
                restaurant: restaurant,
                author: nil,
                coordinate: coordinate,
                isUserCreated: true,
                isAvoided: item.is_avoided ?? false,
                isFavorited: item.is_favorited ?? false,
                groupIds: item.group_ids ?? [],
                favoriteCount: item.favorite_count ?? 0,
                avoidCount: item.avoid_count ?? 0
            )
            displayItem.recommendedBy = [.selfCreated]

            itemsByRestaurantId[item.restaurant_id] = displayItem
            let key = nearbyKey(coordinate: coordinate, name: restaurant.name)
            itemsByCoord[key] = displayItem
        }

        // 2. 添加博主推荐（优先级中）
        for item in mapRestaurants {
            guard let restaurant = item.restaurants,
                  let coordinate = restaurant.coordinate,
                  let author = item.authors,
                  !hiddenRestaurantIds.contains(item.restaurant_id) else { continue }

            let key = nearbyKey(coordinate: coordinate, name: restaurant.name)

            if let existing = itemsByRestaurantId[item.restaurant_id] {
                appendRecommendation(.author(author), to: existing, restaurantId: item.restaurant_id, coordKey: key)
            } else if let existing = itemsByCoord[key] {
                appendRecommendation(.author(author), to: existing, restaurantId: existing.restaurantId, coordKey: key)
            } else {
                // 新增
                var displayItem = MapDisplayItem(
                    id: "author:\(item.id)",
                    source: .author,
                    sourceRecordId: item.id,
                    restaurantId: item.restaurant_id,
                    restaurant: restaurant,
                    author: author,
                    coordinate: coordinate,
                    isUserCreated: false,
                    isAvoided: item.is_avoided ?? false,
                    isFavorited: item.is_favorited ?? false,
                    groupIds: item.group_ids ?? [],
                    favoriteCount: item.favorite_count ?? 0,
                    avoidCount: item.avoid_count ?? 0
                )
                displayItem.recommendedBy = [.author(author)]

                itemsByRestaurantId[item.restaurant_id] = displayItem
                itemsByCoord[key] = displayItem
            }
        }

        // 3. 添加订阅用户推荐（优先级最低）
        for (targetUserId, restaurants) in subscribedMapData {
            // 从订阅列表中获取用户昵称和头像
            guard let subscription = mapSubscriptions.first(where: { $0.target_user_id == targetUserId }) else {
                continue
            }

            for restaurant in restaurants {
                guard let lat = restaurant.latitude,
                      let lng = restaurant.longitude,
                      !hiddenRestaurantIds.contains(restaurant.restaurant_id) else { continue }

                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let key = nearbyKey(coordinate: coordinate, name: restaurant.name)

                // 构建 Restaurant 对象
                let restaurantObj = Restaurant(
                    id: restaurant.id,
                    name: restaurant.name,
                    address: restaurant.address,
                    city: restaurant.city,
                    latitude: lat,
                    longitude: lng,
                    amap_id: nil,
                    category: restaurant.category,
                    verified: nil,
                    avg_price: nil,
                    photo_url: restaurant.photo_url
                )

                if let existing = itemsByRestaurantId[restaurant.restaurant_id] {
                    appendRecommendation(
                        .subscribedUser(userId: targetUserId, nickname: subscription.nickname, avatarUrl: subscription.avatar_url),
                        to: existing,
                        restaurantId: restaurant.restaurant_id,
                        coordKey: key
                    )
                } else if let existing = itemsByCoord[key] {
                    appendRecommendation(
                        .subscribedUser(userId: targetUserId, nickname: subscription.nickname, avatarUrl: subscription.avatar_url),
                        to: existing,
                        restaurantId: existing.restaurantId,
                        coordKey: key
                    )
                } else {
                    // 新增
                    var displayItem = MapDisplayItem(
                        id: "sub:\(targetUserId):\(restaurant.id)",
                        source: .userCreated,
                        sourceRecordId: restaurant.id,
                        restaurantId: restaurant.restaurant_id,
                        restaurant: restaurantObj,
                        author: nil,
                        coordinate: coordinate,
                        isUserCreated: false,
                        isAvoided: false,
                        isFavorited: false,
                        groupIds: [],
                        favoriteCount: 0,
                        avoidCount: 0
                    )
                    displayItem.recommendedBy = [
                        .subscribedUser(userId: targetUserId, nickname: subscription.nickname, avatarUrl: subscription.avatar_url)
                    ]

                    itemsByRestaurantId[restaurant.restaurant_id] = displayItem
                    itemsByCoord[key] = displayItem
                }
            }
        }

        return Array(itemsByRestaurantId.values)
    }
}
