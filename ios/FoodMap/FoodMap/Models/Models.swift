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
// 解析链接的 API 响应（新版本）
// 后端优先解析当前视频快速返回，博主其他视频在后台异步处理
// ─────────────────────────────────────────
struct ParseLinkResponse: Codable {
    let status: String           // "cached" / "parsed"
    // 缓存命中时用 restaurant（新格式，单个店铺）
    let restaurant: RestaurantResult?
    // cached 返回时还有 author_id（用于查询解析状态）
    let author_id: String?
    let author: Author?          // parsed 返回时包含博主信息
    let restaurants: [RestaurantResult]?  // 向后兼容旧格式
    let message: String
    let is_background_running: Bool   // 是否有后台任务正在运行
    let background_progress: BackgroundProgress?
}

// 单个餐厅结果（兼容新旧两种后端格式）
struct RestaurantResult: Codable, Identifiable {
    let id: String?
    let name: String
    let address: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let amap_id: String?
    let category: String?

    // 兼容旧的 Restaurant 类型，转换为坐标
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// 后台解析任务进度
struct BackgroundProgress: Codable {
    let status: String          // pending / running / completed / failed
    let total_videos: Int
    let processed_videos: Int
    let new_restaurants_found: Int
    let task_type: String       // full_scan / incremental
}

// 后台任务状态查询响应
struct ParseStatusResponse: Codable {
    let has_task: Bool
    let status: String
    let task_type: String?
    let total_videos: Int?
    let processed_videos: Int?
    let new_restaurants_found: Int?
    let started_at: String?
    let completed_at: String?
    let message: String
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

// ─────────────────────────────────────────
// 店铺关联视频模型
// ─────────────────────────────────────────
struct RestaurantVideo: Identifiable, Codable {
    let video_id: String
    let author_id: String
    let author_name: String
    let author_avatar_url: String?
    let created_at: String

    var id: String { video_id }

    // 抖音视频链接
    var douyinURL: URL? {
        URL(string: "snssdk1128://aweme/detail/\(video_id)")
    }
}

// ─────────────────────────────────────────
// 手动添加店铺响应
// ─────────────────────────────────────────
struct ManualAddRestaurantResponse: Codable {
    let status: String
    let restaurant: RestaurantResult?
    let restaurant_id: String?
    let message: String
}
