# Supabase 数据库操作模块
# 负责所有数据库的读写操作：博主、店铺、用户关注关系等

import os
import json
from datetime import datetime
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()

# 使用 service_role key，后端有完整读写权限
supabase: Client = create_client(
    os.getenv("SUPABASE_URL"),
    os.getenv("SUPABASE_SERVICE_ROLE_KEY"),
)


# ─────────────────────────────────────────
# 博主相关操作
# ─────────────────────────────────────────

def get_author_by_douyin_id(douyin_uid: str) -> dict | None:
    """根据抖音 uid 查询博主是否已入库"""
    result = supabase.table("authors").select("*").eq("douyin_uid", douyin_uid).execute()
    rows = result.data
    return rows[0] if rows else None


def upsert_author(author_data: dict) -> dict:
    """
    插入或更新博主信息
    author_data 字段：douyin_uid, sec_uid, name, avatar_url
    v7.0 新增扩展字段：signature, video_count, total_likes
    （supabase upsert 自动忽略多余字段，无需额外处理）
    """
    result = supabase.table("authors").upsert(
        author_data,
        on_conflict="douyin_uid"  # 以 douyin_uid 为唯一键
    ).execute()
    return result.data[0] if result.data else {}


# ─────────────────────────────────────────
# 店铺相关操作
# ─────────────────────────────────────────

def get_restaurant_by_amap_id(amap_id: str) -> dict | None:
    """根据高德 POI ID 查询店铺是否已入库"""
    result = supabase.table("restaurants").select("*").eq("amap_id", amap_id).execute()
    rows = result.data
    return rows[0] if rows else None


def upsert_restaurant(restaurant_data: dict) -> dict:
    """
    插入或更新店铺信息
    restaurant_data 字段：name, address, city, latitude, longitude, amap_id, category
    """
    result = supabase.table("restaurants").upsert(
        restaurant_data,
        on_conflict="amap_id"
    ).execute()
    return result.data[0] if result.data else {}


def get_restaurants_by_author(author_id: str) -> list[dict]:
    """获取某个博主推荐的所有店铺（含店铺详情和博主信息）"""
    result = (
        supabase.table("author_restaurants")
        .select("*, restaurants(*), authors(*)")
        .eq("author_id", author_id)
        .execute()
    )
    return result.data or []


def link_author_restaurant(author_id: str, restaurant_id: str, video_id: str = "") -> dict:
    """
    建立博主和店铺的关联关系
    一个博主可以推荐多个店铺，一个店铺也可以被多个博主推荐
    同一博主-店铺组合可以有多个视频记录
    """
    data = {
        "author_id": author_id,
        "restaurant_id": restaurant_id,
        "video_id": video_id,
    }
    result = supabase.table("author_restaurants").upsert(
        data,
        on_conflict="author_id,restaurant_id,video_id"
    ).execute()
    return result.data[0] if result.data else {}


# ─────────────────────────────────────────
# 用户关注博主相关操作
# ─────────────────────────────────────────

def get_user_followed_authors(user_id: str) -> list[dict]:
    """获取用户关注的所有博主"""
    result = (
        supabase.table("user_follows")
        .select("*, authors(*)")
        .eq("user_id", user_id)
        .execute()
    )
    return result.data or []


def follow_author(user_id: str, author_id: str) -> dict:
    """用户关注博主"""
    result = supabase.table("user_follows").upsert(
        {"user_id": user_id, "author_id": author_id},
        on_conflict="user_id,author_id"
    ).execute()
    return result.data[0] if result.data else {}


def unfollow_author(user_id: str, author_id: str) -> bool:
    """用户取消关注博主"""
    supabase.table("user_follows").delete().eq("user_id", user_id).eq("author_id", author_id).execute()
    return True


def get_map_restaurants_for_user(user_id: str) -> list[dict]:
    """
    获取用户地图上应该显示的所有店铺
    逻辑：用户关注的博主 → 这些博主推荐的所有店铺
    返回店铺信息 + 推荐该店铺的博主信息（用于地图标记叠加博主头像）
    """
    # 先获取用户关注的博主 ID 列表
    follows = get_user_followed_authors(user_id)
    if not follows:
        return []

    author_ids = [f["author_id"] for f in follows]

    # 查询这些博主推荐的所有店铺
    result = (
        supabase.table("author_restaurants")
        .select("*, restaurants(*), authors(*)")
        .in_("author_id", author_ids)
        .execute()
    )
    return result.data or []


# ─────────────────────────────────────────
# 用户收藏店铺相关操作
# ─────────────────────────────────────────

def get_user_favorites(user_id: str) -> list[dict]:
    """获取用户收藏的所有店铺"""
    result = (
        supabase.table("user_favorites")
        .select("*, restaurants(*)")
        .eq("user_id", user_id)
        .execute()
    )
    return result.data or []


def get_favorite_restaurant_ids(user_id: str) -> set[str]:
    """获取用户已收藏的店铺 ID 集合（用于地图状态标记）"""
    result = (
        supabase.table("user_favorites")
        .select("restaurant_id")
        .eq("user_id", user_id)
        .execute()
    )
    return {row["restaurant_id"] for row in (result.data or []) if row.get("restaurant_id")}


def add_favorite(user_id: str, restaurant_id: str) -> dict:
    """收藏店铺"""
    result = supabase.table("user_favorites").upsert(
        {"user_id": user_id, "restaurant_id": restaurant_id},
        on_conflict="user_id,restaurant_id"
    ).execute()
    return result.data[0] if result.data else {}


def remove_favorite(user_id: str, restaurant_id: str) -> bool:
    """取消收藏"""
    supabase.table("user_favorites").delete().eq("user_id", user_id).eq("restaurant_id", restaurant_id).execute()
    return True


def get_videos_by_restaurant(restaurant_id: str) -> list[dict]:
    """
    获取某个店铺关联的所有视频信息
    返回：[{video_id, author_id, author_name, author_avatar_url, created_at}]
    """
    result = supabase.rpc("get_videos_by_restaurant", {"p_restaurant_id": restaurant_id}).execute()
    return result.data or []


# ─────────────────────────────────────────
# 解析记录相关操作（避免重复解析同一博主）
# ─────────────────────────────────────────

def get_parse_record(author_id: str) -> dict | None:
    """查询某博主是否已经解析过，避免重复调用 AI"""
    result = supabase.table("parse_records").select("*").eq("author_id", author_id).execute()
    rows = result.data
    return rows[0] if rows else None


def save_parse_record(author_id: str, video_count: int) -> dict:
    """记录博主解析完成"""
    result = supabase.table("parse_records").upsert(
        {"author_id": author_id, "video_count": video_count},
        on_conflict="author_id"
    ).execute()
    return result.data[0] if result.data else {}


# ─────────────────────────────────────────
# 视频地址缓存相关操作
# （解决重复解析同一视频的问题）
# ─────────────────────────────────────────

def get_video_cache_by_url(video_url: str) -> dict | None:
    """根据用户提交的原始链接查找视频缓存（精确匹配）"""
    result = supabase.table("video_parse_cache").select("*").eq("video_url", video_url).execute()
    rows = result.data
    return rows[0] if rows else None


def get_video_cache_by_id(video_id: str) -> dict | None:
    """根据视频 ID 查找缓存（用于判断视频是否解析过）"""
    result = supabase.table("video_parse_cache").select("*").eq("video_id", video_id).execute()
    rows = result.data
    return rows[0] if rows else None


def get_video_cache_by_pk(cache_id: str) -> dict | None:
    """v10.0 新增：根据主键 id 查找缓存记录（前端轮询解析结果用）"""
    result = supabase.table("video_parse_cache").select("*").eq("id", cache_id).execute()
    rows = result.data
    return rows[0] if rows else None


def upsert_video_cache(cache_data: dict) -> dict:
    """
    插入或更新视频缓存记录
    cache_data 字段：video_url, video_id, author_id, status, restaurant_*, error_message
    """
    result = supabase.table("video_parse_cache").upsert(
        cache_data,
        on_conflict="video_url"
    ).execute()
    return result.data[0] if result.data else {}


def update_video_cache_restaurant(video_url: str, restaurant_id: str, restaurant_data: dict) -> dict:
    """视频解析成功后，更新缓存中的店铺快照字段"""
    update_data = {
        "status": "completed",
        "restaurant_id": restaurant_id,
        "restaurant_name": restaurant_data.get("name"),
        "restaurant_address": restaurant_data.get("address"),
        "restaurant_city": restaurant_data.get("city"),
        "restaurant_lat": restaurant_data.get("latitude"),
        "restaurant_lng": restaurant_data.get("longitude"),
        "restaurant_amap_id": restaurant_data.get("amap_id"),
        "restaurant_category": restaurant_data.get("category"),
        "updated_at": "now()",
    }
    # 可选字段：解析说明、数据来源、API 成本、算法版本
    if restaurant_data.get("parse_reason") is not None:
        update_data["parse_reason"] = restaurant_data["parse_reason"]
    if restaurant_data.get("data_source") is not None:
        update_data["data_source"] = restaurant_data["data_source"]
    if restaurant_data.get("api_cost") is not None:
        update_data["api_cost"] = restaurant_data["api_cost"]
    if restaurant_data.get("api_cost_note") is not None:
        update_data["api_cost_note"] = restaurant_data["api_cost_note"]
    if restaurant_data.get("parse_algorithm_version") is not None:
        update_data["parse_algorithm_version"] = restaurant_data["parse_algorithm_version"]

    result = supabase.table("video_parse_cache").update(update_data).eq("video_url", video_url).execute()
    return result.data[0] if result.data else {}


def update_video_cache_failed(video_url: str, error_message: str) -> dict:
    """视频解析失败时，更新缓存状态"""
    result = supabase.table("video_parse_cache").update({
        "status": "failed",
        "error_message": error_message,
        "updated_at": "now()",
    }).eq("video_url", video_url).execute()
    return result.data[0] if result.data else {}


def update_video_cache_extra(video_url: str, video_extra: dict) -> dict:
    """
    视频解析完成后，更新 video_extra JSON 字段（v7.0 新增）。
    video_extra 包含：标题、城市、发布时间、互动数据、封面图、标签等。
    """
    result = supabase.table("video_parse_cache").update({
        "video_extra": video_extra,
        "updated_at": "now()",
    }).eq("video_url", video_url).execute()
    return result.data[0] if result.data else {}


def update_video_cache_extra_by_video_id(video_id: str, video_extra: dict) -> dict:
    """
    根据 video_id 更新 video_extra JSON 字段（v7.0 新增）。
    用于后台解析流程中，视频 URL 不确定时按 video_id 更新。
    """
    result = supabase.table("video_parse_cache").update({
        "video_extra": video_extra,
        "updated_at": "now()",
    }).eq("video_id", video_id).execute()
    return result.data[0] if result.data else {}


# ─────────────────────────────────────────
# 博主后台解析任务相关操作
# （管理博主历史视频的异步解析任务）
# ─────────────────────────────────────────

def create_bg_task(author_id: str, task_type: str = "full_scan") -> dict:
    """创建博主后台解析任务"""
    result = supabase.table("author_background_tasks").insert({
        "author_id": author_id,
        "task_type": task_type,
        "status": "pending",
    }).execute()
    return result.data[0] if result.data else {}


def update_bg_task_started(task_id: str) -> dict:
    """任务开始执行"""
    result = supabase.table("author_background_tasks").update({
        "status": "running",
        "started_at": "now()",
    }).eq("id", task_id).execute()
    return result.data[0] if result.data else {}


def update_bg_task_progress(task_id: str, processed: int, new_found: int = 0) -> dict:
    """更新任务进度"""
    result = supabase.table("author_background_tasks").update({
        "processed_videos": processed,
        "new_restaurants_found": new_found,
    }).eq("id", task_id).execute()
    return result.data[0] if result.data else {}


def complete_bg_task(task_id: str, new_restaurants_count: int = 0) -> dict:
    """任务完成"""
    result = supabase.table("author_background_tasks").update({
        "status": "completed",
        "processed_videos": 0,  # completed 时 processed_videos 意义不大
        "new_restaurants_found": new_restaurants_count,
        "completed_at": "now()",
    }).eq("id", task_id).execute()
    return result.data[0] if result.data else {}


def fail_bg_task(task_id: str, error_message: str) -> dict:
    """任务失败"""
    result = supabase.table("author_background_tasks").update({
        "status": "failed",
        "error_message": error_message,
        "completed_at": "now()",
    }).eq("id", task_id).execute()
    return result.data[0] if result.data else {}


def get_latest_bg_task(author_id: str) -> dict | None:
    """获取博主最新的后台任务（用于查询进度）"""
    result = (
        supabase.table("author_background_tasks")
        .select("*")
        .eq("author_id", author_id)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    rows = result.data
    return rows[0] if rows else None


def get_latest_bg_task_within_hours(author_id: str, hours: int = 24) -> dict | None:
    """
    获取博主最近 N 小时内创建的后台任务（用于冷却期判断，优化 3.3）。

    如果存在未完成或最近创建的任务，说明在冷却期内，应跳过扫描。
    """
    from datetime import datetime, timedelta, timezone

    # 计算截止时间
    cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)

    result = (
        supabase.table("author_background_tasks")
        .select("*")
        .eq("author_id", author_id)
        .gte("created_at", cutoff_time.isoformat())  # 大于等于截止时间
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    rows = result.data
    return rows[0] if rows else None


def is_author_in_cool_down(author_id: str, hours: int = 24) -> bool:
    """
    检查博主是否在扫描冷却期内（优化 3.3）。

    返回 True 表示在冷却期内（应跳过扫描），返回 False 表示可以扫描。
    """
    recent_task = get_latest_bg_task_within_hours(author_id, hours)
    if not recent_task:
        return False

    # 如果最近任务是 pending 或 running，说明有任务正在执行或等待执行
    # 如果最近任务是 completed 或 failed，看创建时间
    status = recent_task.get("status", "")
    if status in ("pending", "running"):
        return True

    # completed 或 failed 的任务，检查创建时间是否在冷却期内
    created_at = recent_task.get("created_at", "")
    if not created_at:
        return False

    from datetime import datetime, timedelta, timezone
    try:
        # 解析时间（处理 ISO 格式）
        if isinstance(created_at, str):
            # 尝试解析 ISO 格式时间
            if created_at.endswith("Z"):
                created_at = created_at[:-1] + "+00:00"
            task_time = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        else:
            task_time = created_at

        cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)
        return task_time > cutoff_time
    except Exception:
        # 解析失败，保守处理为不在冷却期内
        return False


# ─────────────────────────────────────────
# 博主自动更新检测相关操作（v2.4 新增）
# ─────────────────────────────────────────

def get_author_by_id(author_id: str) -> dict | None:
    """根据 author_id 获取博主信息"""
    result = supabase.table("authors").select("*").eq("id", author_id).execute()
    rows = result.data
    return rows[0] if rows else None


def get_authors_with_auto_update_enabled(limit: int = 50) -> list[dict]:
    """
    获取所有启用了自动更新检测的博主

    用于定时任务，遍历所有需要检测的博主
    """
    result = (
        supabase.table("authors")
        .select("*")
        .eq("auto_update_enabled", True)
        .not_is("sec_uid", "null")  # 必须有 sec_uid 才能获取视频列表
        .limit(limit)
        .execute()
    )
    return result.data or []


def update_author_auto_check_time(author_id: str) -> dict:
    """更新博主的上次自动检测时间"""
    result = supabase.table("authors").update({
        "last_update_check": "now()",
    }).eq("id", author_id).execute()
    return result.data[0] if result.data else {}


def increment_no_new_food_video_days(author_id: str) -> dict:
    """增加博主连续无新美食视频天数"""
    # 先获取当前值
    author = get_author_by_id(author_id)
    if author:
        current_days = author.get("no_new_food_video_days", 0)
        result = supabase.table("authors").update({
            "no_new_food_video_days": current_days + 1,
        }).eq("id", author_id).execute()
        return result.data[0] if result.data else {}
    return {}


def reset_no_new_food_video_days(author_id: str) -> dict:
    """重置博主连续无新美食视频天数为 0"""
    result = supabase.table("authors").update({
        "no_new_food_video_days": 0,
    }).eq("id", author_id).execute()
    return result.data[0] if result.data else {}


def disable_author_auto_update(author_id: str) -> dict:
    """关闭博主的自动更新检测"""
    result = supabase.table("authors").update({
        "auto_update_enabled": False,
    }).eq("id", author_id).execute()
    return result.data[0] if result.data else {}


def enable_author_auto_update(author_id: str) -> dict:
    """
    启用博主的自动更新检测

    用于重新激活：用户手动提交该博主的新视频链接时触发
    """
    result = supabase.table("authors").update({
        "auto_update_enabled": True,
        "no_new_food_video_days": 0,  # 重置天数
    }).eq("id", author_id).execute()
    return result.data[0] if result.data else {}


# ─────────────────────────────────────────
# 后台人工复核相关操作（v3.0 新增）
# ─────────────────────────────────────────

def get_review_list(page: int = 1, page_size: int = 20, tab: str = "pending") -> dict:
    """
    获取复核列表。
    tab='pending'：待复核（review_status IN pending/skipped），P0 优先，同级按 created_at 倒序。
                   包含 completed 和 failed 状态的记录（AI 解析失败也需要人工兜底）。
    tab='reviewed'：已复核（review_status IN approved/corrected/confirmed），按 reviewed_at 倒序。
    返回 {items, total, page, page_size}
    """
    offset = (page - 1) * page_size

    select_fields = (
        "id, video_id, video_url, author_id, restaurant_id, status, review_status, "
        "parse_reason, restaurant_name, restaurant_address, restaurant_city, "
        "restaurant_lat, restaurant_lng, restaurant_amap_id, restaurant_category, "
        "restaurant_photo_url, restaurant_avg_price, "  # 复核页店铺封面图和均价快照
        "corrected_restaurants, "  # v9.0 新增：多店铺修正 JSON 数组
        "video_extra, "  # v7.0 新增：视频扩展信息 JSON
        "reviewed_at, created_at, authors(name, avatar_url)"
    )

    if tab == "reviewed":
        # 已复核：approved / corrected / confirmed，按 reviewed_at 倒序
        result = (
            supabase.table("video_parse_cache")
            .select(select_fields, count="exact")
            .in_("review_status", ["approved", "corrected", "confirmed"])
            .in_("status", ["completed", "failed"])
            .order("reviewed_at", desc=True)
            .range(offset, offset + page_size - 1)
            .execute()
        )
    else:
        # 待复核：pending / skipped
        # 优先级：
        # 1. 有待处理用户勘误的记录（最高优先级）
        # 2. P0：restaurant_id IS NULL
        # 3. P1：已有识别结果
        # 同优先级内按最新相关时间倒序。
        result = (
            supabase.table("video_parse_cache")
            .select(select_fields, count="exact")
            .in_("review_status", ["pending", "skipped"])
            .in_("status", ["completed", "failed"])
            .execute()
        )

    items = result.data or []
    total = result.count or 0

    if tab != "reviewed":
        pending_cache_times, pending_restaurant_times = get_pending_correction_targets()

        for item in items:
            cache_id = item.get("id")
            restaurant_id = item.get("restaurant_id")
            correction_ts = max(
                pending_cache_times.get(cache_id, 0.0),
                pending_restaurant_times.get(restaurant_id, 0.0),
            )
            has_pending_correction = correction_ts > 0

            item["has_pending_user_corrections"] = has_pending_correction
            item["_priority_rank"] = 0 if has_pending_correction else (1 if restaurant_id is None else 2)
            item["_sort_ts"] = correction_ts or _iso_to_timestamp(item.get("created_at"))

            if has_pending_correction:
                item["review_priority"] = "P-1"
            else:
                item["review_priority"] = "P0" if restaurant_id is None else "P1"

        items.sort(key=lambda item: (item["_priority_rank"], -item["_sort_ts"]))
        items = items[offset: offset + page_size]

        for item in items:
            item.pop("_priority_rank", None)
            item.pop("_sort_ts", None)
    else:
        # 为每条记录计算优先级标签（已复核记录也保留，方便前端展示）
        for item in items:
            item["review_priority"] = "P0" if item.get("restaurant_id") is None else "P1"

    return {"items": items, "total": total, "page": page, "page_size": page_size}


def get_video_cache_by_cache_id(cache_id: str) -> dict | None:
    """根据 cache id 查询视频缓存记录"""
    result = supabase.table("video_parse_cache").select("*").eq("id", cache_id).execute()
    rows = result.data
    return rows[0] if rows else None


def admin_confirm_correct(cache_id: str, admin_user_id: str) -> bool:
    """
    确认 AI 识别结果正确：
    1. 更新 restaurants.verified = true
    2. 同步更新 video_parse_cache 快照字段
    3. 设置 review_status = 'approved'
    """
    # 获取缓存记录
    cache = get_video_cache_by_cache_id(cache_id)
    if not cache:
        return False

    restaurant_id = cache.get("restaurant_id")
    if not restaurant_id:
        return False

    # 更新 restaurants 表
    supabase.table("restaurants").update({
        "verified": True,
        "verified_at": "now()",
    }).eq("id", restaurant_id).execute()

    # 获取最新 restaurant 数据（用于同步快照）
    r_result = supabase.table("restaurants").select("*").eq("id", restaurant_id).execute()
    restaurant = r_result.data[0] if r_result.data else {}

    # 更新 video_parse_cache
    supabase.table("video_parse_cache").update({
        "restaurant_name": restaurant.get("name", cache.get("restaurant_name")),
        "restaurant_address": restaurant.get("address", cache.get("restaurant_address")),
        "restaurant_city": restaurant.get("city", cache.get("restaurant_city")),
        "restaurant_lat": restaurant.get("latitude", cache.get("restaurant_lat")),
        "restaurant_lng": restaurant.get("longitude", cache.get("restaurant_lng")),
        "restaurant_amap_id": restaurant.get("amap_id", cache.get("restaurant_amap_id")),
        "restaurant_category": restaurant.get("category", cache.get("restaurant_category")),
        "review_status": "approved",
        "reviewed_by": admin_user_id,
        "reviewed_at": "now()",
        "updated_at": "now()",
    }).eq("id", cache_id).execute()

    mark_user_corrections_reviewed(
        reviewed_by=admin_user_id,
        restaurant_id=restaurant_id,
        video_cache_id=cache_id,
        review_note="管理员确认原识别结果正确",
    )

    return True


def admin_confirm_empty(cache_id: str, admin_user_id: str) -> bool:
    """
    确认该视频无店铺，更新 review_status = 'confirmed'。
    若该记录之前关联了店铺，检查该店铺是否还有其他已验证视频关联；
    若没有，则将 restaurants.verified 回滚为 false。
    """
    # 获取缓存记录，检查是否有旧的关联店铺
    cache = get_video_cache_by_cache_id(cache_id)
    if cache:
        old_restaurant_id = cache.get("restaurant_id")
        if old_restaurant_id:
            # 检查该店铺是否还有其他已复核（approved/corrected）的视频关联
            other_verified = (
                supabase.table("video_parse_cache")
                .select("id", count="exact")
                .eq("restaurant_id", old_restaurant_id)
                .in_("review_status", ["approved", "corrected"])
                .neq("id", cache_id)  # 排除当前记录
                .execute()
            )
            if (other_verified.count or 0) == 0:
                # 没有其他已验证关联，回滚 verified 状态
                supabase.table("restaurants").update({
                    "verified": False,
                    "verified_at": None,
                }).eq("id", old_restaurant_id).execute()

    # 删除 author_restaurants 里该视频的关联，避免地图继续显示
    if cache:
        author_id = cache.get("author_id")
        video_id = cache.get("video_id", "")
        if author_id and video_id:
            supabase.table("author_restaurants").delete().eq(
                "author_id", author_id
            ).eq("video_id", video_id).execute()

    supabase.table("video_parse_cache").update({
        "review_status": "confirmed",
        "restaurant_id": None,   # 清空关联店铺
        "reviewed_by": admin_user_id,
        "reviewed_at": "now()",
        "updated_at": "now()",
    }).eq("id", cache_id).execute()

    mark_user_corrections_reviewed(
        reviewed_by=admin_user_id,
        restaurant_id=cache.get("restaurant_id") if cache else None,
        video_cache_id=cache_id,
        review_note="管理员确认该视频无关联店铺",
    )

    return True


def admin_correct_restaurant(
    cache_id: str,
    admin_user_id: str,
    amap_id: str,
    name: str,
    address: str,
    city: str,
    latitude: float,
    longitude: float,
    category: str,
    avg_price: int | None = None,
    photo_url: str | None = None,
    tel: str | None = None,
) -> bool:
    """
    人工修正店铺：
    1. upsert restaurants（以 amap_id 为唯一键，设 verified=true）
    2. 更新 author_restaurants 关联（新建新关联）
    3. 更新 video_parse_cache 所有快照字段，review_status = 'corrected'
    """
    # 获取缓存记录
    cache = get_video_cache_by_cache_id(cache_id)
    if not cache:
        return False

    # upsert restaurants（含均价和封面图）
    restaurant_data = {
        "name": name,
        "address": address,
        "city": city,
        "latitude": latitude,
        "longitude": longitude,
        "amap_id": amap_id,
        "category": category,
        "verified": True,
        "verified_at": "now()",
    }
    if avg_price is not None:
        restaurant_data["avg_price"] = avg_price
    if photo_url:
        restaurant_data["photo_url"] = photo_url
    if tel:
        restaurant_data["tel"] = tel
    r_result = supabase.table("restaurants").upsert(
        restaurant_data, on_conflict="amap_id"
    ).execute()

    if not r_result.data:
        return False

    restaurant_id = r_result.data[0]["id"]

    # 更新 author_restaurants 关联
    # 先删除该视频的旧关联（旧 restaurant_id 不同，upsert 不会覆盖，必须先删再插）
    author_id = cache.get("author_id")
    video_id = cache.get("video_id", "")
    if author_id:
        if video_id:
            supabase.table("author_restaurants").delete().eq(
                "author_id", author_id
            ).eq("video_id", video_id).execute()
        supabase.table("author_restaurants").insert({
            "author_id": author_id,
            "restaurant_id": restaurant_id,
            "video_id": video_id,
        }).execute()

    # 更新 video_parse_cache（人工修正后 status 统一设为 completed，即使原来是 failed）
    cache_update = {
        "status": "completed",
        "restaurant_id": restaurant_id,
        "restaurant_name": name,
        "restaurant_address": address,
        "restaurant_city": city,
        "restaurant_lat": latitude,
        "restaurant_lng": longitude,
        "restaurant_amap_id": amap_id,
        "restaurant_category": category,
        "review_status": "corrected",
        "reviewed_by": admin_user_id,
        "reviewed_at": "now()",
        "updated_at": "now()",
    }
    if avg_price is not None:
        cache_update["restaurant_avg_price"] = avg_price
    if photo_url:
        cache_update["restaurant_photo_url"] = photo_url
    supabase.table("video_parse_cache").update(cache_update).eq("id", cache_id).execute()

    mark_user_corrections_reviewed(
        reviewed_by=admin_user_id,
        restaurant_id=cache.get("restaurant_id"),
        video_cache_id=cache_id,
        review_note=f"管理员已修正为「{name}」",
    )

    return True


def admin_correct_restaurants_multi(
    cache_id: str,
    admin_user_id: str,
    restaurants: list[dict],
) -> bool:
    """
    多店铺人工修正：一个视频关联多家店铺。
    restaurants 列表中每个元素包含：amap_id, name, address, city, latitude, longitude, category

    处理逻辑：
    1. 遍历 restaurants，逐个 upsert restaurants 表（amap_id 唯一键，verified=true）
    2. 删除该视频的所有旧 author_restaurants 关联
    3. 为每个店铺插入新的 author_restaurants 关联
    4. 更新 video_parse_cache：restaurant_id 存第一个店铺，corrected_restaurants 存完整 JSON
    """
    if not restaurants:
        return False

    # 获取缓存记录
    cache = get_video_cache_by_cache_id(cache_id)
    if not cache:
        return False

    author_id = cache.get("author_id")
    video_id = cache.get("video_id", "")

    # 逐个 upsert restaurants 表，收集 restaurant_id
    restaurant_ids = []
    corrected_list = []
    for r in restaurants:
        restaurant_data = {
            "name": r["name"],
            "address": r["address"],
            "city": r["city"],
            "latitude": r["latitude"],
            "longitude": r["longitude"],
            "amap_id": r["amap_id"],
            "category": r["category"],
            "verified": True,
            "verified_at": "now()",
        }
        if r.get("avg_price") is not None:
            restaurant_data["avg_price"] = r["avg_price"]
        if r.get("photo_url"):
            restaurant_data["photo_url"] = r["photo_url"]
        if r.get("tel"):
            restaurant_data["tel"] = r["tel"]
        r_result = supabase.table("restaurants").upsert(
            restaurant_data, on_conflict="amap_id"
        ).execute()

        if not r_result.data:
            return False

        rid = r_result.data[0]["id"]
        restaurant_ids.append(rid)
        corrected_list.append({
            "restaurant_id": rid,
            "amap_id": r["amap_id"],
            "name": r["name"],
            "address": r["address"],
            "city": r["city"],
            "lat": r["latitude"],
            "lng": r["longitude"],
            "category": r["category"],
        })

    # 删除该视频的所有旧 author_restaurants 关联
    if author_id and video_id:
        supabase.table("author_restaurants").delete().eq(
            "author_id", author_id
        ).eq("video_id", video_id).execute()

    # 为每个店铺插入新的 author_restaurants 关联
    if author_id:
        for rid in restaurant_ids:
            supabase.table("author_restaurants").insert({
                "author_id": author_id,
                "restaurant_id": rid,
                "video_id": video_id,
            }).execute()

    # 更新 video_parse_cache：第一个店铺作为主显示，corrected_restaurants 存完整数组
    first = restaurants[0]
    first_id = restaurant_ids[0]
    cache_update = {
        "status": "completed",
        "restaurant_id": first_id,
        "restaurant_name": first["name"],
        "restaurant_address": first["address"],
        "restaurant_city": first["city"],
        "restaurant_lat": first["latitude"],
        "restaurant_lng": first["longitude"],
        "restaurant_amap_id": first["amap_id"],
        "restaurant_category": first["category"],
        "corrected_restaurants": corrected_list,
        "review_status": "corrected",
        "reviewed_by": admin_user_id,
        "reviewed_at": "now()",
        "updated_at": "now()",
    }
    if first.get("avg_price") is not None:
        cache_update["restaurant_avg_price"] = first["avg_price"]
    if first.get("photo_url"):
        cache_update["restaurant_photo_url"] = first["photo_url"]
    supabase.table("video_parse_cache").update(cache_update).eq("id", cache_id).execute()

    mark_user_corrections_reviewed(
        reviewed_by=admin_user_id,
        restaurant_id=cache.get("restaurant_id"),
        video_cache_id=cache_id,
        review_note=f"管理员已修正为 {len(restaurants)} 家关联店铺",
    )

    return True


def admin_skip(cache_id: str, admin_user_id: str) -> bool:
    """跳过复核，更新 review_status = 'skipped'"""
    supabase.table("video_parse_cache").update({
        "review_status": "skipped",
        "reviewed_by": admin_user_id,
        "reviewed_at": "now()",
        "updated_at": "now()",
    }).eq("id", cache_id).execute()
    return True


def is_admin_user(user_id: str) -> bool:
    """检查用户是否为管理员"""
    result = supabase.table("admin_users").select("user_id").eq("user_id", user_id).execute()
    return bool(result.data)


# ─────────────────────────────────────────
# 用户自建推荐店铺相关操作（v4.0 新增）
# ─────────────────────────────────────────

def get_user_created_restaurants(user_id: str) -> list[dict]:
    """获取用户自建的所有推荐店铺（含店铺详情）"""
    result = (
        supabase.table("user_created_restaurants")
        .select("*, restaurants(*)")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


def get_user_created_restaurant_amap_ids(user_id: str) -> set[str]:
    """获取用户已添加店铺的高德 POI ID 集合（用于搜索结果去重提示）"""
    rows = get_user_created_restaurants(user_id)
    amap_ids: set[str] = set()
    for row in rows:
        restaurant = row.get("restaurants") or {}
        amap_id = restaurant.get("amap_id")
        if amap_id:
            amap_ids.add(amap_id)
    return amap_ids


def has_user_restaurant(user_id: str, restaurant_id: str) -> bool:
    """检查用户是否已添加该店铺到我的推荐"""
    result = (
        supabase.table("user_created_restaurants")
        .select("id")
        .eq("user_id", user_id)
        .eq("restaurant_id", restaurant_id)
        .limit(1)
        .execute()
    )
    return bool(result.data)


def add_user_restaurant(user_id: str, restaurant_id: str, note: str = "") -> dict:
    """
    添加用户自建推荐店铺
    若该用户已添加过同一家店（unique 约束），则直接返回已有记录
    同时清除该店铺的删除标记（user_deleted_restaurants），确保重新添加后地图能正常显示
    """
    # 清除删除标记，确保重新添加的店铺不会被地图过滤
    supabase.table("user_deleted_restaurants").delete().eq(
        "user_id", user_id
    ).eq("restaurant_id", restaurant_id).execute()

    data = {"user_id": user_id, "restaurant_id": restaurant_id}
    if note:
        data["note"] = note
    result = supabase.table("user_created_restaurants").upsert(
        data,
        on_conflict="user_id,restaurant_id"
    ).execute()
    return result.data[0] if result.data else {}


def remove_user_restaurant(user_id: str, restaurant_id: str) -> bool:
    """删除用户自建推荐店铺（只删关联记录，不删 restaurants 表）"""
    supabase.table("user_created_restaurants").delete().eq(
        "user_id", user_id
    ).eq("restaurant_id", restaurant_id).execute()
    return True


# ─────────────────────────────────────────
# 避雷店铺相关操作（v5.0 新增）
# ─────────────────────────────────────────

def avoid_restaurant(user_id: str, restaurant_id: str) -> dict:
    """避雷店铺"""
    result = supabase.table("user_blocked_restaurants").upsert(
        {"user_id": user_id, "restaurant_id": restaurant_id},
        on_conflict="user_id,restaurant_id"
    ).execute()
    return result.data[0] if result.data else {}


def unavoid_restaurant(user_id: str, restaurant_id: str) -> bool:
    """取消避雷"""
    supabase.table("user_blocked_restaurants").delete().eq(
        "user_id", user_id
    ).eq("restaurant_id", restaurant_id).execute()
    return True


def get_avoided_restaurants(user_id: str) -> list[dict]:
    """获取用户避雷的所有店铺"""
    result = (
        supabase.table("user_blocked_restaurants")
        .select("*, restaurants(*)")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


def get_avoided_restaurant_ids(user_id: str) -> list[str]:
    """获取用户避雷的店铺 ID 列表（轻量查询，用于地图标记）"""
    result = (
        supabase.table("user_blocked_restaurants")
        .select("restaurant_id")
        .eq("user_id", user_id)
        .execute()
    )
    return [r["restaurant_id"] for r in (result.data or [])]


# ─────────────────────────────────────────
# 删除店铺相关操作（v5.0 新增，全局隐藏）
# ─────────────────────────────────────────

def delete_restaurant_for_user(user_id: str, restaurant_id: str) -> dict:
    """用户删除店铺（全局隐藏，不影响其他用户）"""
    result = supabase.table("user_deleted_restaurants").upsert(
        {"user_id": user_id, "restaurant_id": restaurant_id},
        on_conflict="user_id,restaurant_id"
    ).execute()
    return result.data[0] if result.data else {}


def get_deleted_restaurant_ids(user_id: str) -> list[str]:
    """获取用户已删除的店铺 ID 列表（用于地图过滤）"""
    result = (
        supabase.table("user_deleted_restaurants")
        .select("restaurant_id")
        .eq("user_id", user_id)
        .execute()
    )
    return [r["restaurant_id"] for r in (result.data or [])]


# ─────────────────────────────────────────
# 收藏理由相关操作（v5.0 新增）
# ─────────────────────────────────────────

def update_favorite_note(user_id: str, restaurant_id: str, note: str) -> dict:
    """更新收藏理由（user_favorites 表的 note 字段）"""
    result = (
        supabase.table("user_favorites")
        .update({"note": note})
        .eq("user_id", user_id)
        .eq("restaurant_id", restaurant_id)
        .execute()
    )
    return result.data[0] if result.data else {}


# ─────────────────────────────────────────
# 用户自定义分组相关操作（v5.0 新增）
# ─────────────────────────────────────────

def get_user_groups(user_id: str) -> list[dict]:
    """获取用户的所有自定义分组（含每组店铺数量）"""
    # 先查分组
    groups_result = (
        supabase.table("user_restaurant_groups")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=False)
        .execute()
    )
    groups = groups_result.data or []

    # 查每组的店铺数量
    for group in groups:
        count_result = (
            supabase.table("user_group_restaurants")
            .select("id", count="exact")
            .eq("group_id", group["id"])
            .execute()
        )
        group["restaurant_count"] = count_result.count or 0

    return groups


def create_user_group(user_id: str, name: str) -> dict:
    """创建用户自定义分组"""
    result = supabase.table("user_restaurant_groups").insert({
        "user_id": user_id,
        "name": name,
    }).execute()
    return result.data[0] if result.data else {}


def delete_user_group(user_id: str, group_id: str) -> bool:
    """删除用户自定义分组（级联删除分组内的店铺关联）"""
    supabase.table("user_restaurant_groups").delete().eq(
        "id", group_id
    ).eq("user_id", user_id).execute()
    return True


def add_restaurant_to_group(user_id: str, group_id: str, restaurant_id: str) -> dict:
    """添加店铺到分组"""
    result = supabase.table("user_group_restaurants").upsert(
        {"group_id": group_id, "restaurant_id": restaurant_id, "user_id": user_id},
        on_conflict="group_id,restaurant_id"
    ).execute()
    return result.data[0] if result.data else {}


def remove_restaurant_from_group(user_id: str, group_id: str, restaurant_id: str) -> bool:
    """从分组中移除店铺"""
    supabase.table("user_group_restaurants").delete().eq(
        "group_id", group_id
    ).eq("restaurant_id", restaurant_id).eq("user_id", user_id).execute()
    return True


def get_group_restaurants(group_id: str, user_id: str) -> list[dict]:
    """获取分组内的所有店铺"""
    result = (
        supabase.table("user_group_restaurants")
        .select("*, restaurants(*)")
        .eq("group_id", group_id)
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


def get_group_ids_by_restaurant(user_id: str) -> dict[str, list[str]]:
    """
    获取用户维度下「店铺 -> 分组 ID 列表」映射。
    用于地图分组筛选，不额外请求分组明细接口。
    """
    result = (
        supabase.table("user_group_restaurants")
        .select("restaurant_id, group_id")
        .eq("user_id", user_id)
        .execute()
    )
    mapping: dict[str, list[str]] = {}
    for row in (result.data or []):
        rid = row.get("restaurant_id")
        gid = row.get("group_id")
        if not rid or not gid:
            continue
        mapping.setdefault(rid, []).append(gid)
    return mapping


# ─────────────────────────────────────────
# 博主统计相关操作（v5.0 新增）
# ─────────────────────────────────────────

def get_author_stats(author_id: str) -> dict:
    """
    获取博主统计数据：
    - restaurant_count: 该博主推荐的餐厅总数
    - follower_count: 平台中关注该博主的用户总数
    - city_count: 该博主推荐店铺涉及的城市总数
    """
    # 餐厅数
    r_result = (
        supabase.table("author_restaurants")
        .select("restaurant_id", count="exact")
        .eq("author_id", author_id)
        .execute()
    )
    restaurant_count = r_result.count or 0

    # 粉丝数（平台内关注该博主的用户数）
    f_result = (
        supabase.table("user_follows")
        .select("user_id", count="exact")
        .eq("author_id", author_id)
        .execute()
    )
    follower_count = f_result.count or 0

    # 城市数（去重统计该博主推荐店铺的城市）
    city_result = (
        supabase.table("author_restaurants")
        .select("restaurants(city)")
        .eq("author_id", author_id)
        .execute()
    )
    cities = set()
    for row in (city_result.data or []):
        r = row.get("restaurants")
        if r and r.get("city"):
            cities.add(r["city"])
    city_count = len(cities)

    return {
        "restaurant_count": restaurant_count,
        "follower_count": follower_count,
        "city_count": city_count,
    }


def get_map_restaurants_for_user(user_id: str) -> dict:
    """
    获取用户地图上应该显示的所有店铺，包含两类：
    1. author_restaurants：用户关注的博主推荐的店铺
    2. user_created_restaurants：用户自建的推荐店铺

    v5.0 新增：
    - 过滤用户已删除的店铺（不在地图上显示）
    - 标记用户已避雷的店铺（is_avoided = true）

    返回 {"restaurants": [...], "user_restaurants": [...]}
    """
    # 获取用户已删除和已避雷的店铺 ID
    deleted_ids = get_deleted_restaurant_ids(user_id)
    avoided_ids = set(get_avoided_restaurant_ids(user_id))
    favorited_ids = get_favorite_restaurant_ids(user_id)
    group_map = get_group_ids_by_restaurant(user_id)

    # 博主推荐：用户关注的博主 → 这些博主推荐的所有店铺
    follows = get_user_followed_authors(user_id)
    author_data = []
    if follows:
        author_ids = [f["author_id"] for f in follows]
        result = (
            supabase.table("author_restaurants")
            .select("*, restaurants(*), authors(*)")
            .in_("author_id", author_ids)
            .execute()
        )
        raw_data = result.data or []
        # 过滤已删除店铺，标记已避雷店铺
        for item in raw_data:
            rid = item.get("restaurant_id")
            if rid in deleted_ids:
                continue
            item["is_avoided"] = rid in avoided_ids
            item["is_favorited"] = rid in favorited_ids
            item["group_ids"] = group_map.get(rid, [])
            author_data.append(item)

    # 用户自建推荐
    raw_user_data = get_user_created_restaurants(user_id)
    user_data = []
    for item in raw_user_data:
        rid = item.get("restaurant_id")
        if rid in deleted_ids:
            continue
        item["is_avoided"] = rid in avoided_ids
        item["is_favorited"] = rid in favorited_ids
        item["group_ids"] = group_map.get(rid, [])
        user_data.append(item)

    # 批量聚合全平台收藏/避雷计数
    # 收集所有 restaurant_id，两次 in_ 查询避免 N+1
    all_restaurant_ids = (
        [r["restaurant_id"] for r in author_data if r.get("restaurant_id")]
        + [r["restaurant_id"] for r in user_data if r.get("restaurant_id")]
    )
    if all_restaurant_ids:
        # 全平台收藏计数（所有用户的收藏总数）
        fav_result = (
            supabase.table("user_favorites")
            .select("restaurant_id")
            .in_("restaurant_id", all_restaurant_ids)
            .execute()
        )
        fav_counts: dict[str, int] = {}
        for row in (fav_result.data or []):
            rid = row.get("restaurant_id")
            fav_counts[rid] = fav_counts.get(rid, 0) + 1

        # 全平台避雷计数（所有用户的避雷总数）
        blk_result = (
            supabase.table("user_blocked_restaurants")
            .select("restaurant_id")
            .in_("restaurant_id", all_restaurant_ids)
            .execute()
        )
        blk_counts: dict[str, int] = {}
        for row in (blk_result.data or []):
            rid = row.get("restaurant_id")
            blk_counts[rid] = blk_counts.get(rid, 0) + 1

        # 写入 author_data 和 user_data
        for item in author_data:
            rid = item.get("restaurant_id")
            item["favorite_count"] = fav_counts.get(rid, 0)
            item["avoid_count"] = blk_counts.get(rid, 0)
        for item in user_data:
            rid = item.get("restaurant_id")
            item["favorite_count"] = fav_counts.get(rid, 0)
            item["avoid_count"] = blk_counts.get(rid, 0)
    else:
        for item in author_data:
            item["favorite_count"] = 0
            item["avoid_count"] = 0
        for item in user_data:
            item["favorite_count"] = 0
            item["avoid_count"] = 0

    return {"restaurants": author_data, "user_restaurants": user_data}


# ─────────────────────────────────────────
# 用户 Profile 相关操作
# ─────────────────────────────────────────

def get_user_profile(user_id: str) -> dict | None:
    """获取用户 profile，不存在返回 None"""
    result = supabase.table("user_profiles").select("*").eq("user_id", user_id).execute()
    return result.data[0] if result.data else None


def upsert_user_profile(user_id: str, nickname: str = None, avatar_url: str = None) -> dict:
    """创建或更新用户 profile（upsert），只更新传入的字段"""
    data = {"user_id": user_id}
    if nickname is not None:
        data["nickname"] = nickname
    if avatar_url is not None:
        data["avatar_url"] = avatar_url
    result = supabase.table("user_profiles").upsert(
        data, on_conflict="user_id"
    ).execute()
    return result.data[0] if result.data else {}


# ─────────────────────────────────────────
# v6.0 用户地图相关操作
# ─────────────────────────────────────────

def get_user_map_info(user_id: str) -> dict:
    """
    获取用户地图基本信息
    返回：{ user_id, nickname, avatar_url, is_public, restaurant_count }
    """
    # 获取用户 profile
    profile = get_user_profile(user_id)
    if not profile:
        return {"is_public": True, "restaurant_count": 0}

    # 获取地图隐私设置
    map_result = supabase.table("user_maps").select("is_public").eq("user_id", user_id).execute()
    is_public = map_result.data[0]["is_public"] if map_result.data else True

    # 计算店铺总数（博主推荐 + 自建）
    author_count = supabase.table("author_restaurants").select("restaurant_id", count="exact").in_(
        "author_id",
        [f["author_id"] for f in get_user_followed_authors(user_id)]
    ).execute().count or 0

    user_count = supabase.table("user_created_restaurants").select("*", count="exact").eq(
        "user_id", user_id
    ).execute().count or 0

    return {
        "user_id": user_id,
        "nickname": profile.get("nickname", "美食探索者"),
        "avatar_url": profile.get("avatar_url"),
        "is_public": is_public,
        "restaurant_count": author_count + user_count
    }


def get_user_map_restaurants_public(
    user_id: str,
    page: int = 1,
    page_size: int = 50,
    lat: float = None,
    lng: float = None,
    radius_km: float = 10
) -> dict:
    """
    分页获取他人地图的店铺列表
    私密地图返回 { is_private: true, restaurants: [] }
    """
    # 检查地图是否公开
    map_result = supabase.table("user_maps").select("is_public").eq("user_id", user_id).execute()
    if not map_result.data or not map_result.data[0]["is_public"]:
        return {"is_private": True, "restaurants": [], "total": 0, "has_more": False}

    # 获取博主推荐的店铺
    author_ids = [f["author_id"] for f in get_user_followed_authors(user_id)]
    author_restaurants = []
    if author_ids:
        result = supabase.table("author_restaurants").select(
            "restaurant_id, restaurants(id, name, address, city, category, latitude, longitude, photo_url)"
        ).in_("author_id", author_ids).execute()
        author_restaurants = result.data or []

    # 获取用户自建店铺
    user_restaurants = supabase.table("user_created_restaurants").select(
        "restaurant_id, restaurants(id, name, address, city, category, latitude, longitude, photo_url)"
    ).eq("user_id", user_id).execute().data or []

    # 合并并去重
    seen_ids = set()
    all_restaurants = []
    for item in author_restaurants + user_restaurants:
        rest = item.get("restaurants")
        if rest and rest["id"] not in seen_ids:
            seen_ids.add(rest["id"])
            all_restaurants.append({
                "id": rest["id"],
                "restaurant_id": rest["id"],
                "name": rest.get("name"),
                "address": rest.get("address"),
                "city": rest.get("city"),
                "category": rest.get("category"),
                "latitude": rest.get("latitude"),
                "longitude": rest.get("longitude"),
                "photo_url": rest.get("photo_url")
            })

    # 附近筛选（可选）
    if lat is not None and lng is not None:
        from math import radians, cos, sin, asin, sqrt
        def haversine(lon1, lat1, lon2, lat2):
            lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
            dlon = lon2 - lon1
            dlat = lat2 - lat1
            a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
            c = 2 * asin(sqrt(a))
            r = 6371
            return c * r

        all_restaurants = [
            r for r in all_restaurants
            if r.get("latitude") and r.get("longitude") and
            haversine(lng, lat, r["longitude"], r["latitude"]) <= radius_km
        ]

    # 分页
    total = len(all_restaurants)
    start = (page - 1) * page_size
    end = start + page_size
    paginated = all_restaurants[start:end]

    return {
        "is_private": False,
        "restaurants": paginated,
        "total": total,
        "has_more": end < total
    }


def upsert_user_map(user_id: str, is_public: bool) -> dict:
    """创建或更新用户地图隐私设置"""
    data = {"user_id": user_id, "is_public": is_public}
    result = supabase.table("user_maps").upsert(
        data, on_conflict="user_id"
    ).execute()
    return result.data[0] if result.data else {}


def subscribe_user_map(subscriber_id: str, target_user_id: str) -> dict:
    """
    订阅他人地图
    校验：subscriber_id ≠ target_user_id，target_user_id 的地图必须公开
    """
    if subscriber_id == target_user_id:
        raise ValueError("不能订阅自己的地图")

    # 检查目标地图是否公开
    map_result = supabase.table("user_maps").select("is_public").eq("user_id", target_user_id).execute()
    if not map_result.data or not map_result.data[0]["is_public"]:
        raise ValueError("该地图已设为私密，无法订阅")

    data = {
        "subscriber_id": subscriber_id,
        "target_user_id": target_user_id,
        "is_enabled": True
    }
    result = supabase.table("user_map_subscriptions").upsert(
        data, on_conflict="subscriber_id,target_user_id"
    ).execute()
    return result.data[0] if result.data else {}


def unsubscribe_user_map(subscriber_id: str, target_user_id: str) -> dict:
    """取消订阅"""
    result = supabase.table("user_map_subscriptions").delete().eq(
        "subscriber_id", subscriber_id
    ).eq("target_user_id", target_user_id).execute()
    return {"status": "ok"}


def toggle_map_subscription(subscriber_id: str, target_user_id: str, is_enabled: bool) -> dict:
    """切换订阅开关（是否在自己地图上显示该用户点位）"""
    result = supabase.table("user_map_subscriptions").update(
        {"is_enabled": is_enabled}
    ).eq("subscriber_id", subscriber_id).eq("target_user_id", target_user_id).execute()
    return result.data[0] if result.data else {}


def get_map_subscriptions(subscriber_id: str) -> list[dict]:
    """获取用户的订阅列表（含被订阅者 profile）"""
    # 先查询订阅列表
    result = supabase.table("user_map_subscriptions").select(
        "*"
    ).eq("subscriber_id", subscriber_id).execute()

    subscriptions = []
    for item in result.data or []:
        target_user_id = item["target_user_id"]

        # 分别查询被订阅者的 profile
        profile_result = supabase.table("user_profiles").select(
            "user_id, nickname, avatar_url"
        ).eq("user_id", target_user_id).execute()

        profile = profile_result.data[0] if profile_result.data else {}

        subscriptions.append({
            "id": item["id"],
            "target_user_id": target_user_id,
            "nickname": profile.get("nickname", "美食探索者"),
            "avatar_url": profile.get("avatar_url"),
            "is_enabled": item["is_enabled"],
            "created_at": item["created_at"]
        })

    return subscriptions


# ─────────────────────────────────────────
# v8.0 饭团系统：打卡相关操作
# ─────────────────────────────────────────

def create_checkin(user_id: str, restaurant_id: str, rating: int = None, comment: str = None, photo_urls: list = None) -> dict:
    """创建打卡记录（含可选的评分、评价、照片）"""
    data = {"user_id": user_id, "restaurant_id": restaurant_id}
    if rating is not None:
        data["rating"] = rating
    if comment is not None:
        data["comment"] = comment
    if photo_urls is not None:
        data["photo_urls"] = photo_urls
    result = supabase.table("user_checkins").insert(data).execute()
    return result.data[0] if result.data else {}


def get_checkins_by_restaurant(restaurant_id: str, limit: int = 20) -> list[dict]:
    """获取某店铺的打卡记录（含用户 profile）"""
    result = (
        supabase.table("user_checkins")
        .select("*, user_profiles(nickname, avatar_url)")
        .eq("restaurant_id", restaurant_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data or []


def get_checkins_by_user(user_id: str, limit: int = 50) -> list[dict]:
    """获取用户自己的打卡历史（含店铺信息）"""
    result = (
        supabase.table("user_checkins")
        .select("*, restaurants(id, name, address, city, category, photo_url)")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data or []


def get_user_checkin_count(user_id: str) -> int:
    """获取用户打卡总数（用于成就检测）"""
    result = (
        supabase.table("user_checkins")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .execute()
    )
    return result.count or 0


def get_user_checkin_restaurant_ids(user_id: str) -> set:
    """获取用户已打卡的店铺 ID 集合（用于推荐时排除已去过的店）"""
    result = (
        supabase.table("user_checkins")
        .select("restaurant_id")
        .eq("user_id", user_id)
        .execute()
    )
    return {row["restaurant_id"] for row in (result.data or []) if row.get("restaurant_id")}


# ─────────────────────────────────────────
# v8.0 饭团系统：抽卡记录相关操作
# ─────────────────────────────────────────

def save_gacha_records(records: list[dict]) -> list[dict]:
    """
    批量保存一次抽卡的 6 张卡片记录。
    records: [{user_id, restaurant_id, rarity, is_selected, session_id, trigger_type, recommend_reason}]
    """
    result = supabase.table("gacha_records").insert(records).execute()
    return result.data or []


def mark_gacha_selected(session_id: str, restaurant_id: str) -> dict:
    """用户选中某张卡片，更新 is_selected"""
    result = (
        supabase.table("gacha_records")
        .update({"is_selected": True})
        .eq("session_id", session_id)
        .eq("restaurant_id", restaurant_id)
        .execute()
    )
    return result.data[0] if result.data else {}


def get_user_gacha_count(user_id: str) -> int:
    """获取用户累计抽卡次数（按 session 去重，用于成就检测）"""
    result = (
        supabase.table("gacha_records")
        .select("session_id")
        .eq("user_id", user_id)
        .eq("is_selected", True)
        .execute()
    )
    return len(result.data or [])


def get_user_rare_card_count(user_id: str) -> int:
    """获取用户抽中的稀有卡数量（is_selected=true 且 rarity=rare）"""
    result = (
        supabase.table("gacha_records")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .eq("is_selected", True)
        .eq("rarity", "rare")
        .execute()
    )
    return result.count or 0


def get_user_limited_card_count(user_id: str) -> int:
    """获取用户抽中的限定卡数量"""
    result = (
        supabase.table("gacha_records")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .eq("is_selected", True)
        .eq("rarity", "limited")
        .execute()
    )
    return result.count or 0


# ─────────────────────────────────────────
# v8.0 饭团系统：每日抽卡次数管理
# ─────────────────────────────────────────

def get_daily_gacha_count(user_id: str) -> int:
    """获取用户今日已使用的抽卡次数"""
    from datetime import date
    today = date.today().isoformat()
    result = (
        supabase.table("daily_gacha_counts")
        .select("count")
        .eq("user_id", user_id)
        .eq("date", today)
        .execute()
    )
    if result.data:
        return result.data[0].get("count", 0)
    return 0


def increment_daily_gacha_count(user_id: str) -> int:
    """
    增加用户今日抽卡次数，返回更新后的次数。
    若今日无记录则创建（count=1），有记录则 +1。
    """
    from datetime import date
    today = date.today().isoformat()
    current = get_daily_gacha_count(user_id)
    new_count = current + 1
    supabase.table("daily_gacha_counts").upsert(
        {"user_id": user_id, "date": today, "count": new_count},
        on_conflict="user_id,date"
    ).execute()
    return new_count


# ─────────────────────────────────────────
# v8.0 饭团系统：成就相关操作
# ─────────────────────────────────────────

def get_all_achievements() -> list[dict]:
    """获取所有成就定义"""
    result = supabase.table("achievements").select("*").order("condition_value").execute()
    return result.data or []


def get_user_achievements(user_id: str) -> list[dict]:
    """获取用户已解锁的成就（含成就定义详情）"""
    result = (
        supabase.table("user_achievements")
        .select("*, achievements(*)")
        .eq("user_id", user_id)
        .order("unlocked_at", desc=True)
        .execute()
    )
    return result.data or []


def unlock_achievement(user_id: str, achievement_id: str) -> dict | None:
    """
    解锁成就（幂等操作，已解锁则跳过）。
    返回新解锁的记录，若已存在返回 None。
    """
    # 检查是否已解锁
    existing = (
        supabase.table("user_achievements")
        .select("id")
        .eq("user_id", user_id)
        .eq("achievement_id", achievement_id)
        .execute()
    )
    if existing.data:
        return None

    result = supabase.table("user_achievements").insert({
        "user_id": user_id,
        "achievement_id": achievement_id,
    }).execute()
    return result.data[0] if result.data else None


# ─────────────────────────────────────────
# v8.0 饭团系统：用户行为日志
# ─────────────────────────────────────────

def log_user_behavior(user_id: str, action: str, target_type: str = None, target_id: str = None, metadata: dict = None) -> dict:
    """
    记录用户行为日志，用于 AI 推荐的偏好分析。
    action: view / favorite / checkin / gacha / navigate / unfavorite
    target_type: restaurant / author / card
    """
    data = {"user_id": user_id, "action": action}
    if target_type:
        data["target_type"] = target_type
    if target_id:
        data["target_id"] = target_id
    if metadata:
        data["metadata"] = metadata
    result = supabase.table("user_behavior_logs").insert(data).execute()
    return result.data[0] if result.data else {}


def get_recent_user_behaviors(user_id: str, limit: int = 50) -> list[dict]:
    """获取用户最近的行为日志（用于 AI 推荐分析偏好）"""
    result = (
        supabase.table("user_behavior_logs")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data or []


def get_user_gacha_streak(user_id: str) -> int:
    """
    计算用户连续抽卡天数（用于成就检测）。
    从今天往前数，连续有抽卡记录的天数。
    """
    from datetime import date, timedelta
    result = (
        supabase.table("daily_gacha_counts")
        .select("date, count")
        .eq("user_id", user_id)
        .gt("count", 0)
        .order("date", desc=True)
        .limit(60)  # 最多查 60 天
        .execute()
    )
    if not result.data:
        return 0

    dates = sorted([row["date"] for row in result.data], reverse=True)
    streak = 0
    today = date.today()
    for i, d in enumerate(dates):
        expected = (today - timedelta(days=i)).isoformat()
        if d == expected:
            streak += 1
        else:
            break
    return streak


# ─────────────────────────────────────────
# v8.0 饭团系统：推荐池构建辅助查询
# ─────────────────────────────────────────

def get_platform_popular_restaurants(limit: int = 50) -> list[dict]:
    """
    获取平台热门店铺（全平台收藏数最多的店铺）。
    用于冷启动和推荐池补充。
    """
    # 统计每个店铺的收藏数
    fav_result = (
        supabase.table("user_favorites")
        .select("restaurant_id")
        .execute()
    )
    # 计数
    counts: dict[str, int] = {}
    for row in (fav_result.data or []):
        rid = row.get("restaurant_id")
        if rid:
            counts[rid] = counts.get(rid, 0) + 1

    if not counts:
        return []

    # 按收藏数排序取 top N
    sorted_ids = sorted(counts.keys(), key=lambda x: counts[x], reverse=True)[:limit]

    # 查询店铺详情
    result = (
        supabase.table("restaurants")
        .select("*")
        .in_("id", sorted_ids)
        .execute()
    )
    restaurants = result.data or []

    # 附加收藏数并排序
    for r in restaurants:
        r["favorite_count"] = counts.get(r["id"], 0)
    restaurants.sort(key=lambda x: x.get("favorite_count", 0), reverse=True)

    return restaurants


def get_user_all_restaurants(user_id: str) -> list[dict]:
    """
    获取用户所有可推荐的店铺（达人推荐 + 自建 + 订阅用户的店铺）。
    去重后返回，用于推荐池构建。
    """
    seen_ids = set()
    all_restaurants = []

    # 1. 用户关注的博主推荐的店铺
    follows = get_user_followed_authors(user_id)
    if follows:
        author_ids = [f["author_id"] for f in follows]
        result = (
            supabase.table("author_restaurants")
            .select("restaurant_id, restaurants(*)")
            .in_("author_id", author_ids)
            .execute()
        )
        for item in (result.data or []):
            r = item.get("restaurants")
            if r and r["id"] not in seen_ids:
                seen_ids.add(r["id"])
                r["source"] = "author"
                all_restaurants.append(r)

    # 2. 用户自建推荐
    user_created = get_user_created_restaurants(user_id)
    for item in user_created:
        r = item.get("restaurants")
        if r and r["id"] not in seen_ids:
            seen_ids.add(r["id"])
            r["source"] = "user_created"
            all_restaurants.append(r)

    # 3. 订阅用户的店铺
    subs = get_map_subscriptions(user_id)
    for sub in subs:
        if not sub.get("is_enabled", True):
            continue
        target_id = sub.get("target_user_id")
        if not target_id:
            continue
        # 获取被订阅用户的博主推荐
        target_follows = get_user_followed_authors(target_id)
        if target_follows:
            target_author_ids = [f["author_id"] for f in target_follows]
            result = (
                supabase.table("author_restaurants")
                .select("restaurant_id, restaurants(*)")
                .in_("author_id", target_author_ids)
                .execute()
            )
            for item in (result.data or []):
                r = item.get("restaurants")
                if r and r["id"] not in seen_ids:
                    seen_ids.add(r["id"])
                    r["source"] = "subscription"
                    all_restaurants.append(r)

    return all_restaurants


def get_restaurant_recommend_count(restaurant_id: str) -> int:
    """获取某店铺被多少个达人推荐过（用于稀有度判定）"""
    result = (
        supabase.table("author_restaurants")
        .select("author_id", count="exact")
        .eq("restaurant_id", restaurant_id)
        .execute()
    )
    return result.count or 0


def get_restaurant_authors(restaurant_id: str) -> list[dict]:
    """获取推荐某店铺的所有博主信息（用于抽卡结果页展示）"""
    result = (
        supabase.table("author_restaurants")
        .select("authors(id, name, avatar_url)")
        .eq("restaurant_id", restaurant_id)
        .execute()
    )
    # 去重（同一博主可能有多个视频推荐同一店铺）
    seen = set()
    authors = []
    for row in (result.data or []):
        a = row.get("authors")
        if a and a.get("id") not in seen:
            seen.add(a["id"])
            authors.append(a)
    return authors


def get_favorite_notes_for_restaurant(restaurant_id: str, limit: int = 10) -> list[str]:
    """获取某店铺的所有收藏理由（用于 AI 摘要）"""
    result = (
        supabase.table("user_favorites")
        .select("note")
        .eq("restaurant_id", restaurant_id)
        .not_is("note", "null")
        .neq("note", "")
        .limit(limit)
        .execute()
    )
    return [row["note"] for row in (result.data or []) if row.get("note")]


# ─────────────────────────────────────────
# v10.0 新增：用户勘误相关操作
# ─────────────────────────────────────────

def create_user_correction(data: dict) -> dict:
    """创建用户勘误记录"""
    result = supabase.table("user_corrections").insert(data).execute()
    return result.data[0] if result.data else {}


def get_corrections_by_restaurant(restaurant_id: str) -> list[dict]:
    """获取某店铺的所有勘误记录（复核页面展示用）"""
    result = (
        supabase.table("user_corrections")
        .select("*")
        .eq("restaurant_id", restaurant_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


def get_corrections_by_video_cache(video_cache_id: str) -> list[dict]:
    """获取某视频缓存记录的所有勘误"""
    result = (
        supabase.table("user_corrections")
        .select("*")
        .eq("video_cache_id", video_cache_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


def get_user_corrections_for_review_item(
    restaurant_id: str | None = None,
    video_cache_id: str | None = None,
) -> list[dict]:
    """聚合某条复核记录关联的全部勘误（餐厅级 + 视频级），按时间倒序去重返回"""
    merged: dict[str, dict] = {}

    if restaurant_id:
        for row in get_corrections_by_restaurant(restaurant_id):
            correction_id = row.get("id")
            if correction_id:
                merged[correction_id] = row

    if video_cache_id:
        for row in get_corrections_by_video_cache(video_cache_id):
            correction_id = row.get("id")
            if correction_id:
                merged[correction_id] = row

    return sorted(
        merged.values(),
        key=lambda row: _iso_to_timestamp(row.get("created_at")),
        reverse=True,
    )


def get_pending_correction_targets() -> tuple[dict[str, float], dict[str, float]]:
    """返回待处理用户勘误关联的 video_cache / restaurant 最新时间索引，用于复核排序"""
    result = (
        supabase.table("user_corrections")
        .select("restaurant_id, video_cache_id, created_at")
        .eq("status", "pending")
        .execute()
    )

    cache_times: dict[str, float] = {}
    restaurant_times: dict[str, float] = {}

    for row in (result.data or []):
        ts = _iso_to_timestamp(row.get("created_at"))
        cache_id = row.get("video_cache_id")
        restaurant_id = row.get("restaurant_id")

        if cache_id:
            cache_times[cache_id] = max(cache_times.get(cache_id, 0.0), ts)
        if restaurant_id:
            restaurant_times[restaurant_id] = max(restaurant_times.get(restaurant_id, 0.0), ts)

    return cache_times, restaurant_times


def mark_user_corrections_reviewed(
    reviewed_by: str,
    restaurant_id: str | None = None,
    video_cache_id: str | None = None,
    review_note: str | None = None,
    status: str = "reviewed",
) -> None:
    """管理员处理复核后，将相关待处理勘误标记为已复核"""
    update_data = {
        "status": status,
        "reviewed_by": reviewed_by,
        "reviewed_at": "now()",
    }
    if review_note:
        update_data["review_note"] = review_note

    if restaurant_id:
        supabase.table("user_corrections").update(update_data).eq(
            "restaurant_id", restaurant_id
        ).eq("status", "pending").execute()

    if video_cache_id:
        supabase.table("user_corrections").update(update_data).eq(
            "video_cache_id", video_cache_id
        ).eq("status", "pending").execute()


def reset_review_status_for_correction(restaurant_id: str = None, video_cache_id: str = None):
    """
    勘误提交后，将关联的 video_parse_cache 记录的 review_status 重置为 pending。
    即使之前已人工复核过，也重新进入复核队列。
    """
    if restaurant_id:
        # 找到该店铺关联的所有 video_parse_cache 记录
        result = (
            supabase.table("video_parse_cache")
            .select("id")
            .eq("restaurant_id", restaurant_id)
            .execute()
        )
        for row in (result.data or []):
            supabase.table("video_parse_cache").update(
                {"review_status": "pending"}
            ).eq("id", row["id"]).execute()

    if video_cache_id:
        supabase.table("video_parse_cache").update(
            {"review_status": "pending"}
        ).eq("id", video_cache_id).execute()


def _iso_to_timestamp(value: str | None) -> float:
    """将 ISO 时间转为时间戳，异常时返回 0，便于排序"""
    if not value:
        return 0.0
    try:
        normalized = value.replace("Z", "+00:00")
        return datetime.fromisoformat(normalized).timestamp()
    except Exception:
        return 0.0


# ─────────────────────────────────────────
# v10.10 饭团养成体系
# ─────────────────────────────────────────

def _calc_intimacy_level(intimacy: int) -> int:
    """根据亲密度数值计算等级 1-5"""
    if intimacy >= 500: return 5
    if intimacy >= 300: return 4
    if intimacy >= 150: return 3
    if intimacy >= 50: return 2
    return 1


def get_fantuan_status(user_id: str) -> dict:
    """
    获取饭团养成状态。
    不存在则自动创建默认记录（饱食度 80，亲密度 0）。
    """
    result = supabase.table("fantuan_status").select("*").eq("user_id", user_id).execute()
    if result.data:
        return result.data[0]
    # 首次访问，创建默认记录
    default = {"user_id": user_id, "satiety": 80, "intimacy": 0, "intimacy_level": 1, "consecutive_login_days": 0}
    insert_result = supabase.table("fantuan_status").insert(default).execute()
    return insert_result.data[0] if insert_result.data else default


def fantuan_daily_login(user_id: str) -> dict:
    """
    每日登录签到。
    - 计算离线天数，扣减饱食度（每天 -5）
    - 判断连续登录
    - 饱食度 +10，亲密度 +2（连续≥3天 ×1.5）
    返回：{ satiety_change, intimacy_change, fantuan_status, already_logged_in }
    """
    from datetime import date
    today = date.today()
    status = get_fantuan_status(user_id)

    last_login = status.get("last_login_date")
    if last_login and str(last_login) == today.isoformat():
        return {"satiety_change": 0, "intimacy_change": 0, "fantuan_status": status, "already_logged_in": True}

    satiety = status["satiety"]
    intimacy = status["intimacy"]
    consecutive = status["consecutive_login_days"]

    # 计算离线天数并扣减饱食度
    if last_login:
        try:
            last_date = date.fromisoformat(str(last_login))
            days_away = (today - last_date).days
        except (ValueError, TypeError):
            days_away = 1
    else:
        days_away = 0  # 首次登录不扣减

    if days_away > 0:
        satiety = max(0, satiety - days_away * 5)

    # 连续登录判断
    if last_login:
        try:
            last_date = date.fromisoformat(str(last_login))
            consecutive = consecutive + 1 if (today - last_date).days == 1 else 1
        except (ValueError, TypeError):
            consecutive = 1
    else:
        consecutive = 1

    # 计算增量（连续≥3天 ×1.5）
    multiplier = 1.5 if consecutive >= 3 else 1.0
    satiety_add = 10
    intimacy_add = int(2 * multiplier)
    satiety = min(100, satiety + satiety_add)
    intimacy += intimacy_add
    level = _calc_intimacy_level(intimacy)

    update_data = {
        "satiety": satiety, "intimacy": intimacy, "intimacy_level": level,
        "consecutive_login_days": consecutive, "last_login_date": today.isoformat(),
        "updated_at": "now()",
    }
    result = supabase.table("fantuan_status").update(update_data).eq("user_id", user_id).execute()
    updated = result.data[0] if result.data else {**status, **update_data}
    return {"satiety_change": satiety_add, "intimacy_change": intimacy_add, "fantuan_status": updated, "already_logged_in": False}


def fantuan_pet(user_id: str) -> dict:
    """
    摸摸饭团，每日限 1 次。
    饱食度 +5，亲密度 +3（连续≥3天 ×1.5）。
    """
    from datetime import date
    today = date.today()
    status = get_fantuan_status(user_id)

    if status.get("last_pet_date") and str(status["last_pet_date"]) == today.isoformat():
        return {"already_pet": True, "satiety_change": 0, "intimacy_change": 0, "fantuan_status": status}

    multiplier = 1.5 if status["consecutive_login_days"] >= 3 else 1.0
    satiety_add = 5
    intimacy_add = int(3 * multiplier)
    satiety = min(100, status["satiety"] + satiety_add)
    intimacy = status["intimacy"] + intimacy_add
    level = _calc_intimacy_level(intimacy)

    update_data = {
        "satiety": satiety, "intimacy": intimacy, "intimacy_level": level,
        "last_pet_date": today.isoformat(), "updated_at": "now()",
    }
    result = supabase.table("fantuan_status").update(update_data).eq("user_id", user_id).execute()
    updated = result.data[0] if result.data else {**status, **update_data}
    return {"already_pet": False, "satiety_change": satiety_add, "intimacy_change": intimacy_add, "fantuan_status": updated}


def _update_fantuan_values(user_id: str, satiety_add: int, intimacy_add: int) -> dict:
    """内部通用：增加饱食度和亲密度，返回更新后状态"""
    status = get_fantuan_status(user_id)
    multiplier = 1.5 if status["consecutive_login_days"] >= 3 else 1.0
    actual_intimacy = int(intimacy_add * multiplier) if intimacy_add > 0 else 0
    satiety = min(100, status["satiety"] + satiety_add)
    intimacy = status["intimacy"] + actual_intimacy
    level = _calc_intimacy_level(intimacy)

    update_data = {"satiety": satiety, "intimacy": intimacy, "intimacy_level": level, "updated_at": "now()"}
    result = supabase.table("fantuan_status").update(update_data).eq("user_id", user_id).execute()
    return result.data[0] if result.data else {**status, **update_data}


def update_fantuan_on_gacha(user_id: str) -> dict:
    """抽卡时附带更新：饱食度 +3，亲密度 +1"""
    return _update_fantuan_values(user_id, satiety_add=3, intimacy_add=1)


def update_fantuan_on_checkin(user_id: str) -> dict:
    """打卡时附带更新：饱食度 +15，亲密度 +5"""
    return _update_fantuan_values(user_id, satiety_add=15, intimacy_add=5)


def update_fantuan_on_favorite(user_id: str) -> dict:
    """收藏时附带更新：饱食度 +2"""
    return _update_fantuan_values(user_id, satiety_add=2, intimacy_add=0)
