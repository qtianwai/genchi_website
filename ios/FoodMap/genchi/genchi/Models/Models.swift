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
    let tel: String?         // 商家联系电话，来自高德 tel 字段

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
    // v7.1 新增：全平台聚合计数
    let favorite_count: Int?         // 全平台收藏总数
    let avoid_count: Int?           // 全平台避雷总数

    // Identifiable 协议需要
    var mapId: String { id }
}

// ─────────────────────────────────────────
// 解析链接的 API 响应（v10.0 半异步版本）
// 缓存命中直接返回结果；未命中返回 status="parsing" + video_cache_id，前端轮询
// ─────────────────────────────────────────
struct ParseLinkResponse: Codable {
    let status: String           // "cached" / "parsed" / "parsing"（v10.0 新增）
    // 缓存命中时用 restaurant（新格式，单个店铺）
    let restaurant: RestaurantResult?
    // cached 返回时还有 author_id（用于查询解析状态）
    let author_id: String?
    let author: Author?          // parsed/parsing 返回时包含博主信息
    let restaurants: [RestaurantResult]?  // 向后兼容旧格式
    let message: String
    let is_background_running: Bool   // 是否有后台任务正在运行
    let background_progress: BackgroundProgress?
    let video_cache_id: String?  // v10.0 新增：异步解析时用于轮询结果
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
// v10.0 新增：异步解析结果查询响应（前端轮询用）
// ─────────────────────────────────────────
struct ParseResultResponse: Codable {
    let status: String           // "parsing" / "completed" / "failed"
    let restaurant: RestaurantResult?
    let message: String
}

// ─────────────────────────────────────────
// v10.0 新增：用户勘误相关模型
// ─────────────────────────────────────────

// 勘误提交请求
struct CorrectionRequest: Codable {
    let user_id: String
    let restaurant_id: String?
    let video_cache_id: String?
    let correction_type: String   // wrong_restaurant / wrong_address / closed / duplicate / other
    let correction_detail: String?
}

// 勘误提交响应
struct CorrectionResponse: Codable {
    let status: String
    let message: String
}

// 用户勘误记录（复核页面展示用）
struct UserCorrection: Identifiable, Codable {
    let id: String
    let user_id: String
    let correction_type: String
    let correction_detail: String?
    let status: String
    let created_at: String?
}

// ─────────────────────────────────────────
// 用户收藏模型
// ─────────────────────────────────────────
struct Favorite: Identifiable, Codable {
    let id: String
    let user_id: String
    let restaurant_id: String
    var note: String?                  // 收藏理由（v5.0 新增）
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

// 多店铺修正记录（对应 video_parse_cache.corrected_restaurants JSON 数组中的每个元素）
struct CorrectedRestaurant: Codable, Identifiable {
    let restaurant_id: String
    let amap_id: String
    let name: String
    let address: String
    let city: String
    let lat: Double
    let lng: Double
    let category: String

    var id: String { restaurant_id }
}

// 单条待复核记录
struct ReviewItem: Identifiable, Codable {
    let id: String              // video_parse_cache.id
    let video_id: String?
    let video_url: String?
    let author_id: String?
    let restaurant_id: String?
    let status: String?         // "completed" / "failed" / "cold_start" / "pending"（解析状态）
    let review_status: String?
    let review_priority: String?  // "P-1" / "P0" / "P1"
    let parse_reason: String?
    let data_source: String?    // v14.0 新增：数据来源（user_submit/background_scan/cold_start 等）
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
    // v9.0 新增：多店铺修正记录（corrected_restaurants JSON 数组）
    let corrected_restaurants: [CorrectedRestaurant]?
    // v10.0 新增：用户勘误记录
    let user_corrections: [UserCorrection]?

    // P0：AI 未识别（restaurant_id 为 nil）
    var isP0: Bool { restaurant_id == nil }

    // P-1：存在待处理用户勘误，需要最高优先级复核
    var isUserCorrectionPriority: Bool { review_priority == "P-1" }

    // AI 解析失败（status == "failed"），需要人工兜底
    var isFailed: Bool { status == "failed" }

    // v14.0 新增：冷启动录入的记录
    var isColdStart: Bool { data_source == "cold_start" }

    // v14.1 新增：溢出截断的记录（AI 过滤通过但超出 MAX_PARSE_VIDEOS 限制）
    var isOverflow: Bool { data_source == "overflow" }

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
    let tel: String?            // 商家联系电话，来自高德 tel 字段
    let distance_meters: Double? // 与当前用户位置的直线距离（米）
    let is_added: Bool?         // 当前用户是否已添加到“我的推荐”

    // Identifiable 使用 amap_id
    var id: String { amap_id }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceText: String? {
        guard let distance_meters else { return nil }
        if distance_meters < 1000 {
            return "距你 \(Int(distance_meters.rounded()))m"
        }
        return String(format: "距你 %.1fkm", distance_meters / 1000)
    }
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
    // v7.1 新增：全平台聚合计数
    let favorite_count: Int?         // 全平台收藏总数
    let avoid_count: Int?           // 全平台避雷总数
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
struct RestaurantGroup: Identifiable, Codable, Hashable {
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

// ─────────────────────────────────────────
// v6.0 个人专属美食地图 - 数据模型
// ─────────────────────────────────────────
// 注意：RecommendSourceType、MapDisplayItem 定义在 MapViewModel.swift 中，避免重复声明

// 用户地图基本信息
struct UserMapInfo: Codable {
    let user_id: String
    let nickname: String
    let avatar_url: String?
    let is_public: Bool
    let restaurant_count: Int
}

// 地图订阅关系
struct MapSubscription: Codable, Identifiable {
    let id: String
    let target_user_id: String
    let nickname: String
    let avatar_url: String?
    var is_enabled: Bool
    let created_at: String?
}

// 他人地图的店铺项
struct UserMapRestaurantItem: Codable, Identifiable {
    let id: String
    let restaurant_id: String
    let name: String
    let address: String?
    let city: String?
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let photo_url: String?

    // 计算属性：转换为 CoreLocation 坐标
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// 他人地图店铺列表响应
struct UserMapRestaurantsResponse: Codable {
    let is_private: Bool?
    let restaurants: [UserMapRestaurantItem]
    let total: Int
    let has_more: Bool
}


// ─────────────────────────────────────────
// v8.0 饭团系统 - 数据模型
// ─────────────────────────────────────────

// 天气信息
struct WeatherInfo: Codable {
    let text: String        // 天气状况文字（晴/多云/小雨等）
    let temp: String        // 温度（摄氏度）
    let icon: String        // 天气图标代码
    let wind_dir: String    // 风向
    let humidity: String    // 湿度百分比
    let precip: String      // 降水量 mm
    let category: String    // 简化分类：sunny/cloudy/rainy/snowy/hot/cold/normal
}

// 抽卡卡片稀有度
enum CardRarity: String, Codable, CaseIterable {
    case normal = "normal"      // 普通（白/绿）
    case quality = "quality"    // 优质（蓝/紫）
    case rare = "rare"          // 稀有（金）
    case limited = "limited"    // 限定（彩虹）

    // 稀有度对应的显示名称
    var displayName: String {
        switch self {
        case .normal: return "普通"
        case .quality: return "优质"
        case .rare: return "稀有"
        case .limited: return "限定"
        }
    }

    // 稀有度对应的主色调
    var color: String {
        switch self {
        case .normal: return "gray"
        case .quality: return "purple"
        case .rare: return "orange"
        case .limited: return "rainbow"
        }
    }
}

// 抽卡卡片（后端返回的单张卡片数据）
struct GachaCard: Identifiable, Codable {
    let restaurant_id: String
    let name: String
    let address: String?
    let city: String?
    let category: String?
    let avg_price: Int?
    let photo_url: String?
    let latitude: Double?
    let longitude: Double?
    let distance_km: Double?
    let rarity: CardRarity
    let recommend_reason: String
    let source: String          // author / user_created / subscription / platform_popular / amap_nearby
    let authors: [GachaAuthor]? // 推荐该店铺的博主列表

    var id: String { restaurant_id }

    // 距离文本
    var distanceText: String? {
        guard let km = distance_km else { return nil }
        if km < 1 {
            return "\(Int(km * 1000))m"
        }
        return String(format: "%.1fkm", km)
    }

    // 来源文本
    var sourceText: String {
        switch source {
        case "author": return "达人推荐"
        case "user_created": return "我的推荐"
        case "subscription": return "好友推荐"
        case "platform_popular": return "平台热门"
        case "amap_nearby": return "附近发现"
        default: return "推荐"
        }
    }
}

// 抽卡卡片中的博主简要信息
struct GachaAuthor: Identifiable, Codable {
    let id: String
    let name: String
    let avatar_url: String?
}

// 抽卡响应
struct GachaDrawResponse: Codable {
    let session_id: String
    let cards: [GachaCard]
    let remaining: Int          // 今日剩余次数
}

// 抽卡选择响应
struct GachaSelectResponse: Codable {
    let status: String
    let newly_unlocked_achievements: [Achievement]?
}

// 每日抽卡次数
struct GachaRemainingResponse: Codable {
    let used: Int
    let limit: Int
    let remaining: Int
}

// 问答推荐 - 问题
struct QAQuestion: Identifiable, Codable {
    let id: Int
    let text: String
    let options: [String]
}

// 问答推荐 - 问题列表响应
struct QAQuestionsResponse: Codable {
    let questions: [QAQuestion]
}

// 问答推荐 - 推荐结果
struct QARecommendation: Identifiable, Codable {
    let restaurant_id: String
    let name: String
    let address: String?
    let city: String?
    let category: String?
    let avg_price: Int?
    let photo_url: String?
    let distance_km: Double?
    let recommend_reason: String
    let match_score: Double?
    let source: String

    var id: String { restaurant_id }

    var distanceText: String? {
        guard let km = distance_km else { return nil }
        if km < 1 { return "\(Int(km * 1000))m" }
        return String(format: "%.1fkm", km)
    }
}

// 问答推荐响应
struct QAResultResponse: Codable {
    let recommendations: [QARecommendation]
}

// 成就定义
struct Achievement: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let icon_name: String?      // SF Symbol 图标名
    let category: String        // collection / streak / limited
    let condition_type: String
    let condition_value: Int
}

// 用户已解锁成就
struct UserAchievement: Identifiable, Codable {
    let id: String
    let user_id: String
    let achievement_id: String
    let unlocked_at: String?
    let achievements: Achievement?  // join 查询
}

// 打卡记录
struct Checkin: Identifiable, Codable {
    let id: String
    let user_id: String
    let restaurant_id: String
    let rating: Int?
    let comment: String?
    let photo_urls: [String]?
    let created_at: String?
    let restaurants: Restaurant?        // join 查询（用户打卡历史）
    let user_profiles: UserProfile?     // join 查询（店铺打卡列表）
}

// 打卡响应
struct CheckinResponse: Codable {
    let checkin: Checkin
    let newly_unlocked_achievements: [Achievement]?
}

// 收藏留言 AI 摘要
struct ReviewsSummaryResponse: Codable {
    let summary: String
    let note_count: Int
}

// ─────────────────────────────────────────
// v10.10 饭团养成体系
// ─────────────────────────────────────────

// 饭团养成状态
struct FanTuanStatus: Codable, Hashable {
    let satiety: Int              // 饱食度 0-100
    let intimacy: Int             // 亲密度 0-∞
    let intimacy_level: Int       // 亲密度等级 1-5
    let consecutive_login_days: Int // 连续登录天数
    let last_login_date: String?  // 最后登录日期
    let last_pet_date: String?    // 最后摸摸日期
}

// 每日登录签到响应
struct FanTuanLoginResponse: Codable {
    let satiety_change: Int
    let intimacy_change: Int
    let fantuan_status: FanTuanStatus
    let already_logged_in: Bool
}

// 摸摸饭团响应
struct FanTuanPetResponse: Codable {
    let already_pet: Bool
    let satiety_change: Int
    let intimacy_change: Int
    let fantuan_status: FanTuanStatus
}

// ─────────────────────────────────────────
// v14.0 冷启动博主录入相关模型
// ─────────────────────────────────────────

// 冷启动任务信息
struct ColdStartTask: Codable {
    let task_id: String
    let status: String              // pending / running / completed / failed
    let total_videos: Int?
    let food_videos_found: Int?     // 美食视频数
    let new_records_created: Int?   // 新增记录数
    let api_cost: Double?
    let created_at: String?
    let completed_at: String?
    let error_message: String?
}

// 冷启动博主列表项
struct ColdStartAuthor: Identifiable, Codable {
    let id: String              // author.id
    let name: String
    let avatar_url: String?
    let douyin_uid: String?
    let task: ColdStartTask?
}

// 冷启动提交响应
struct ColdStartSubmitResponse: Codable {
    let status: String
    let author: Author?
    let task_id: String?
    let message: String
}

// 冷启动博主列表响应
struct ColdStartAuthorsResponse: Codable {
    let authors: [ColdStartAuthor]
    let total: Int
    let page: Int
    let page_size: Int
}

// 冷启动任务状态响应
struct ColdStartTaskStatusResponse: Codable {
    let status: String
    let total_videos: Int?
    let food_videos_found: Int?
    let new_records_created: Int?
    let api_cost: Double?
    let message: String?
}

// ─── v15.0 用户反馈相关模型 ───

// 用户反馈主体
struct UserFeedback: Identifiable, Codable {
    let id: String
    let user_id: String
    let category: String          // bug_report / feature_request / other
    let content: String
    let image_urls: [String]?
    let device_model: String?
    let ios_version: String?
    let app_version: String?
    let status: String            // pending / in_progress / resolved
    let created_at: String?
    let updated_at: String?
    let reply_count: Int?         // 列表接口返回的回复数

    // 状态中文文本
    var statusText: String {
        switch status {
        case "pending": return "待处理"
        case "in_progress": return "处理中"
        case "resolved": return "已解决"
        default: return status
        }
    }

    // 状态对应颜色
    var statusColor: Color {
        switch status {
        case "pending": return DS.Color.brand
        case "in_progress": return DS.Color.info
        case "resolved": return DS.Color.success
        default: return .secondary
        }
    }

    // 分类中文文本
    var categoryText: String {
        switch category {
        case "bug_report": return "Bug报告"
        case "feature_request": return "功能建议"
        case "other": return "其他"
        default: return category
        }
    }
}

// 管理员回复
struct FeedbackReply: Identifiable, Codable {
    let id: String
    let feedback_id: String
    let admin_user_id: String
    let content: String
    let created_at: String?
}

// 反馈详情响应（反馈 + 回复列表）
struct FeedbackDetailResponse: Codable {
    let feedback: UserFeedback
    let replies: [FeedbackReply]
}

// 反馈列表响应
struct FeedbackListResponse: Codable {
    let items: [UserFeedback]
    let total: Int
    let page: Int
    let page_size: Int
}

// 管理员反馈列表项（含提交者昵称头像）
struct AdminFeedbackItem: Identifiable, Codable {
    let id: String
    let user_id: String
    let category: String
    let content: String
    let image_urls: [String]?
    let status: String
    let created_at: String?
    let reply_count: Int?
    let nickname: String?
    let avatar_url: String?
    let device_model: String?
    let ios_version: String?
    let app_version: String?

    var statusText: String {
        switch status {
        case "pending": return "待处理"
        case "in_progress": return "处理中"
        case "resolved": return "已解决"
        default: return status
        }
    }

    var statusColor: Color {
        switch status {
        case "pending": return DS.Color.brand
        case "in_progress": return DS.Color.info
        case "resolved": return DS.Color.success
        default: return .secondary
        }
    }

    var categoryText: String {
        switch category {
        case "bug_report": return "Bug报告"
        case "feature_request": return "功能建议"
        case "other": return "其他"
        default: return category
        }
    }
}

// 管理员反馈列表响应
struct AdminFeedbackListResponse: Codable {
    let items: [AdminFeedbackItem]
    let total: Int
    let page: Int
    let page_size: Int
}
