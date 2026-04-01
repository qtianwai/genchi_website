# FastAPI 主程序
# 定义所有 API 路由，是后端的入口文件
# iOS App 通过这些接口与后端通信

import os
import asyncio
from datetime import datetime
from fastapi import FastAPI, HTTPException, Header, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from douyin_parser import parse_douyin_link, fetch_author_videos, fetch_video_comments, fetch_video_detail_extra, extract_url_from_text
from ai_extractor import extract_restaurants_from_video, extract_restaurants_priority
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
    # 新增：视频缓存和后台任务相关
    get_video_cache_by_url, upsert_video_cache, update_video_cache_restaurant,
    update_video_cache_failed, get_video_cache_by_id,
    create_bg_task, update_bg_task_started, update_bg_task_progress,
    complete_bg_task, fail_bg_task, get_latest_bg_task,
    get_videos_by_restaurant,
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

class ManualAddRestaurantRequest(BaseModel):
    video_url: str          # 原始视频链接
    user_id: str            # 用户 ID
    restaurant_name: str    # 店铺名称
    city: str               # 所在城市
    category: str = ""      # 美食分类（可选）


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
# 核心功能：解析抖音链接（重构版）
# 核心策略：用户提交链接后，优先解析当前视频快速返回，
#           博主其他历史视频在后台异步处理，不阻塞用户
# ─────────────────────────────────────────

def _save_video_restaurant(video_url: str, video_id: str, author_id: str, restaurant_data: dict) -> dict:
    """
    内部函数：将视频解析出的店铺存入数据库并更新视频缓存
    统一处理：店铺入库 → 关联博主 → 更新视频缓存
    """
    # 查询高德坐标（只有有坐标的店铺才入库）
    if not restaurant_data.get("latitude") or not restaurant_data.get("longitude"):
        return {"restaurant": None, "status": "no_location"}

    # 检查店铺是否已存在
    existing = get_restaurant_by_amap_id(restaurant_data["amap_id"])
    if existing:
        restaurant_id = existing["id"]
    else:
        saved = upsert_restaurant({
            "name": restaurant_data["name"],
            "address": restaurant_data["address"],
            "city": restaurant_data["city"],
            "latitude": restaurant_data["latitude"],
            "longitude": restaurant_data["longitude"],
            "amap_id": restaurant_data["amap_id"],
            "category": restaurant_data.get("category", ""),
        })
        restaurant_id = saved["id"]

    # 博主与店铺关联
    link_author_restaurant(author_id, restaurant_id, video_id)

    # 更新视频缓存（记录店铺快照）
    update_video_cache_restaurant(video_url, restaurant_id, restaurant_data)

    return {
        "restaurant": restaurant_data,
        "restaurant_id": restaurant_id,
        "status": "saved",
    }


async def parse_single_video_fast(
    video_url: str,
    video_info: dict,
    author_id: str,
) -> dict:
    """
    快速解析单个视频的核心逻辑（优化版：获取评论和扩展信息以提升识别率）
    用于 parse_link 主流程，平衡速度和准确性
    """
    vid = video_info.get("video_id", "")
    title = video_info.get("title", "")
    author_name = video_info.get("author_name", "")

    # 并行获取扩展信息和评论（提升识别率）
    extra_task = fetch_video_detail_extra(vid, author_id)
    comments_task = fetch_video_comments(vid, max_count=15)

    extra, all_comments = await asyncio.gather(extra_task, comments_task)

    hashtags = extra.get("hashtags", [])
    city = extra.get("city_name", "未知")
    author_liked_comments = extra.get("author_liked_comments", [])
    hot_comments = extra.get("hot_comments", [])

    # 调用 AI 提取店铺（使用完整信息，提升识别率）
    extracted = await extract_restaurants_priority(
        video_title=title,
        author_name=author_name,
        hashtags=hashtags,
        city_name=city,
        author_liked_comments=author_liked_comments,
        hot_comments=hot_comments,
        all_comments=all_comments,
    )

    # 降级为旧算法
    if not extracted:
        extracted = await extract_restaurants_from_video(
            video_title=title,
            comments=all_comments,
            author_name=author_name,
        )

    if not extracted:
        return {"restaurant": None, "status": "not_found"}

    # 调用高德搜索坐标（只有带坐标的才入库）
    restaurant_data = extracted[0]
    search_results = await batch_search_restaurants([restaurant_data])

    if not search_results:
        # 高德搜不到，记录失败缓存
        upsert_video_cache({
            "video_url": video_url,
            "video_id": vid,
            "author_id": author_id,
            "status": "failed",
            "restaurant_name": restaurant_data.get("name", ""),
            "restaurant_city": restaurant_data.get("city", ""),
            "error_message": "高德地图未找到该店铺",
        })
        return {"restaurant": None, "status": "amap_not_found"}

    # 取高德搜索结果的第一条（最匹配的）
    amap_result = search_results[0]
    restaurant_data.update({
        "address": amap_result.get("address", ""),
        "latitude": amap_result.get("latitude"),
        "longitude": amap_result.get("longitude"),
        "amap_id": amap_result.get("amap_id"),
    })

    # 存入数据库并更新视频缓存
    result = _save_video_restaurant(video_url, vid, author_id, restaurant_data)
    return result


def parse_author_all_videos_background(author_id: str, sec_uid: str, current_video_id: str):
    """
    后台任务：解析博主所有历史探店视频（异步执行，不阻塞主流程）
    在独立的事件循环中运行，支持分批处理和错误恢复
    """
    # 在新事件循环中运行（FastAPI 需要在事件循环中 await）
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(_parse_author_videos_async(author_id, sec_uid, current_video_id))
    except Exception as e:
        print(f"[后台任务] 博主全量解析出错 author_id={author_id}: {e}")
        try:
            task = create_bg_task(author_id, "full_scan")
            fail_bg_task(task["id"], str(e))
        except Exception:
            pass
    finally:
        loop.close()


async def _parse_author_videos_async(author_id: str, sec_uid: str, current_video_id: str):
    """
    异步执行：获取博主视频列表并逐一解析（排除当前视频）
    每次只解析视频标题（不获取评论），节省 API 调用
    """
    if not sec_uid:
        print(f"[后台解析] 博主无 sec_uid，跳过历史视频解析: {author_id}")
        return

    # 获取博主视频列表（最多 30 个，排除当前视频）
    videos = await fetch_author_videos(sec_uid, max_count=30)
    video_list = [
        {
            "video_id": v.get("video_id", ""),
            "title": v.get("title", ""),
            "share_url": v.get("share_url", ""),
        }
        for v in videos if v.get("video_id") != current_video_id
    ]

    if not video_list:
        print(f"[后台解析] 博主 {author_id} 无历史视频")
        return

    # 创建后台任务记录
    task = create_bg_task(author_id, "full_scan")
    task_id = task.get("id", "")
    update_bg_task_started(task_id)

    print(f"[后台解析] 开始解析博主 {author_id} 的 {len(video_list)} 个历史视频...")

    saved_count = 0
    for i, video in enumerate(video_list):
        vid = video.get("video_id", "")
        title = video.get("title", "")

        # 检查视频是否已在缓存（已有成功结果的跳过）
        existing_cache = get_video_cache_by_id(vid)
        if existing_cache and existing_cache.get("status") == "completed":
            print(f"[后台解析] 视频 {vid} 已解析过，跳过")
            update_bg_task_progress(task_id, i + 1, saved_count)
            continue

        # 创建该视频的缓存记录
        # 优先使用真实的 share_url（可在抖音中打开），没有则构造基础链接
        share_url = video.get("share_url", "")
        video_url = share_url if share_url else f"https://www.iesdouyin.com/share/video/{vid}/"
        upsert_video_cache({
            "video_url": video_url,
            "video_id": vid,
            "author_id": author_id,
            "status": "parsing",
        })

        try:
            # 获取视频扩展信息（P1：标签+城市）
            extra = await fetch_video_detail_extra(vid, author_id)
            comments = await fetch_video_comments(vid, max_count=10) if vid else []

            # AI 提取
            extracted = await extract_restaurants_priority(
                video_title=title,
                author_name="",
                hashtags=extra.get("hashtags", []),
                city_name=extra.get("city_name", "未知"),
                author_liked_comments=extra.get("author_liked_comments", []),
                hot_comments=extra.get("hot_comments", []),
                all_comments=comments,
            )
            if not extracted:
                extracted = await extract_restaurants_from_video(
                    video_title=title,
                    comments=comments,
                    author_name="",
                )

            if extracted:
                # 高德搜索
                search_results = await batch_search_restaurants([extracted[0]])
                if search_results:
                    amap_result = search_results[0]
                    extracted[0].update({
                        "address": amap_result.get("address", ""),
                        "latitude": amap_result.get("latitude"),
                        "longitude": amap_result.get("longitude"),
                        "amap_id": amap_result.get("amap_id"),
                    })
                    result = _save_video_restaurant(video_url, vid, author_id, extracted[0])
                    if result["status"] == "saved":
                        saved_count += 1

            # 更新缓存状态
            if existing_cache := get_video_cache_by_id(vid):
                if existing_cache.get("status") != "completed":
                    upsert_video_cache({
                        "video_url": existing_cache["video_url"],
                        "video_id": vid,
                        "author_id": author_id,
                        "status": "completed" if saved_count > 0 else "failed",
                    })
        except Exception as e:
            print(f"[后台解析] 视频 {vid} 解析失败: {e}")
            update_video_cache_failed(video_url, str(e))

        update_bg_task_progress(task_id, i + 1, saved_count)

    complete_bg_task(task_id, saved_count)
    print(f"[后台解析] 博主 {author_id} 后台解析完成，新增 {saved_count} 家店铺")


@app.post("/api/parse-link")
async def parse_link(req: ParseLinkRequest, background_tasks: BackgroundTasks):
    """
    解析抖音分享链接（新流程）

    优化策略：
    1. 先用原始链接在 video_parse_cache 查缓存，命中则直接返回
    2. 未命中则解析当前视频（优先快速路径），立即返回结果
    3. 启动后台任务异步解析博主历史探店视频（不阻塞用户）
    """
    try:
        raw_url = req.url.strip()
        # 先提取纯 URL（去掉分享文字前缀），确保缓存命中不受分享格式影响
        clean_url = extract_url_from_text(raw_url)

        # 第一步：检查视频地址缓存（用提取后的纯 URL 精确匹配）
        cached = get_video_cache_by_url(clean_url)
        if cached and cached.get("status") == "completed":
            # 命中缓存，直接返回
            author = get_author_by_douyin_id(
                cached.get("author_id", "") if cached.get("author_id") else ""
            )
            if not author and cached.get("author_id"):
                # 尝试从 authors 表查询
                pass
            print(f"[解析链接] 视频地址缓存命中，直接返回: {clean_url}")
            return {
                "status": "cached",
                "restaurant": _cache_to_restaurant(cached),
                "author_id": cached.get("author_id", ""),
                "message": "已从缓存加载",
                "is_background_running": False,
                "background_progress": None,
            }

        # 第二步：解析抖音链接获取视频和博主信息
        video_info = await parse_douyin_link(raw_url)
        author_douyin_id = video_info.get("author_id", "")
        author_sec_uid = video_info.get("author_sec_uid", "")
        vid = video_info.get("video_id", "")

        if not author_douyin_id:
            author_douyin_id = f"video_{vid}"
            print(f"[解析链接] 未获取到博主 ID，使用视频 ID 兜底: {author_douyin_id}")

        # 第三步：检查该视频是否已解析过（用 video_id 判断）
        video_cache_by_id = get_video_cache_by_id(vid)
        if video_cache_by_id and video_cache_by_id.get("status") == "completed":
            # 视频已解析过，但 URL 不同（比如同一个视频多个分享格式）
            # 更新该 URL 的缓存记录
            update_video_cache_restaurant(clean_url, video_cache_by_id["restaurant_id"],
                                          {"name": video_cache_by_id.get("restaurant_name", "")})
            print(f"[解析链接] 视频 {vid} 已解析过（URL 不同），更新缓存")

        # 第四步：查询或创建博主记录
        existing_author = get_author_by_douyin_id(author_douyin_id)
        if existing_author:
            author_id = existing_author["id"]
            author_record = existing_author
        else:
            author_record = upsert_author({
                "douyin_uid": author_douyin_id,
                "sec_uid": author_sec_uid,
                "name": video_info.get("author_name", "未知博主"),
                "avatar_url": video_info.get("author_avatar", ""),
            })
            author_id = author_record["id"]

        # 第五步：为当前视频创建/更新缓存记录（parsing 状态）
        upsert_video_cache({
            "video_url": clean_url,
            "video_id": vid,
            "author_id": author_id,
            "status": "parsing",
        })

        # 第六步：快速解析当前视频（不获取评论，不等待其他视频）
        parse_result = await parse_single_video_fast(clean_url, video_info, author_id)
        restaurant = parse_result.get("restaurant")

        # 第七步：建立博主-店铺关联（当前视频的店铺）
        is_new_restaurant = False
        if restaurant:
            existing = get_restaurant_by_amap_id(restaurant["amap_id"])
            restaurant_id = existing["id"] if existing else None
            if not existing:
                saved = upsert_restaurant({
                    "name": restaurant["name"],
                    "address": restaurant["address"],
                    "city": restaurant["city"],
                    "latitude": restaurant["latitude"],
                    "longitude": restaurant["longitude"],
                    "amap_id": restaurant["amap_id"],
                    "category": restaurant.get("category", ""),
                })
                restaurant_id = saved["id"]
                is_new_restaurant = True
            if restaurant_id:
                link_author_restaurant(author_id, restaurant_id, vid)

        # 第八步：自动关注博主
        follow_author(req.user_id, author_id)

        # 第九步：启动后台任务解析博主历史视频
        # 已入库博主检查是否有未完成的后台任务；新博主直接创建任务
        latest_task = get_latest_bg_task(author_id)
        should_start_bg = (
            latest_task is None  # 新博主，从未创建过后台任务
            or latest_task.get("status") in ("completed", "failed")  # 上次任务已结束
        )
        is_bg_running = False
        if should_start_bg and author_sec_uid:
            background_tasks.add_task(
                parse_author_all_videos_background,
                author_id,
                author_sec_uid,
                vid,
            )
            is_bg_running = True
            print(f"[解析链接] 已启动后台任务，异步解析博主 {author_id} 的历史视频")
        elif latest_task and latest_task.get("status") in ("pending", "running"):
            is_bg_running = True

        # 第十步：返回结果
        return {
            "status": "parsed",
            "restaurant": restaurant,
            "author": author_record,
            "author_id": author_id,
            "message": _build_message(parse_result, is_new_restaurant, is_bg_running),
            "is_background_running": is_bg_running,
            "background_progress": _build_progress_info(latest_task) if is_bg_running else None,
        }

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"[解析链接] 未知错误: {e}")
        raise HTTPException(status_code=500, detail=f"解析失败: {str(e)}")


def _cache_to_restaurant(cached: dict) -> dict:
    """将视频缓存记录转换为餐厅响应格式"""
    if cached.get("status") != "completed":
        return None
    return {
        "name": cached.get("restaurant_name", ""),
        "address": cached.get("restaurant_address", ""),
        "city": cached.get("restaurant_city", ""),
        "latitude": cached.get("restaurant_lat"),
        "longitude": cached.get("restaurant_lng"),
        "amap_id": cached.get("restaurant_amap_id", ""),
        "category": cached.get("restaurant_category", ""),
    }


def _build_message(parse_result: dict, is_new_restaurant: bool, is_bg_running: bool) -> str:
    """构建返回给前端的消息文本"""
    status = parse_result.get("status", "")
    if status == "saved":
        msg = "已识别店铺并添加到地图"
        if is_bg_running:
            msg += "，博主其他探店视频正在后台解析中"
    elif status == "no_location":
        msg = "视频有店铺信息但未能获取坐标"
    elif status == "amap_not_found":
        msg = "未能在高德地图找到该店铺"
    else:
        msg = "未能识别到具体店铺"
        if is_bg_running:
            msg += "，博主其他视频正在后台解析"
    return msg


def _build_progress_info(task: dict | None) -> dict | None:
    """将后台任务记录转换为前端进度提示"""
    if not task:
        return None
    return {
        "status": task.get("status", ""),
        "total_videos": task.get("total_videos", 0),
        "processed_videos": task.get("processed_videos", 0),
        "new_restaurants_found": task.get("new_restaurants_found", 0),
        "task_type": task.get("task_type", ""),
    }


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


@app.get("/api/restaurants/{restaurant_id}/videos")
async def get_restaurant_videos(restaurant_id: str):
    """
    获取某个店铺关联的所有视频信息
    返回：[{video_id, author_id, author_name, author_avatar_url, created_at}]
    """
    try:
        videos = get_videos_by_restaurant(restaurant_id)
        return {"videos": videos}
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


@app.get("/api/parse-status/{author_id}")
async def get_parse_status(author_id: str):
    """
    查询博主的后台解析任务进度
    前端在用户提交链接后，定时轮询此接口更新进度提示
    """
    try:
        task = get_latest_bg_task(author_id)
        if not task:
            return {
                "has_task": False,
                "status": "none",
                "message": "暂无后台任务",
            }

        return {
            "has_task": True,
            "status": task.get("status", ""),
            "task_type": task.get("task_type", ""),
            "total_videos": task.get("total_videos", 0),
            "processed_videos": task.get("processed_videos", 0),
            "new_restaurants_found": task.get("new_restaurants_found", 0),
            "started_at": task.get("started_at"),
            "completed_at": task.get("completed_at"),
            "message": _build_task_message(task),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


def _build_task_message(task: dict) -> str:
    """根据任务状态构建友好的提示文本"""
    status = task.get("status", "")
    processed = task.get("processed_videos", 0)
    total = task.get("total_videos", 0)
    new_count = task.get("new_restaurants_found", 0)

    if status == "pending":
        return "正在准备解析博主其他视频，请稍候..."
    elif status == "running":
        if total > 0:
            return f"正在解析博主其他探店视频（{processed}/{total}）..."
        return f"正在解析博主历史视频（已处理 {processed} 个）..."
    elif status == "completed":
        if new_count > 0:
            return f"已完成博主历史视频解析，发现 {new_count} 家新店铺"
        return "已完成博主历史视频解析"
    elif status == "failed":
        return f"后台解析遇到问题：{task.get('error_message', '未知错误')}"
    return ""


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
# 手动添加店铺接口
# ─────────────────────────────────────────

@app.post("/api/manual-add-restaurant")
async def manual_add_restaurant(req: ManualAddRestaurantRequest):
    """
    用户手动添加店铺（当 AI 无法识别时）

    流程：
    1. 从视频缓存中获取 video_id 和 author_id
    2. 调用高德地图搜索店铺坐标
    3. 入库 restaurants 表
    4. 关联 author_restaurants 表
    5. 更新 video_parse_cache 状态为 completed
    """
    try:
        # 参数验证
        if not req.restaurant_name or len(req.restaurant_name.strip()) < 2:
            raise HTTPException(status_code=400, detail="店铺名称至少需要 2 个字符")
        if not req.city or len(req.city.strip()) < 2:
            raise HTTPException(status_code=400, detail="请选择所在城市")

        # 从视频缓存中获取 video_id 和 author_id
        clean_url = extract_url_from_text(req.video_url)
        cached = get_video_cache_by_url(clean_url)

        if not cached:
            raise HTTPException(status_code=404, detail="未找到该视频的解析记录，请先解析视频")

        video_id = cached.get("video_id", "")
        author_id = cached.get("author_id", "")

        if not video_id or not author_id:
            raise HTTPException(status_code=400, detail="视频信息不完整，无法添加店铺")

        # 调用高德地图搜索
        restaurant_data = {
            "name": req.restaurant_name.strip(),
            "city": req.city.strip(),
            "category": req.category.strip() if req.category else "",
        }

        search_results = await batch_search_restaurants([restaurant_data])

        if not search_results:
            raise HTTPException(
                status_code=404,
                detail=f"高德地图未找到「{req.restaurant_name}」，请检查店铺名称和城市是否正确"
            )

        # 取第一条搜索结果
        amap_result = search_results[0]
        restaurant_data.update({
            "address": amap_result.get("address", ""),
            "latitude": amap_result.get("latitude"),
            "longitude": amap_result.get("longitude"),
            "amap_id": amap_result.get("amap_id"),
        })

        # 检查店铺是否已存在
        existing = get_restaurant_by_amap_id(restaurant_data["amap_id"])
        if existing:
            restaurant_id = existing["id"]
            print(f"[手动添加] 店铺已存在: {existing['name']}")
        else:
            # 入库新店铺
            saved = upsert_restaurant({
                "name": restaurant_data["name"],
                "address": restaurant_data["address"],
                "city": restaurant_data["city"],
                "latitude": restaurant_data["latitude"],
                "longitude": restaurant_data["longitude"],
                "amap_id": restaurant_data["amap_id"],
                "category": restaurant_data.get("category", ""),
            })
            restaurant_id = saved["id"]
            print(f"[手动添加] 新店铺入库: {restaurant_data['name']}")

        # 关联博主-店铺
        link_author_restaurant(author_id, restaurant_id, video_id)

        # 更新视频缓存状态
        update_video_cache_restaurant(clean_url, restaurant_id, restaurant_data)

        # 自动关注博主（如果尚未关注）
        try:
            follow_author(req.user_id, author_id)
        except Exception:
            pass  # 已关注时会报错，忽略

        return {
            "status": "success",
            "restaurant": restaurant_data,
            "restaurant_id": restaurant_id,
            "message": "店铺已添加到地图",
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"[手动添加] 未知错误: {e}")
        raise HTTPException(status_code=500, detail=f"添加失败: {str(e)}")


# ─────────────────────────────────────────
# 本地开发启动入口
# ─────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    # 本地开发时运行：python main.py
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
