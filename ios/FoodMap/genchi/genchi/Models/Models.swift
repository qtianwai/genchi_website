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
    let verified: Bool?      // 是否经过人工验证（v3.0 新增，可选兼容旧数据）
    let avg_price: Int?      // 人均消费（元），来自高德 biz_ext.avgprice（v5.0 新增）
    let photo_url: String?   // 店铺封面图 URL，来自高德 photos[0].url（v5.0 新增）

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
    let is_avoided: Bool?           // 是否被用户避雷（v5.0 新增）
    let is_favorited: Bool?         // 是否已收藏（地图接口扩展）
    let group_ids: [String]?        // 所属分组 ID 列表（地图接口扩展）

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
    let note: String?                  // 收藏理由（v5.0 新增）
    let restaurants: Restaurant?       // join 查询的店铺详情
}

// ─────────────────────────────────────────
// 店铺关联视频模型
// ─────────────────────────────────────────
struct RestaurantVideo: Identifiable, Codable {
    let video_id: String
    let author_id: String
    let author_name: String
    let author_avatar_url: String?
    let video_url: String?    // 后端返回的真实抖音分享链接（可能为 nil）
    let created_at: String

    // 用 video_id + created_at 组合作为唯一 id，避免同 video_id 时 SwiftUI 复用错卡片
    var id: String { "\(video_id)_\(created_at)" }

    // 抖音视频链接：优先用后端返回的真实 share_url，否则用 URL Scheme 构造
    var douyinURL: URL? {
        // 优先使用真实分享链接（iesdouyin.com 格式，抖音 App 可识别）
        if let urlStr = video_url, !urlStr.isEmpty, let url = URL(string: urlStr) {
            return url
        }
        // 降级：用 video_id 构造抖音内部 URL Scheme
        return URL(string: "snssdk1128://aweme/detail/\(video_id)")
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


// ─────────────────────────────────────────
// 后台人工复核相关模型（v3.0 新增）
// ─────────────────────────────────────────

// 管理员身份检查响应
struct AdminCheckResponse: Codable {
    let is_admin: Bool
    let user_id: String?
}

// 复核列表中的博主信息（精简版）
struct ReviewAuthorInfo: Codable {
    let name: String?
    let avatar_url: String?
}

// 复核列表中的店铺信息（精简版）
struct ReviewRestaurantInfo: Codable {
    let name: String?
    let verified: Bool?
}

// 单条待复核记录
struct ReviewItem: Identifiable, Codable {
    let id: String              // video_parse_cache.id
    let video_id: String?
    let video_url: String?
    let author_id: String?
    let restaurant_id: String?
    let review_status: String?
    let review_priority: String?  // "P0" 或 "P1"
    let parse_reason: String?
    // 店铺快照字段
    let restaurant_name: String?
    let restaurant_address: String?
    let restaurant_city: String?
    let restaurant_lat: Double?
    let restaurant_lng: Double?
    let restaurant_amap_id: String?
    let restaurant_category: String?
    let restaurant_avg_price: Int?    // 人均消费（v5.0 新增）
    let restaurant_photo_url: String? // 店铺封面图 URL（v5.0 新增）
    let created_at: String?
    let reviewed_at: String?    // 复核时间（已复核记录有值）
    // 关联数据
    let authors: ReviewAuthorInfo?

    // P0：AI 未识别（restaurant_id 为 nil）
    var isP0: Bool { restaurant_id == nil }

    // 抖音视频跳转 URL（与地图卡片 VideoThumbnail 保持一致，用路径格式）
    var douyinAppURL: URL? {
        guard let vid = video_id else { return nil }
        return URL(string: "snssdk1128://aweme/detail/\(vid)")
    }
    var douyinWebURL: URL? {
        guard let vid = video_id else { return nil }
        // 优先用 video_url（真实分享链接），降级用网页链接
        if let urlStr = video_url, !urlStr.isEmpty, let url = URL(string: urlStr) {
            return url
        }
        return URL(string: "https://www.douyin.com/video/\(vid)")
    }
}

// 复核列表响应
struct ReviewListResponse: Codable {
    let items: [ReviewItem]
    let total: Int
    let page: Int
    let page_size: Int
}

// 高德 POI 候选店铺（复核修正时使用）
struct RestaurantCandidate: Identifiable, Codable {
    let amap_id: String
    let name: String
    let address: String
    let city: String
    let latitude: Double
    let longitude: Double
    let category_raw: String    // 高德原始分类，如"餐饮服务;火锅店;火锅店"
    let category_mapped: String // 后端映射后的分类，如"火锅"
    let avg_price: Int?         // 人均消费（元），来自高德 biz_ext.avgprice（v5.0 新增）
    let photo_url: String?      // 店铺封面图 URL，来自高德 photos[0].url（v5.0 新增）

    // Identifiable 使用 amap_id
    var id: String { amap_id }
}

// 候选店铺搜索响应
struct RestaurantCandidatesResponse: Codable {
    let candidates: [RestaurantCandidate]
}

// ─────────────────────────────────────────
// 用户自建推荐店铺相关模型（v4.0 新增）
// ─────────────────────────────────────────

// 用户自建推荐店铺记录（对应 user_created_restaurants 表）
struct UserCreatedRestaurant: Identifiable, Codable {
    let id: String               // user_created_restaurants.id
    let user_id: String
    let restaurant_id: String
    let note: String?            // 用户备注（预留）
    let created_at: String?
    let restaurants: Restaurant? // join 查询的店铺详情
    let is_avoided: Bool?        // 是否被用户避雷（v5.0 新增，地图数据接口返回）
    let is_favorited: Bool?      // 是否已收藏（地图接口扩展）
    let group_ids: [String]?     // 所属分组 ID 列表（地图接口扩展）
}

// 用户自建推荐搜索候选（复用 RestaurantCandidate，字段相同）
// 搜索接口响应
struct UserRestaurantSearchResponse: Codable {
    let results: [RestaurantCandidate]
}

// 用户自建推荐列表响应
struct UserRestaurantsResponse: Codable {
    let restaurants: [UserCreatedRestaurant]
}

// 创建用户自建推荐响应
struct CreateUserRestaurantResponse: Codable {
    let status: String
    let restaurant_id: String?
    let message: String
}

// 地图数据响应（v4.0 更新，新增 user_restaurants 字段）
struct MapRestaurantsResponse: Codable {
    let restaurants: [MapRestaurant]          // 博主推荐
    let user_restaurants: [UserCreatedRestaurant]  // 用户自建推荐
}

// 用户 profile（昵称 + 头像）
struct UserProfile: Codable {
    let user_id: String
    let nickname: String
    let avatar_url: String?  // nil 表示未上传，使用默认占位符
}

// ─────────────────────────────────────────
// 避雷店铺模型（v5.0 新增）
// ─────────────────────────────────────────
struct AvoidedRestaurant: Identifiable, Codable {
    let id: String
    let user_id: String
    let restaurant_id: String
    let created_at: String?
    let restaurants: Restaurant?   // join 查询的店铺详情
}

// ─────────────────────────────────────────
// 博主统计数据（v5.0 新增）
// ─────────────────────────────────────────
struct AuthorStats: Codable {
    let restaurant_count: Int   // 该博主推荐的餐厅总数
    let follower_count: Int     // 平台中关注该博主的用户总数
    let city_count: Int         // 该博主推荐店铺涉及的城市总数
}

// ─────────────────────────────────────────
// 用户自定义分组模型（v5.0 新增）
// ─────────────────────────────────────────
struct RestaurantGroup: Identifiable, Codable {
    let id: String
    let user_id: String
    let name: String
    let created_at: String?
    var restaurant_count: Int?  // 分组内店铺数量（后端 join 查询）
}

// 分组内店铺关联记录
struct GroupRestaurant: Identifiable, Codable {
    let id: String
    let group_id: String
    let restaurant_id: String
    let user_id: String
    let created_at: String?
    let restaurants: Restaurant?  // join 查询的店铺详情
}
