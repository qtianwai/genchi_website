# FastAPI 主程序
# 定义所有 API 路由，是后端的入口文件
# iOS App 通过这些接口与后端通信

import os
from fastapi import FastAPI, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from douyin_parser import parse_douyin_link, fetch_author_videos
from ai_extractor import extract_restaurants_from_video
from amap_service import batch_search_restaurants
from db import (
    get_author_by_douyin_id, upsert_author,
    get_restaurant_by_amap_id, upsert_restaurant,
    link_author_restaurant, get_parse_record, save_parse_record,
    get_user_followed_authors, follow_author, unfollow_author,
    get_map_restaurants_for_user,
    get_user_favorites, add_favorite, remove_favorite,
    get_restaurants_by_author,
)

load_dotenv()

app = FastAPI(title="达人美食推荐 API", version="1.0.0")

# 允许跨域（iOS App 调用需要）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─────────────────────────────────────────
# 请求/响应数据模型
# ─────────────────────────────────────────

class ParseLinkRequest(BaseModel):
    url: str        # 抖音分享链接
    user_id: str    # 当前用户 ID（Supabase Auth 的 user id）

class FollowRequest(BaseModel):
    user_id: str
    author_id: str

class FavoriteRequest(BaseModel):
    user_id: str
    restaurant_id: str


# ─────────────────────────────────────────
# 健康检查
# ─────────────────────────────────────────

@app.get("/")
async def health_check():
    """服务健康检查，Railway 部署后可用此接口验证服务是否正常"""
    return {"status": "ok", "service": "达人美食推荐后端"}


# ─────────────────────────────────────────
# 核心功能：解析抖音链接
# ─────────────────────────────────────────

@app.post("/api/parse-link")
async def parse_link(req: ParseLinkRequest):
    """
    解析抖音分享链接，提取博主信息和推荐店铺

    流程：
    1. 解析链接获取视频信息和博主信息
    2. 检查该博主是否已入库（已入库则直接返回，不重复解析）
    3. 未入库则调用 AI 提取店铺，再用高德搜索地址
    4. 将博主、店铺、关联关系存入数据库
    5. 自动关注该博主（用户粘贴链接即表示感兴趣）
    """
    try:
        # 第一步：解析抖音链接
        video_info = await parse_douyin_link(req.url)
        author_douyin_id = video_info.get("author_id", "")
        author_sec_uid = video_info.get("author_sec_uid", "")

        if not author_douyin_id:
            raise HTTPException(status_code=400, detail="无法识别博主信息，请检查链接是否正确")

        # 第二步：检查博主是否已入库
        existing_author = get_author_by_douyin_id(author_douyin_id)

        if existing_author:
            # 博主已入库，直接返回已有数据，不重复解析
            author_id = existing_author["id"]
            restaurants = get_restaurants_by_author(author_id)

            # 自动关注该博主
            follow_author(req.user_id, author_id)

            return {
                "status": "cached",  # 表示使用了缓存数据
                "author": existing_author,
                "restaurants": restaurants,
                "message": f"已从数据库加载 {len(restaurants)} 家店铺",
            }

        # 第三步：新博主，先存入博主信息
        author_record = upsert_author({
            "douyin_uid": author_douyin_id,
            "sec_uid": author_sec_uid,
            "name": video_info.get("author_name", "未知博主"),
            "avatar_url": video_info.get("author_avatar", ""),
        })
        author_id = author_record["id"]

        # 第四步：获取博主所有视频并逐一解析（最多处理 20 个视频）
        all_restaurants = []

        if author_sec_uid:
            # 获取博主视频列表
            videos = await fetch_author_videos(author_sec_uid, max_count=20)
        else:
            # 如果获取不到视频列表，至少处理当前这个视频
            videos = [{"video_id": video_info["video_id"], "title": video_info["title"]}]

        # 对每个视频调用 AI 提取店铺
        for video in videos:
            extracted = await extract_restaurants_from_video(
                video_title=video.get("title", ""),
                comments=[],  # 批量处理时暂不获取评论，节省时间
                author_name=video_info.get("author_name", ""),
            )
            all_restaurants.extend(extracted)

        # 第五步：去重（同名同城市的店铺只保留一个）
        seen = set()
        unique_restaurants = []
        for r in all_restaurants:
            key = f"{r['name']}_{r.get('city', '')}"
            if key not in seen:
                seen.add(key)
                unique_restaurants.append(r)

        # 第六步：调用高德地图搜索精确地址和坐标
        restaurants_with_location = await batch_search_restaurants(unique_restaurants)

        # 第七步：存入数据库并建立博主-店铺关联
        saved_restaurants = []
        for r in restaurants_with_location:
            # 检查店铺是否已存在（可能被其他博主推荐过）
            existing = get_restaurant_by_amap_id(r["amap_id"])
            if existing:
                restaurant_id = existing["id"]
            else:
                saved = upsert_restaurant({
                    "name": r["name"],
                    "address": r["address"],
                    "city": r["city"],
                    "latitude": r["latitude"],
                    "longitude": r["longitude"],
                    "amap_id": r["amap_id"],
                    "category": r.get("category", ""),
                })
                restaurant_id = saved["id"]

            # 建立博主和店铺的关联
            link_author_restaurant(author_id, restaurant_id, video_info["video_id"])
            saved_restaurants.append(r)

        # 第八步：记录解析完成，避免下次重复解析
        save_parse_record(author_id, len(videos))

        # 第九步：自动关注该博主
        follow_author(req.user_id, author_id)

        return {
            "status": "parsed",  # 表示新解析的数据
            "author": author_record,
            "restaurants": saved_restaurants,
            "message": f"成功解析 {len(saved_restaurants)} 家店铺",
        }

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"[解析链接] 未知错误: {e}")
        raise HTTPException(status_code=500, detail=f"解析失败: {str(e)}")


# ─────────────────────────────────────────
# 地图数据接口
# ─────────────────────────────────────────

@app.get("/api/map/restaurants")
async def get_map_restaurants(user_id: str):
    """
    获取用户地图上应显示的所有店铺
    返回用户关注的所有博主推荐的店铺，含坐标和博主头像信息
    """
    try:
        data = get_map_restaurants_for_user(user_id)
        return {"restaurants": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 博主关注接口
# ─────────────────────────────────────────

@app.get("/api/authors/following")
async def get_following(user_id: str):
    """获取用户关注的博主列表"""
    try:
        authors = get_user_followed_authors(user_id)
        return {"authors": authors}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/authors/follow")
async def follow(req: FollowRequest):
    """关注博主"""
    try:
        result = follow_author(req.user_id, req.author_id)
        return {"status": "ok", "data": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/authors/unfollow")
async def unfollow(req: FollowRequest):
    """取消关注博主"""
    try:
        unfollow_author(req.user_id, req.author_id)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/authors/{author_id}/restaurants")
async def get_author_restaurants(author_id: str):
    """获取某个博主推荐的所有店铺"""
    try:
        restaurants = get_restaurants_by_author(author_id)
        return {"restaurants": restaurants}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 收藏接口
# ─────────────────────────────────────────

@app.get("/api/favorites")
async def get_favorites(user_id: str):
    """获取用户收藏的店铺列表"""
    try:
        favorites = get_user_favorites(user_id)
        return {"favorites": favorites}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/favorites/add")
async def add_to_favorites(req: FavoriteRequest):
    """收藏店铺"""
    try:
        result = add_favorite(req.user_id, req.restaurant_id)
        return {"status": "ok", "data": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/favorites/remove")
async def remove_from_favorites(req: FavoriteRequest):
    """取消收藏"""
    try:
        remove_favorite(req.user_id, req.restaurant_id)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 本地开发启动入口
# ─────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    # 本地开发时运行：python main.py
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
