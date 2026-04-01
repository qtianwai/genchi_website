// API 网络请求服务
// 封装所有与后端通信的接口，iOS App 通过此文件调用后端 API

import Foundation

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

    func parseDouyinLink(url: String, userId: String) async throws -> ParseLinkResponse {
        struct Body: Codable { let url: String; let user_id: String }
        return try await post(
            path: "/api/parse-link",
            body: Body(url: url, user_id: userId),
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

    func getMapRestaurants(userId: String) async throws -> [MapRestaurant] {
        struct Response: Codable { let restaurants: [MapRestaurant] }
        let resp = try await get(
            path: "/api/map/restaurants",
            params: ["user_id": userId],
            responseType: Response.self
        )
        return resp.restaurants
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
