// API 网络请求服务
// 封装所有与后端通信的接口，iOS App 通过此文件调用后端 API

import Foundation
import CoreLocation

// 后端服务地址，部署到 Railway 后替换为真实地址
// 本地开发时使用 http://localhost:8000
let BASE_URL = "https://claudetest-production-c925.up.railway.app"  // Railway 部署地址

class APIService {
    static let shared = APIService()
    private init() {}

    // 通用 POST 请求
    private func post<T: Codable, R: Codable>(
        path: String,
        body: T,
        responseType: R.Type
    ) async throws -> R {
        guard let url = URL(string: "\(BASE_URL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 60  // 解析抖音可能较慢，设置 60 秒超时

        let (data, response) = try await URLSession.shared.data(for: request)

        // 检查 HTTP 状态码
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            // 尝试解析错误信息
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("请求失败，状态码: \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(R.self, from: data)
    }

    // 通用 GET 请求
    private func get<R: Codable>(
        path: String,
        params: [String: String] = [:],
        responseType: R.Type
    ) async throws -> R {
        var components = URLComponents(string: "\(BASE_URL)\(path)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(R.self, from: data)
    }

    // ─────────────────────────────────────────
    // 解析抖音链接
    // ─────────────────────────────────────────

    func parseDouyinLink(url: String, userId: String, scope: String = "follow_all") async throws -> ParseLinkResponse {
        // scope: "follow_all" → 关注博主 + 触发后台全量解析（默认）
        //        "single_only" → 仅添加本店铺，不关注博主，不触发后台任务
        struct Body: Codable { let url: String; let user_id: String; let scope: String }
        return try await post(
            path: "/api/parse-link",
            body: Body(url: url, user_id: userId, scope: scope),
            responseType: ParseLinkResponse.self
        )
    }

    // 查询博主后台解析任务进度
    func getParseStatus(authorId: String) async throws -> ParseStatusResponse {
        return try await get(
            path: "/api/parse-status/\(authorId)",
            params: [:],
            responseType: ParseStatusResponse.self
        )
    }

    // ─────────────────────────────────────────
    // 地图数据
    // ─────────────────────────────────────────

    func getMapRestaurants(userId: String) async throws -> MapRestaurantsResponse {
        return try await get(
            path: "/api/map/restaurants",
            params: ["user_id": userId],
            responseType: MapRestaurantsResponse.self
        )
    }

    // ─────────────────────────────────────────
    // 博主关注
    // ─────────────────────────────────────────

    func getFollowingAuthors(userId: String) async throws -> [Author] {
        struct FollowItem: Codable { let authors: Author? }
        struct Response: Codable { let authors: [FollowItem] }
        let resp = try await get(
            path: "/api/authors/following",
            params: ["user_id": userId],
            responseType: Response.self
        )
        return resp.authors.compactMap { $0.authors }
    }

    func followAuthor(userId: String, authorId: String) async throws {
        struct Body: Codable { let user_id: String; let author_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/authors/follow",
            body: Body(user_id: userId, author_id: authorId),
            responseType: Response.self
        )
    }

    func unfollowAuthor(userId: String, authorId: String) async throws {
        struct Body: Codable { let user_id: String; let author_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/authors/unfollow",
            body: Body(user_id: userId, author_id: authorId),
            responseType: Response.self
        )
    }

    // 获取博主推荐的所有店铺
    func getAuthorRestaurants(authorId: String) async throws -> [MapRestaurant] {
        struct Response: Codable { let restaurants: [MapRestaurant] }
        let resp = try await get(
            path: "/api/authors/\(authorId)/restaurants",
            params: [:],
            responseType: Response.self
        )
        return resp.restaurants
    }

    // ─────────────────────────────────────────
    // 收藏
    // ─────────────────────────────────────────

    func getFavorites(userId: String) async throws -> [Favorite] {
        struct Response: Codable { let favorites: [Favorite] }
        let resp = try await get(
            path: "/api/favorites",
            params: ["user_id": userId],
            responseType: Response.self
        )
        return resp.favorites
    }

    func addFavorite(userId: String, restaurantId: String) async throws {
        struct Body: Codable { let user_id: String; let restaurant_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/favorites/add",
            body: Body(user_id: userId, restaurant_id: restaurantId),
            responseType: Response.self
        )
    }

    func removeFavorite(userId: String, restaurantId: String) async throws {
        struct Body: Codable { let user_id: String; let restaurant_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/favorites/remove",
            body: Body(user_id: userId, restaurant_id: restaurantId),
            responseType: Response.self
        )
    }

    // ─────────────────────────────────────────
    // 店铺关联视频
    // ─────────────────────────────────────────

    func getRestaurantVideos(restaurantId: String) async throws -> [RestaurantVideo] {
        struct Response: Codable { let videos: [RestaurantVideo] }
        let resp = try await get(
            path: "/api/restaurants/\(restaurantId)/videos",
            params: [:],
            responseType: Response.self
        )
        return resp.videos
    }

    // ─────────────────────────────────────────
    // 手动添加店铺
    // ─────────────────────────────────────────

    func manualAddRestaurant(
        videoUrl: String,
        userId: String,
        restaurantName: String,
        city: String,
        category: String
    ) async throws -> ManualAddRestaurantResponse {
        struct Body: Codable {
            let video_url: String
            let user_id: String
            let restaurant_name: String
            let city: String
            let category: String
        }
        return try await post(
            path: "/api/manual-add-restaurant",
            body: Body(
                video_url: videoUrl,
                user_id: userId,
                restaurant_name: restaurantName,
                city: city,
                category: category
            ),
            responseType: ManualAddRestaurantResponse.self
        )
    }

    // ─────────────────────────────────────────
    // 后台人工复核接口（v3.0 新增）
    // 所有接口携带 X-User-ID Header 进行管理员鉴权
    // ─────────────────────────────────────────

    // 携带管理员 Header 的 GET 请求
    private func adminGet<R: Codable>(
        path: String,
        params: [String: String] = [:],
        userId: String,
        responseType: R.Type
    ) async throws -> R {
        var components = URLComponents(string: "\(BASE_URL)\(path)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("请求失败，状态码: \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    // 携带管理员 Header 的 POST 请求
    private func adminPost<T: Codable, R: Codable>(
        path: String,
        body: T,
        userId: String,
        responseType: R.Type
    ) async throws -> R {
        guard let url = URL(string: "\(BASE_URL)\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("请求失败，状态码: \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    // 获取复核列表（tab: "pending" 或 "reviewed"）
    func getReviewList(page: Int = 1, tab: String = "pending", userId: String) async throws -> ReviewListResponse {
        return try await adminGet(
            path: "/api/admin/review/list",
            params: ["page": "\(page)", "page_size": "20", "tab": tab],
            userId: userId,
            responseType: ReviewListResponse.self
        )
    }

    // 搜索店铺候选（复核修正时使用）
    func searchRestaurantForReview(name: String, city: String, userId: String) async throws -> [RestaurantCandidate] {
        var params = ["name": name]
        if !city.isEmpty { params["city"] = city }
        let resp = try await adminGet(
            path: "/api/admin/review/search-restaurant",
            params: params,
            userId: userId,
            responseType: RestaurantCandidatesResponse.self
        )
        return resp.candidates
    }

    // 确认 AI 识别结果正确
    func adminConfirmCorrect(cacheId: String, userId: String) async throws {
        struct Body: Codable { let cache_id: String }
        struct Resp: Codable { let status: String }
        _ = try await adminPost(
            path: "/api/admin/review/confirm-correct",
            body: Body(cache_id: cacheId),
            userId: userId,
            responseType: Resp.self
        )
    }

    // 确认视频无店铺
    func adminConfirmEmpty(cacheId: String, userId: String) async throws {
        struct Body: Codable { let cache_id: String }
        struct Resp: Codable { let status: String }
        _ = try await adminPost(
            path: "/api/admin/review/confirm-empty",
            body: Body(cache_id: cacheId),
            userId: userId,
            responseType: Resp.self
        )
    }

    // 人工修正店铺
    func adminCorrect(cacheId: String, candidate: RestaurantCandidate, category: String, userId: String) async throws {
        struct Body: Codable {
            let cache_id: String
            let amap_id: String
            let restaurant_name: String
            let address: String
            let city: String
            let latitude: Double
            let longitude: Double
            let category: String
            let avg_price: Int?
            let photo_url: String?
        }
        struct Resp: Codable { let status: String }
        _ = try await adminPost(
            path: "/api/admin/review/correct",
            body: Body(
                cache_id: cacheId,
                amap_id: candidate.amap_id,
                restaurant_name: candidate.name,
                address: candidate.address,
                city: candidate.city,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                category: category,
                avg_price: candidate.avg_price,
                photo_url: candidate.photo_url
            ),
            userId: userId,
            responseType: Resp.self
        )
    }

    // v9.0 新增：多店铺修正（一个视频关联多家店铺）
    func adminCorrectMulti(
        cacheId: String,
        restaurants: [(candidate: RestaurantCandidate, category: String)],
        userId: String
    ) async throws {
        // 单个店铺条目
        struct RestaurantEntry: Codable {
            let amap_id: String
            let restaurant_name: String
            let address: String
            let city: String
            let latitude: Double
            let longitude: Double
            let category: String
            let avg_price: Int?
            let photo_url: String?
        }
        struct Body: Codable {
            let cache_id: String
            let restaurants: [RestaurantEntry]
        }
        struct Resp: Codable { let status: String }

        let entries = restaurants.map { r in
            RestaurantEntry(
                amap_id: r.candidate.amap_id,
                restaurant_name: r.candidate.name,
                address: r.candidate.address,
                city: r.candidate.city,
                latitude: r.candidate.latitude,
                longitude: r.candidate.longitude,
                category: r.category,
                avg_price: r.candidate.avg_price,
                photo_url: r.candidate.photo_url
            )
        }
        _ = try await adminPost(
            path: "/api/admin/review/correct-multi",
            body: Body(cache_id: cacheId, restaurants: entries),
            userId: userId,
            responseType: Resp.self
        )
    }

    // 跳过复核
    func adminSkip(cacheId: String, userId: String) async throws {
        struct Body: Codable { let cache_id: String }
        struct Resp: Codable { let status: String }
        _ = try await adminPost(
            path: "/api/admin/review/skip",
            body: Body(cache_id: cacheId),
            userId: userId,
            responseType: Resp.self
        )
    }

    // ─────────────────────────────────────────
    // 用户自建推荐店铺（v4.0 新增）
    // ─────────────────────────────────────────

    // 搜索高德候选店铺（用于用户自建推荐时选择）
    func searchUserRestaurant(
        name: String,
        city: String,
        location: CLLocationCoordinate2D? = nil,
        limit: Int = 50
    ) async throws -> [RestaurantCandidate] {
        var params = [
            "name": name,
            "limit": "\(limit)"
        ]
        if !city.isEmpty {
            params["city"] = city
        }
        if let location {
            params["lat"] = "\(location.latitude)"
            params["lng"] = "\(location.longitude)"
        }

        let resp = try await get(
            path: "/api/user-restaurants/search",
            params: params,
            responseType: UserRestaurantSearchResponse.self
        )
        return resp.results
    }

    // 创建用户自建推荐店铺
    func createUserRestaurant(
        userId: String,
        candidate: RestaurantCandidate,
        note: String = ""
    ) async throws -> CreateUserRestaurantResponse {
        struct Body: Codable {
            let user_id: String
            let amap_id: String
            let restaurant_name: String
            let address: String
            let city: String
            let latitude: Double
            let longitude: Double
            let category: String
            let note: String
            let avg_price: Int?
            let photo_url: String
        }
        return try await post(
            path: "/api/user-restaurants",
            body: Body(
                user_id: userId,
                amap_id: candidate.amap_id,
                restaurant_name: candidate.name,
                address: candidate.address,
                city: candidate.city,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                category: candidate.category_mapped,
                note: note,
                avg_price: candidate.avg_price,
                photo_url: candidate.photo_url ?? ""
            ),
            responseType: CreateUserRestaurantResponse.self
        )
    }

    // 获取用户自建推荐列表
    func getUserRestaurants(userId: String) async throws -> [UserCreatedRestaurant] {
        let resp = try await get(
            path: "/api/user-restaurants",
            params: ["user_id": userId],
            responseType: UserRestaurantsResponse.self
        )
        return resp.restaurants
    }

    // 删除用户自建推荐店铺
    func deleteUserRestaurant(userId: String, restaurantId: String) async throws {
        var components = URLComponents(string: "\(BASE_URL)/api/user-restaurants/\(restaurantId)")!
        components.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("删除失败，状态码: \(httpResponse.statusCode)")
        }
    }

    // ─────────────────────────────────────────
    // 避雷店铺（v5.0 新增）
    // ─────────────────────────────────────────

    // 避雷店铺
    func avoidRestaurant(userId: String, restaurantId: String) async throws {
        struct Body: Codable { let user_id: String; let restaurant_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/restaurants/avoid",
            body: Body(user_id: userId, restaurant_id: restaurantId),
            responseType: Response.self
        )
    }

    // 取消避雷
    func unavoidRestaurant(userId: String, restaurantId: String) async throws {
        struct Body: Codable { let user_id: String; let restaurant_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/restaurants/unavoid",
            body: Body(user_id: userId, restaurant_id: restaurantId),
            responseType: Response.self
        )
    }

    // 获取避雷列表
    func getAvoidedRestaurants(userId: String) async throws -> [AvoidedRestaurant] {
        struct Response: Codable { let restaurants: [AvoidedRestaurant] }
        let resp = try await get(
            path: "/api/restaurants/avoided",
            params: ["user_id": userId],
            responseType: Response.self
        )
        return resp.restaurants
    }

    // ─────────────────────────────────────────
    // 删除店铺（v5.0 新增，全局隐藏）
    // ─────────────────────────────────────────

    func deleteRestaurantForUser(userId: String, restaurantId: String) async throws {
        struct Body: Codable { let user_id: String; let restaurant_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/restaurants/delete",
            body: Body(user_id: userId, restaurant_id: restaurantId),
            responseType: Response.self
        )
    }

    // ─────────────────────────────────────────
    // 收藏理由（v5.0 新增）
    // ─────────────────────────────────────────

    func updateFavoriteNote(userId: String, restaurantId: String, note: String) async throws {
        struct Body: Codable { let user_id: String; let restaurant_id: String; let note: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/favorites/update-note",
            body: Body(user_id: userId, restaurant_id: restaurantId, note: note),
            responseType: Response.self
        )
    }

    // ─────────────────────────────────────────
    // 用户自定义分组（v5.0 新增）
    // ─────────────────────────────────────────

    // 获取用户分组列表
    func getGroups(userId: String) async throws -> [RestaurantGroup] {
        struct Response: Codable { let groups: [RestaurantGroup] }
        let resp = try await get(
            path: "/api/groups",
            params: ["user_id": userId],
            responseType: Response.self
        )
        return resp.groups
    }

    // 创建分组
    func createGroup(userId: String, name: String) async throws -> RestaurantGroup {
        struct Body: Codable { let user_id: String; let name: String }
        struct Response: Codable { let status: String; let group: RestaurantGroup }
        let resp = try await post(
            path: "/api/groups",
            body: Body(user_id: userId, name: name),
            responseType: Response.self
        )
        return resp.group
    }

    // 删除分组
    func deleteGroup(userId: String, groupId: String) async throws {
        var components = URLComponents(string: "\(BASE_URL)/api/groups/\(groupId)")!
        components.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("删除分组失败")
        }
    }

    // 添加店铺到分组
    func addToGroup(userId: String, groupId: String, restaurantId: String) async throws {
        struct Body: Codable { let user_id: String; let group_id: String; let restaurant_id: String }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/groups/\(groupId)/restaurants",
            body: Body(user_id: userId, group_id: groupId, restaurant_id: restaurantId),
            responseType: Response.self
        )
    }

    // 从分组移除店铺
    func removeFromGroup(userId: String, groupId: String, restaurantId: String) async throws {
        var components = URLComponents(string: "\(BASE_URL)/api/groups/\(groupId)/restaurants/\(restaurantId)")!
        components.queryItems = [URLQueryItem(name: "user_id", value: userId)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("移除失败")
        }
    }

    // 获取分组内店铺列表
    func getGroupRestaurants(groupId: String, userId: String) async throws -> [GroupRestaurant] {
        struct Response: Codable { let restaurants: [GroupRestaurant] }
        let resp = try await get(
            path: "/api/groups/\(groupId)/restaurants",
            params: ["user_id": userId],
            responseType: Response.self
        )
        return resp.restaurants
    }

    // ─────────────────────────────────────────
    // 博主统计（v5.0 新增）
    // ─────────────────────────────────────────

    func getAuthorStats(authorId: String) async throws -> AuthorStats {
        return try await get(
            path: "/api/authors/\(authorId)/stats",
            params: [:],
            responseType: AuthorStats.self
        )
    }

    // ─────────────────────────────────────────
    // v6.0 个人专属美食地图
    // ─────────────────────────────────────────

    // 获取他人地图基本信息（昵称、店铺总数、是否公开）
    func getUserMapInfo(targetUserId: String) async throws -> UserMapInfo {
        return try await get(
            path: "/api/map/\(targetUserId)/info",
            params: [:],
            responseType: UserMapInfo.self
        )
    }

    // 获取他人地图的店铺列表（分页、支持附近筛选）
    func getUserMapRestaurants(
        targetUserId: String,
        page: Int = 1,
        lat: Double? = nil,
        lng: Double? = nil,
        radiusKm: Double = 10
    ) async throws -> UserMapRestaurantsResponse {
        var params: [String: String] = [
            "page": String(page),
            "page_size": "50"
        ]
        if let lat = lat, let lng = lng {
            params["lat"] = String(lat)
            params["lng"] = String(lng)
            params["radius_km"] = String(radiusKm)
        }
        return try await get(
            path: "/api/map/\(targetUserId)/restaurants",
            params: params,
            responseType: UserMapRestaurantsResponse.self
        )
    }

    // 更新自己地图的隐私设置（公开/私密）
    func updateMapPrivacy(userId: String, isPublic: Bool) async throws {
        struct Body: Codable {
            let user_id: String
            let is_public: Bool
        }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/map/privacy",
            body: Body(user_id: userId, is_public: isPublic),
            responseType: Response.self
        )
    }

    // 获取我的订阅列表
    func getMapSubscriptions(userId: String) async throws -> [MapSubscription] {
        struct Response: Codable { let subscriptions: [MapSubscription] }
        let resp = try await get(
            path: "/api/map-subscriptions",
            params: ["user_id": userId],
            responseType: Response.self
        )
        return resp.subscriptions
    }

    // 订阅他人地图
    func subscribeUserMap(subscriberId: String, targetUserId: String) async throws {
        struct Body: Codable {
            let subscriber_id: String
            let target_user_id: String
        }
        struct Response: Codable { let status: String }
        _ = try await post(
            path: "/api/map-subscriptions",
            body: Body(subscriber_id: subscriberId, target_user_id: targetUserId),
            responseType: Response.self
        )
    }

    // 取消订阅
    func unsubscribeUserMap(subscriberId: String, targetUserId: String) async throws {
        var components = URLComponents(string: "\(BASE_URL)/api/map-subscriptions/\(targetUserId)")!
        components.queryItems = [URLQueryItem(name: "subscriber_id", value: subscriberId)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("取消订阅失败")
        }
    }

    // 切换订阅开关（是否在自己地图上显示该用户点位）
    func toggleMapSubscription(subscriberId: String, targetUserId: String, isEnabled: Bool) async throws {
        struct Body: Codable {
            let subscriber_id: String
            let is_enabled: Bool
        }
        struct Response: Codable { let status: String }
        _ = try await patch(
            path: "/api/map-subscriptions/\(targetUserId)",
            body: Body(subscriber_id: subscriberId, is_enabled: isEnabled),
            responseType: Response.self
        )
    }

    // 通用 PATCH 请求
    private func patch<T: Codable, R: Codable>(
        path: String,
        body: T,
        responseType: R.Type
    ) async throws -> R {
        guard let url = URL(string: "\(BASE_URL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let detail = errorBody["detail"] {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("请求失败，状态码: \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(R.self, from: data)
    }

    // ─────────────────────────────────────────
    // v8.0 饭团系统 API
    // ─────────────────────────────────────────

    // MARK: - 天气

    /// 获取当前天气信息
    func getWeather(lat: Double, lng: Double) async throws -> WeatherInfo {
        try await get(
            path: "/api/weather",
            params: ["lat": String(lat), "lng": String(lng)],
            responseType: WeatherInfo.self
        )
    }

    // MARK: - 抽卡

    /// 查询今日剩余抽卡次数
    func getGachaRemaining(userId: String) async throws -> GachaRemainingResponse {
        try await get(
            path: "/api/gacha/remaining",
            params: ["user_id": userId],
            responseType: GachaRemainingResponse.self
        )
    }

    /// 执行一次抽卡（返回 6 张卡片）
    func gachaDraw(userId: String, lat: Double, lng: Double, qaAnswers: [[String: String]]? = nil) async throws -> GachaDrawResponse {
        struct Body: Codable {
            let user_id: String
            let latitude: Double
            let longitude: Double
            let qa_answers: [[String: String]]?
        }
        return try await post(
            path: "/api/gacha/draw",
            body: Body(user_id: userId, latitude: lat, longitude: lng, qa_answers: qaAnswers),
            responseType: GachaDrawResponse.self
        )
    }

    /// 用户选中某张卡片
    func gachaSelect(userId: String, sessionId: String, restaurantId: String) async throws -> GachaSelectResponse {
        struct Body: Codable {
            let user_id: String
            let session_id: String
            let restaurant_id: String
        }
        return try await post(
            path: "/api/gacha/select",
            body: Body(user_id: userId, session_id: sessionId, restaurant_id: restaurantId),
            responseType: GachaSelectResponse.self
        )
    }

    // MARK: - 问答推荐

    /// 问答模式：获取动态问题
    func getRecommendQuestions(userId: String, lat: Double, lng: Double) async throws -> QAQuestionsResponse {
        struct Body: Codable {
            let user_id: String
            let latitude: Double
            let longitude: Double
        }
        return try await post(
            path: "/api/recommend/questions",
            body: Body(user_id: userId, latitude: lat, longitude: lng),
            responseType: QAQuestionsResponse.self
        )
    }

    /// 问答模式：基于回答生成推荐
    func getRecommendResult(userId: String, lat: Double, lng: Double, answers: [[String: String]]) async throws -> QAResultResponse {
        struct Body: Codable {
            let user_id: String
            let latitude: Double
            let longitude: Double
            let answers: [[String: String]]
        }
        return try await post(
            path: "/api/recommend/result",
            body: Body(user_id: userId, latitude: lat, longitude: lng, answers: answers),
            responseType: QAResultResponse.self
        )
    }

    // MARK: - 打卡

    /// 创建打卡记录
    func createCheckin(userId: String, restaurantId: String, rating: Int? = nil, comment: String? = nil, photoUrls: [String]? = nil) async throws -> CheckinResponse {
        struct Body: Codable {
            let user_id: String
            let restaurant_id: String
            let rating: Int?
            let comment: String?
            let photo_urls: [String]?
        }
        return try await post(
            path: "/api/checkins",
            body: Body(user_id: userId, restaurant_id: restaurantId, rating: rating, comment: comment, photo_urls: photoUrls),
            responseType: CheckinResponse.self
        )
    }

    /// 获取某店铺的打卡记录
    func getRestaurantCheckins(restaurantId: String, limit: Int = 20) async throws -> [Checkin] {
        try await get(
            path: "/api/checkins/restaurant/\(restaurantId)",
            params: ["limit": String(limit)],
            responseType: [Checkin].self
        )
    }

    /// 获取用户打卡历史
    func getUserCheckins(userId: String, limit: Int = 50) async throws -> [Checkin] {
        try await get(
            path: "/api/checkins/user",
            params: ["user_id": userId, "limit": String(limit)],
            responseType: [Checkin].self
        )
    }

    // MARK: - 成就

    /// 获取所有成就定义
    func getAllAchievements() async throws -> [Achievement] {
        try await get(path: "/api/achievements", responseType: [Achievement].self)
    }

    /// 获取用户已解锁的成就
    func getUserAchievements(userId: String) async throws -> [UserAchievement] {
        try await get(
            path: "/api/achievements/user",
            params: ["user_id": userId],
            responseType: [UserAchievement].self
        )
    }

    // MARK: - 行为日志

    /// 记录用户行为
    func logBehavior(userId: String, action: String, targetType: String? = nil, targetId: String? = nil, metadata: [String: String]? = nil) async throws {
        struct Body: Codable {
            let user_id: String
            let action: String
            let target_type: String?
            let target_id: String?
            let metadata: [String: String]?
        }
        struct Resp: Codable { let status: String }
        _ = try await post(
            path: "/api/behavior/log",
            body: Body(user_id: userId, action: action, target_type: targetType, target_id: targetId, metadata: metadata),
            responseType: Resp.self
        )
    }

    // MARK: - 收藏留言 AI 摘要

    /// 获取店铺收藏留言 AI 摘要
    func getReviewsSummary(restaurantId: String) async throws -> ReviewsSummaryResponse {
        try await get(
            path: "/api/restaurants/\(restaurantId)/reviews-summary",
            responseType: ReviewsSummaryResponse.self
        )
    }
}

// 自定义错误类型
enum APIError: LocalizedError {
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return msg
        }
    }
}
