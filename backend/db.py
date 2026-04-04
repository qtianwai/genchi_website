# Supabase 数据库操作模块
# 负责所有数据库的读写操作：博主、店铺、用户关注关系等

import os
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
    # 可选字段：解析说明、数据来源、API 成本
    if restaurant_data.get("parse_reason") is not None:
        update_data["parse_reason"] = restaurant_data["parse_reason"]
    if restaurant_data.get("data_source") is not None:
        update_data["data_source"] = restaurant_data["data_source"]
    if restaurant_data.get("api_cost") is not None:
        update_data["api_cost"] = restaurant_data["api_cost"]
    if restaurant_data.get("api_cost_note") is not None:
        update_data["api_cost_note"] = restaurant_data["api_cost_note"]

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
    tab='reviewed'：已复核（review_status IN approved/corrected/confirmed），按 reviewed_at 倒序。
    返回 {items, total, page, page_size}
    """
    offset = (page - 1) * page_size

    select_fields = (
        "id, video_id, video_url, author_id, restaurant_id, review_status, "
        "parse_reason, restaurant_name, restaurant_address, restaurant_city, "
        "restaurant_lat, restaurant_lng, restaurant_amap_id, restaurant_category, "
        "reviewed_at, created_at, authors(name, avatar_url)"
    )

    if tab == "reviewed":
        # 已复核：approved / corrected / confirmed，按 reviewed_at 倒序
        result = (
            supabase.table("video_parse_cache")
            .select(select_fields, count="exact")
            .in_("review_status", ["approved", "corrected", "confirmed"])
            .eq("status", "completed")
            .order("reviewed_at", desc=True)
            .range(offset, offset + page_size - 1)
            .execute()
        )
    else:
        # 待复核：pending / skipped，P0（restaurant_id IS NULL）在前
        result = (
            supabase.table("video_parse_cache")
            .select(select_fields, count="exact")
            .in_("review_status", ["pending", "skipped"])
            .eq("status", "completed")
            .order("restaurant_id", desc=False, nullsfirst=True)  # NULL 在前（P0）
            .order("created_at", desc=True)
            .range(offset, offset + page_size - 1)
            .execute()
        )

    items = result.data or []
    total = result.count or 0

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

    # upsert restaurants
    r_result = supabase.table("restaurants").upsert({
        "name": name,
        "address": address,
        "city": city,
        "latitude": latitude,
        "longitude": longitude,
        "amap_id": amap_id,
        "category": category,
        "verified": True,
        "verified_at": "now()",
    }, on_conflict="amap_id").execute()

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

    # 更新 video_parse_cache
    supabase.table("video_parse_cache").update({
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
    }).eq("id", cache_id).execute()

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


def add_user_restaurant(user_id: str, restaurant_id: str, note: str = "") -> dict:
    """
    添加用户自建推荐店铺
    若该用户已添加过同一家店（unique 约束），则直接返回已有记录
    """
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
            author_data.append(item)

    # 用户自建推荐
    raw_user_data = get_user_created_restaurants(user_id)
    user_data = []
    for item in raw_user_data:
        rid = item.get("restaurant_id")
        if rid in deleted_ids:
            continue
        item["is_avoided"] = rid in avoided_ids
        user_data.append(item)

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
