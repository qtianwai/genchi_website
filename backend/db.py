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
    """获取某个博主推荐的所有店铺（含店铺详情）"""
    result = (
        supabase.table("author_restaurants")
        .select("*, restaurants(*)")
        .eq("author_id", author_id)
        .execute()
    )
    return result.data or []


def link_author_restaurant(author_id: str, restaurant_id: str, video_id: str = "") -> dict:
    """
    建立博主和店铺的关联关系
    一个博主可以推荐多个店铺，一个店铺也可以被多个博主推荐
    """
    data = {
        "author_id": author_id,
        "restaurant_id": restaurant_id,
        "video_id": video_id,
    }
    result = supabase.table("author_restaurants").upsert(
        data,
        on_conflict="author_id,restaurant_id"
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
    result = supabase.table("video_parse_cache").update({
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
    }).eq("video_url", video_url).execute()
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
