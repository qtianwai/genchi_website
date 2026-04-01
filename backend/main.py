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
from sms_service import generate_otp, store_otp, verify_otp as verify_otp_code, send_sms, phone_to_user_id
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

app = FastAPI(title="跟吃 API", version="1.0.0")

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
    user_id: str    # 当前用户 ID

class FollowRequest(BaseModel):
    user_id: str
    author_id: str

class FavoriteRequest(BaseModel):
    user_id: str
    restaurant_id: str

class SendOTPRequest(BaseModel):
    phone: str      # 手机号，格式：+8613800138000

class VerifyOTPRequest(BaseModel):
    phone: str      # 手机号
    code: str       # 6 位验证码


# ─────────────────────────────────────────
# 健康检查
# ─────────────────────────────────────────

@app.get("/")
async def health_check():
    """服务健康检查，Railway 部署后可用此接口验证服务是否正常"""
    return {"status": "ok", "service": "跟吃后端"}


# ─────────────────────────────────────────
# 认证接口：发送和验证短信验证码
# ─────────────────────────────────────────

@app.post("/api/auth/send-otp")
async def send_otp(req: SendOTPRequest):
    """
    发送短信验证码
    手机号格式：+8613800138000（含国家码）
    """
    phone = req.phone.strip()
    if not phone.startswith("+"):
        raise HTTPException(status_code=400, detail="手机号格式错误，需包含国家码，如 +8613800138000")

    code = generate_otp()
    store_otp(phone, code)

    success = await send_sms(phone, code)
    if not success:
        raise HTTPException(status_code=500, detail="短信发送失败，请稍后重试")

    return {"status": "ok", "message": "验证码已发送"}


@app.post("/api/auth/verify-otp")
async def verify_otp(req: VerifyOTPRequest):
    """
    验证短信验证码，验证成功返回 user_id 和 access_token
    user_id 由手机号确定性生成，同一手机号永远对应同一 user_id
    """
    phone = req.phone.strip()
    code = req.code.strip()

    if not verify_otp_code(phone, code):
        raise HTTPException(status_code=400, detail="验证码错误或已过期")

    # 由手机号生成固定 user_id（UUID v5，确定性）
    user_id = phone_to_user_id(phone)

    # 生成一个简单的 access_token（用于 iOS 端标识已登录状态）
    # 这里用 user_id 本身作为 token，因为 user_id 已经是不可猜测的 UUID
    access_token = user_id

    return {
        "status": "ok",
        "user_id": user_id,
        "access_token": access_token,
    }


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
            # 抖音反爬导致无法获取博主 ID 时，用视频 ID 作为兜底唯一标识
            # 这样至少能完成本次解析，不会直接报错
            author_douyin_id = f"video_{video_info.get('video_id', 'unknown')}"
            print(f"[解析链接] 未获取到博主 ID，使用视频 ID 兜底: {author_douyin_id}")

        # 第二步：检查博主是否已入库
        existing_author = get_author_by_douyin_id(author_douyin_id)

        if existing_author:
            author_id = existing_author["id"]
            restaurants = get_restaurants_by_author(author_id)

            if restaurants:
                # 博主已入库且有店铺数据，直接返回缓存
                follow_author(req.user_id, author_id)
                return {
                    "status": "cached",
                    "author": existing_author,
                    "restaurants": restaurants,
                    "message": f"已从数据库加载 {len(restaurants)} 家店铺",
                }
            # 博主已入库但店铺为空（上次解析失败），继续往下重新解析
            print(f"[解析链接] 博主已入库但无店铺数据，重新解析: {author_douyin_id}")

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
        videos = []

        if author_sec_uid:
            # 获取博主视频列表
            videos = await fetch_author_videos(author_sec_uid, max_count=20)

        # 视频列表为空（获取失败或无 sec_uid），回退到当前视频
        if not videos:
            print(f"[解析链接] 视频列表为空，回退到当前视频: {video_info.get('video_id')}")
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
