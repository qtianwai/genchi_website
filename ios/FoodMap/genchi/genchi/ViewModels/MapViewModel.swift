// 地图页面 ViewModel
// 管理地图数据、筛选、搜索、聚合和相机控制

import Foundation
import SwiftUI
import MapKit

enum MapAuthorFilter: Hashable {
    case all
    case mine
    case author(String)
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
    var categories: Set<String> = []

    var hasActiveFilters: Bool {
        if author != .all { return true }
        if group != .all { return true }
        if distance != .all { return true }
        return !categories.isEmpty
    }

    var activeCount: Int {
        var count = 0
        if author != .all { count += 1 }
        if group != .all { count += 1 }
        if distance != .all { count += 1 }
        if !categories.isEmpty { count += 1 }
        return count
    }
}

enum MapItemSource {
    case author
    case userCreated
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

    private var refreshTimer: Timer? = nil
    private var lastDataSignature = ""

    var hasActiveFilters: Bool { filter.hasActiveFilters }
    var activeFilterCount: Int { filter.activeCount }

    // MARK: - Derived Data
    var allItems: [MapDisplayItem] {
        var items: [MapDisplayItem] = []

        for item in mapRestaurants {
            guard let restaurant = item.restaurants,
                  let coordinate = restaurant.coordinate else { continue }
            items.append(
                MapDisplayItem(
                    id: "author:\(item.id)",
                    source: .author,
                    sourceRecordId: item.id,
                    restaurantId: item.restaurant_id,
                    restaurant: restaurant,
                    author: item.authors,
                    coordinate: coordinate,
                    isUserCreated: false,
                    isAvoided: item.is_avoided ?? false,
                    isFavorited: item.is_favorited ?? false,
                    groupIds: item.group_ids ?? []
                )
            )
        }

        for item in userRestaurants {
            guard let restaurant = item.restaurants,
                  let coordinate = restaurant.coordinate else { continue }
            items.append(
                MapDisplayItem(
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
                    groupIds: item.group_ids ?? []
                )
            )
        }

        return items
    }

    var availableAuthors: [Author] {
        var seen = Set<String>()
        return mapRestaurants
            .compactMap { $0.authors }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var availableCategories: [String] {
        let categories = allItems
            .compactMap { item -> String? in
                let value = item.category
                return value.isEmpty ? nil : value
            }
        return Array(Set(categories)).sorted()
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

        // Category filter
        if !filter.categories.isEmpty {
            items = items.filter { filter.categories.contains($0.category) }
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

        let region = visibleRegion ?? MKCoordinateRegion(
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
        guard let region = visibleRegion else { return false }
        return region.span.latitudeDelta >= 0.09
    }

    var shouldShowStoreName: Bool {
        guard let region = visibleRegion else { return false }
        return region.span.latitudeDelta <= 0.03
    }

    // MARK: - Camera
    func updateVisibleRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
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
    }

    func clearFilters() {
        filter = MapFilterState()
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
}
