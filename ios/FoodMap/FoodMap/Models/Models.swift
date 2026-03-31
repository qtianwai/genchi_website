// 数据模型定义文件
// 定义 App 中所有核心数据结构，与后端 API 返回格式对应

import Foundation
import CoreLocation

// ─────────────────────────────────────────
// 博主模型
// ─────────────────────────────────────────
struct Author: Identifiable, Codable, Hashable {
    let id: String
    let douyin_uid: String
    let name: String
    let avatar_url: String?
    let created_at: String?
}

// ─────────────────────────────────────────
// 店铺模型
// ─────────────────────────────────────────
struct Restaurant: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let address: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let amap_id: String?
    let category: String?

    // 计算属性：转换为 CoreLocation 坐标（地图标注用）
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// ─────────────────────────────────────────
// 地图标注模型（博主推荐的店铺，含博主信息）
// ─────────────────────────────────────────
struct MapRestaurant: Identifiable, Codable {
    let id: String          // author_restaurants 表的 id
    let author_id: String
    let restaurant_id: String
    let restaurants: Restaurant?    // 店铺详情（join 查询）
    let authors: Author?            // 博主详情（join 查询）

    // Identifiable 协议需要
    var mapId: String { id }
}

// ─────────────────────────────────────────
// 解析链接的 API 响应
// ─────────────────────────────────────────
struct ParseLinkResponse: Codable {
    let status: String          // "cached" 或 "parsed"
    let author: Author
    let restaurants: [RestaurantResult]
    let message: String
}

struct RestaurantResult: Codable, Identifiable {
    let id: String?
    let name: String
    let address: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let amap_id: String?
    let category: String?
}

// ─────────────────────────────────────────
// 用户收藏模型
// ─────────────────────────────────────────
struct Favorite: Identifiable, Codable {
    let id: String
    let user_id: String
    let restaurant_id: String
    let restaurants: Restaurant?    // join 查询的店铺详情
}
