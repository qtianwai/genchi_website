# FastAPI 主程序
# 定义所有 API 路由，是后端的入口文件
# iOS App 通过这些接口与后端通信

import os
import asyncio
from datetime import datetime
from fastapi import FastAPI, HTTPException, Header, BackgroundTasks, Depends, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from douyin_parser import parse_douyin_link, fetch_author_videos, fetch_video_comments, fetch_video_detail_extra, extract_url_from_text, extract_video_id_from_url, poll_comment_replies_for_confidence
from ai_extractor import extract_restaurants_from_video, extract_restaurants_priority, extract_restaurants_with_replies, filter_food_video_titles
from ai_extractor import extract_restaurants_from_video, extract_restaurants_priority, extract_restaurants_with_replies
from amap_service import batch_search_restaurants, search_restaurant_for_review, get_poi_detail
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
    is_author_in_cool_down,  # 新增：博主扫描冷却期检查（优化 3.3）
    get_videos_by_restaurant,
    # 新增：博主自动更新相关（v2.4）
    enable_author_auto_update,
    # 新增：后台人工复核相关（v3.0）
    is_admin_user, get_review_list, get_video_cache_by_cache_id,
    admin_confirm_correct, admin_confirm_empty, admin_correct_restaurant, admin_skip,
    # 新增：用户自建推荐店铺相关（v4.0）
    get_user_created_restaurants, add_user_restaurant, remove_user_restaurant,
    # 新增：用户 profile 相关
    get_user_profile, upsert_user_profile,
    # 新增：避雷、删除、分组、收藏理由、博主统计（v5.0）
    avoid_restaurant, unavoid_restaurant, get_avoided_restaurants,
    delete_restaurant_for_user,
    update_favorite_note,
    get_user_groups, create_user_group, delete_user_group,
    add_restaurant_to_group, remove_restaurant_from_group, get_group_restaurants,
    get_author_stats,
)

load_dotenv()

# 读取调试模式配置
DEBUG_MODE = os.getenv("DEBUG_MODE", "false").lower() == "true"
DEBUG_MAX_VIDEOS = int(os.getenv("DEBUG_MAX_VIDEOS", "5"))

# 读取评论回复调用限制配置
COMMENT_REPLY_DAILY_LIMIT = int(os.getenv("COMMENT_REPLY_DAILY_LIMIT", "100"))

# 全局计数器：评论回复接口每日调用次数（内存存储，重启后重置）
_comment_reply_calls_today = 0
_comment_reply_calls_date = datetime.now().date()

def can_call_comment_reply() -> bool:
    """检查今日是否还能调用评论回复接口"""
    global _comment_reply_calls_today, _comment_reply_calls_date

    # 检查日期是否变化，变化则重置计数器
    today = datetime.now().date()
    if today != _comment_reply_calls_date:
        _comment_reply_calls_today = 0
        _comment_reply_calls_date = today

    return _comment_reply_calls_today < COMMENT_REPLY_DAILY_LIMIT

def increment_comment_reply_calls(count: int = 1):
    """增加评论回复调用次数"""
    global _comment_reply_calls_today
    _comment_reply_calls_today += count
    print(f"[评论回复限制] 今日已调用 {_comment_reply_calls_today}/{COMMENT_REPLY_DAILY_LIMIT} 次")

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
    scope: str = "follow_all"  # 入库范围：
                               # "follow_all"  → 关注博主 + 触发后台全量解析（默认）
                               # "single_only" → 仅添加本店铺，不关注博主，不触发后台任务

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

class WechatLoginRequest(BaseModel):
    code: str               # 微信授权后返回的 code

# v5.0 新增：避雷、删除、分组、收藏理由相关请求模型
class AvoidRestaurantRequest(BaseModel):
    user_id: str
    restaurant_id: str

class DeleteRestaurantRequest(BaseModel):
    user_id: str
    restaurant_id: str

class UpdateFavoriteNoteRequest(BaseModel):
    user_id: str
    restaurant_id: str
    note: str

class CreateGroupRequest(BaseModel):
    user_id: str
    name: str

class AddToGroupRequest(BaseModel):
    user_id: str
    group_id: str
    restaurant_id: str


# ─────────────────────────────────────────
# 健康检查
# ─────────────────────────────────────────

@app.get("/")
async def health_check():
    """服务健康检查，Railway 部署后可用此接口验证服务是否正常"""
    return {"status": "ok", "service": "跟吃后端"}


# ─────────────────────────────────────────
# Apple App Site Association（微信 Universal Link 验证）
# 微信 SDK 会请求此文件验证域名所有权
# ─────────────────────────────────────────

from fastapi.responses import JSONResponse

@app.get("/.well-known/apple-app-site-association")
async def apple_app_site_association():
    """
    Apple Universal Link 验证文件
    微信 SDK 和 iOS 系统会请求此接口验证域名与 App 的关联关系
    Team ID 可在 Apple Developer 后台 → Membership 页面查看
    """
    return JSONResponse(content={
        "applinks": {
            "apps": [],
            "details": [
                {
                    # 格式：TeamID.BundleID
                    # TODO: 将 YOUR_TEAM_ID 替换为你的 Apple Developer Team ID
                    "appID": "YOUR_TEAM_ID.com.qtianwai.genchi",
                    "paths": ["/wechat/*"]
                }
            ]
        }
    })


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
        # 短信发送失败时，直接返回验证码（方便调试，正式上线前移除）
        return {"status": "ok", "message": "短信发送失败，验证码已在响应中返回", "debug_code": code}

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


@app.post("/api/auth/wechat-login")
async def wechat_login(req: WechatLoginRequest):
    """
    微信登录接口

    流程：
    1. iOS 端调用微信 SDK 获取 code
    2. 后端用 code 换取 access_token 和 openid
    3. 用 openid 生成确定性 user_id
    4. 返回 user_id 和 access_token

    配置：需要在 .env 中配置 WECHAT_APP_ID 和 WECHAT_APP_SECRET
    """
    import httpx

    code = req.code.strip()
    if not code:
        raise HTTPException(status_code=400, detail="微信授权码不能为空")

    # 从环境变量读取微信配置
    wechat_app_id = os.getenv("WECHAT_APP_ID", "")
    wechat_app_secret = os.getenv("WECHAT_APP_SECRET", "")

    if not wechat_app_id or not wechat_app_secret:
        raise HTTPException(
            status_code=500,
            detail="服务器未配置微信登录，请联系管理员"
        )

    # 调用微信接口换取 access_token 和 openid
    wechat_url = "https://api.weixin.qq.com/sns/oauth2/access_token"
    params = {
        "appid": wechat_app_id,
        "secret": wechat_app_secret,
        "code": code,
        "grant_type": "authorization_code",
    }

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(wechat_url, params=params, timeout=10)
            result = response.json()

            # 检查微信接口返回的错误
            if "errcode" in result:
                error_msg = result.get("errmsg", "未知错误")
                print(f"[微信登录] 微信接口返回错误: {result}")
                raise HTTPException(
                    status_code=400,
                    detail=f"微信登录失败: {error_msg}"
                )

            # 获取 openid
            openid = result.get("openid", "")
            if not openid:
                raise HTTPException(status_code=400, detail="微信登录失败：未获取到用户标识")

            # 用 openid 生成确定性 user_id（与手机号登录类似）
            import uuid
            namespace = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
            user_id = str(uuid.uuid5(namespace, f"wechat:{openid}"))

            # 生成 access_token（简化版，直接用 user_id）
            access_token = user_id

            return {
                "status": "ok",
                "user_id": user_id,
                "access_token": access_token,
            }

    except httpx.RequestError as e:
        print(f"[微信登录] 网络请求失败: {e}")
        raise HTTPException(status_code=500, detail="微信登录失败：网络错误")
    except HTTPException:
        raise
    except Exception as e:
        print(f"[微信登录] 未知错误: {e}")
        raise HTTPException(status_code=500, detail=f"微信登录失败: {str(e)}")


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
            "avg_price": restaurant_data.get("avg_price"),    # 人均消费（元）
            "photo_url": restaurant_data.get("photo_url", ""), # 店铺封面图
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
    data_source: str = "user_submit",  # 数据来源标识
) -> dict:
    """
    快速解析单个视频的核心逻辑（优化版：使用 parse_douyin_link 已获取的扩展信息）。

    优化1：parse_douyin_link 已获取完整的扩展信息（话题标签、城市、评论），
           此函数不再单独调用 fetch_video_detail_extra，节省 1 次 JustOneAPI 调用。

    v2.6 优化：置信度 medium 或 high 但缺分店信息时，调用评论回复接口补充信息。
    v2.5 新增：记录 parse_reason、data_source、api_cost、api_cost_note。
    """
    vid = video_info.get("video_id", "")
    title = video_info.get("title", "")
    author_name = video_info.get("author_name", "")

    # 使用 parse_douyin_link 已获取的扩展信息（优化1：避免重复调用）
    hashtags = video_info.get("hashtags", [])
    city = video_info.get("city_name", "未知")
    author_liked_comments = video_info.get("author_liked_comments", [])
    hot_comments = video_info.get("hot_comments", [])
    all_comments = video_info.get("all_comments", [])
    hot_comments_raw = video_info.get("hot_comments_raw", [])

    # API 成本统计（parse_douyin_link 已消耗：share-url-transfer + get-video-detail + get-video-comment）
    # 单价参考 JustOneAPI 官网，此处按每次调用 0.001 元估算
    COST_PER_CALL = 0.1  # 元/次
    api_calls = [
        "share-url-transfer/v1（解析短链）",
        "get-video-detail/v2（获取视频详情+话题标签+城市）",
        "get-video-comment/v1（获取评论）",
    ]
    api_cost = len(api_calls) * COST_PER_CALL

    # AI 提取（使用完整信息，优先级算法）
    extracted = await extract_restaurants_priority(
        video_title=title,
        author_name=author_name,
        hashtags=hashtags,
        city_name=city,
        author_liked_comments=author_liked_comments,
        hot_comments=hot_comments,
        all_comments=all_comments,
    )

    # 收集 parse_reason（无论是否提取到店铺）
    parse_reason = ""
    if extracted:
        if extracted[0].get("_no_result"):
            parse_reason = extracted[0].get("reason", "AI未识别到店铺")
        else:
            parse_reason = extracted[0].get("reason", "")

    # 置信度判断（v2.6 优化：high 但缺分店信息时也调用评论回复）
    should_call_replies = extracted and not extracted[0].get("_no_result") and extracted[0].get("confidence") == "medium"
    if not should_call_replies and extracted and not extracted[0].get("_no_result") and extracted[0].get("confidence") == "high":
        parsed_name = extracted[0].get("name", "")
        if not any(keyword in parsed_name for keyword in ["店", "广场", "分店", "路", "街"]):
            should_call_replies = True
    if should_call_replies:
        if can_call_comment_reply():
            print(f"[解析策略] 置信度 medium 或缺分店信息，调用评论回复接口补充信息")
            reply_data = await poll_comment_replies_for_confidence(
                hot_comments_raw=hot_comments_raw,
                author_uid=author_id,
                max_polls=2,
            )
            polls_used = reply_data.get("polls_used", 0)
            increment_comment_reply_calls(polls_used)

            if polls_used > 0:
                # 记录评论回复接口调用成本
                for i in range(polls_used):
                    api_calls.append(f"get-video-sub-comment/v1（评论回复#{i+1}）")
                api_cost += polls_used * COST_PER_CALL

            if reply_data.get("polled_replies"):
                extracted_with_replies = await extract_restaurants_with_replies(
                    video_title=title,
                    author_name=author_name,
                    hashtags=hashtags,
                    city_name=city,
                    author_liked_comments=author_liked_comments,
                    hot_comments=hot_comments,
                    all_comments=all_comments,
                    polled_replies=reply_data.get("polled_replies", []),
                )
                if extracted_with_replies:
                    new_conf = extracted_with_replies[0].get("confidence") if not extracted_with_replies[0].get("_no_result") else None
                    old_conf = extracted[0].get("confidence") if not extracted[0].get("_no_result") else None
                    new_name = extracted_with_replies[0].get("name", "")
                    old_name = extracted[0].get("name", "")
                    if new_conf == "high" or (new_conf == old_conf and len(new_name) > len(old_name)):
                        print(f"[解析策略] 评论回复优化结果: {old_name} → {new_name}")
                        extracted = extracted_with_replies
                        parse_reason = extracted[0].get("reason", parse_reason) if not extracted[0].get("_no_result") else extracted[0].get("reason", parse_reason)
        else:
            print(f"[解析策略] 今日评论回复调用已达上限，跳过")

    # 构建 API 成本说明
    api_cost_note = "；".join(api_calls) + f"；合计 {len(api_calls)} 次调用，约 ¥{api_cost:.4f}"

    # 过滤掉 _no_result 标记（只是用于传递 reason，不是真实店铺）
    real_extracted = [r for r in extracted if not r.get("_no_result")] if extracted else []

    if not real_extracted:
        # 未提取到店铺，更新缓存记录 parse_reason 和 data_source
        upsert_video_cache({
            "video_url": video_url,
            "video_id": vid,
            "author_id": author_id,
            "status": "failed",
            "parse_reason": parse_reason or "AI未识别到店铺",
            "data_source": data_source,
            "api_cost": api_cost,
            "api_cost_note": api_cost_note,
        })
        return {"restaurant": None, "status": "not_found"}

    # 调用高德搜索坐标
    restaurant_data = real_extracted[0]
    search_results = await batch_search_restaurants([restaurant_data])

    if not search_results:
        upsert_video_cache({
            "video_url": video_url,
            "video_id": vid,
            "author_id": author_id,
            "status": "failed",
            "restaurant_name": restaurant_data.get("name", ""),
            "restaurant_city": restaurant_data.get("city", ""),
            "error_message": "高德地图未找到该店铺",
            "parse_reason": parse_reason or f"AI识别到店铺「{restaurant_data.get('name')}」但高德地图未找到",
            "data_source": data_source,
            "api_cost": api_cost,
            "api_cost_note": api_cost_note,
        })
        return {"restaurant": None, "status": "amap_not_found"}

    amap_result = search_results[0]
    restaurant_data.update({
        "address": amap_result.get("address", ""),
        "latitude": amap_result.get("latitude"),
        "longitude": amap_result.get("longitude"),
        "amap_id": amap_result.get("amap_id"),
        "avg_price": amap_result.get("avg_price"),      # 人均消费（元）
        "photo_url": amap_result.get("photo_url", ""),  # 店铺封面图
        # 附加新字段，供 _save_video_restaurant 写入缓存
        "parse_reason": parse_reason,
        "data_source": data_source,
        "api_cost": api_cost,
        "api_cost_note": api_cost_note,
    })

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

    优化 3.2：新增 AI 标题过滤，过滤掉非美食/探店类视频，零 JustOneAPI 成本
    优化 3.3：新增冷却期检查，1 天内重复扫描时直接跳过

    调试模式：当 DEBUG_MODE=true 时，最多解析 DEBUG_MAX_VIDEOS 条视频
    """
    if not sec_uid:
        print(f"[后台解析] 博主无 sec_uid，跳过历史视频解析: {author_id}")
        return

    # 优化 3.3：冷却期检查（1 天内不重复扫描）
    if is_author_in_cool_down(author_id, hours=24):
        recent_task = get_latest_bg_task(author_id)
        task_status = recent_task.get("status", "unknown") if recent_task else "unknown"
        print(f"[后台解析] 博主 {author_id} 在冷却期内（最近任务状态: {task_status}），跳过本次扫描")
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

    # 调试模式：限制解析数量
    if DEBUG_MODE and len(video_list) > DEBUG_MAX_VIDEOS:
        print(f"[后台解析] 调试模式已启用，限制解析数量: {len(video_list)} -> {DEBUG_MAX_VIDEOS}")
        video_list = video_list[:DEBUG_MAX_VIDEOS]

    # 创建后台任务记录
    task = create_bg_task(author_id, "full_scan")
    task_id = task.get("id", "")
    update_bg_task_started(task_id)

    # 优化 3.2：AI 标题过滤 - 过滤掉非美食/探店类视频
    food_videos = await filter_food_video_titles(video_list)

    # 过滤掉数据库中已有成功解析记录的视频（使用 video_id）
    pending_videos = []
    for video in food_videos:
        vid = video.get("video_id", "")
        existing_cache = get_video_cache_by_id(vid)
        if existing_cache and existing_cache.get("status") == "completed":
            print(f"[后台解析] 视频 {vid} 已解析过，跳过")
            continue
        pending_videos.append(video)

    print(f"[后台解析] AI 过滤完成: {len(video_list)} -> {len(food_videos)} 条美食视频 -> {len(pending_videos)} 条待解析")

    if not pending_videos:
        print(f"[后台解析] 博主 {author_id} 无需解析的历史视频")
        complete_bg_task(task_id, 0)
        return

    print(f"[后台解析] 开始解析博主 {author_id} 的 {len(pending_videos)} 个历史视频...")

    saved_count = 0
    for i, video in enumerate(pending_videos):
        vid = video.get("video_id", "")
        title = video.get("title", "")

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
            # 获取视频扩展信息（P1:标签+城市+评论）
            # 后台解析消耗：get-video-detail/v2 + get-video-comment/v1
            COST_PER_CALL = 0.1
            extra = await fetch_video_detail_extra(vid, author_id)
            api_calls_bg = [
                "get-video-detail/v2（获取视频详情+话题标签+城市）",
                "get-video-comment/v1（获取评论）",
            ]
            api_cost_bg = len(api_calls_bg) * COST_PER_CALL

            # AI 提取（v2.3：废弃降级算法，优先级算法返回空时直接返回空）
            extracted = await extract_restaurants_priority(
                video_title=title,
                author_name="",
                hashtags=extra.get("hashtags", []),
                city_name=extra.get("city_name", "未知"),
                author_liked_comments=extra.get("author_liked_comments", []),
                hot_comments=extra.get("hot_comments", []),
                all_comments=extra.get("all_comments", []),
            )

            # 收集 parse_reason
            parse_reason_bg = ""
            if extracted:
                if extracted[0].get("_no_result"):
                    parse_reason_bg = extracted[0].get("reason", "AI未识别到店铺")
                else:
                    parse_reason_bg = extracted[0].get("reason", "")

            # 置信度判断（v2.6 优化：high 但缺分店信息时也调用评论回复）
            should_call_replies = extracted and not extracted[0].get("_no_result") and extracted[0].get("confidence") == "medium"
            if not should_call_replies and extracted and not extracted[0].get("_no_result") and extracted[0].get("confidence") == "high":
                parsed_name = extracted[0].get("name", "")
                if not any(keyword in parsed_name for keyword in ["店", "广场", "分店", "路", "街"]):
                    should_call_replies = True
            if should_call_replies:
                if can_call_comment_reply():
                    conf_tag = "medium" if (extracted and not extracted[0].get("_no_result") and extracted[0].get("confidence") == "medium") else "缺分店"
                    print(f"[后台解析] 视频 {vid} 置信度 {conf_tag}，调用评论回复补充")
                    reply_data = await poll_comment_replies_for_confidence(
                        hot_comments_raw=extra.get("hot_comments_raw", []),
                        author_uid=author_id,
                        max_polls=2,
                    )
                    polls_used = reply_data.get("polls_used", 0)
                    increment_comment_reply_calls(polls_used)
                    if polls_used > 0:
                        for i_r in range(polls_used):
                            api_calls_bg.append(f"get-video-sub-comment/v1（评论回复#{i_r+1}）")
                        api_cost_bg += polls_used * COST_PER_CALL
                    if reply_data.get("polled_replies"):
                        extracted_with_replies = await extract_restaurants_with_replies(
                            video_title=title,
                            author_name="",
                            hashtags=extra.get("hashtags", []),
                            city_name=extra.get("city_name", "未知"),
                            author_liked_comments=extra.get("author_liked_comments", []),
                            hot_comments=extra.get("hot_comments", []),
                            all_comments=extra.get("all_comments", []),
                            polled_replies=reply_data.get("polled_replies", []),
                        )
                        if extracted_with_replies:
                            new_conf = extracted_with_replies[0].get("confidence") if not extracted_with_replies[0].get("_no_result") else None
                            old_conf = extracted[0].get("confidence") if not extracted[0].get("_no_result") else None
                            new_name = extracted_with_replies[0].get("name", "")
                            old_name = extracted[0].get("name", "")
                            if new_conf == "high" or (new_conf == old_conf and len(new_name) > len(old_name)):
                                print(f"[后台解析] 视频 {vid} 评论回复优化: {old_name} → {new_name}")
                                extracted = extracted_with_replies
                                parse_reason_bg = extracted[0].get("reason", parse_reason_bg) if not extracted[0].get("_no_result") else extracted[0].get("reason", parse_reason_bg)
                else:
                    print(f"[后台解析] 今日评论回复调用已达上限，跳过视频 {vid}")

            api_cost_note_bg = "；".join(api_calls_bg) + f"；合计 {len(api_calls_bg)} 次调用，约 ¥{api_cost_bg:.4f}"

            # 过滤掉 _no_result 标记
            real_extracted = [r for r in extracted if not r.get("_no_result")] if extracted else []

            if real_extracted:
                # 高德搜索
                search_results = await batch_search_restaurants([real_extracted[0]])
                if search_results:
                    amap_result = search_results[0]
                    real_extracted[0].update({
                        "address": amap_result.get("address", ""),
                        "latitude": amap_result.get("latitude"),
                        "longitude": amap_result.get("longitude"),
                        "amap_id": amap_result.get("amap_id"),
                        "avg_price": amap_result.get("avg_price"),      # 人均消费（元）
                        "photo_url": amap_result.get("photo_url", ""),  # 店铺封面图
                        "parse_reason": parse_reason_bg,
                        "data_source": "background_scan",
                        "api_cost": api_cost_bg,
                        "api_cost_note": api_cost_note_bg,
                    })
                    result = _save_video_restaurant(video_url, vid, author_id, real_extracted[0])
                    if result["status"] == "saved":
                        saved_count += 1
                else:
                    # 高德搜不到，更新缓存记录失败原因
                    upsert_video_cache({
                        "video_url": video_url,
                        "video_id": vid,
                        "author_id": author_id,
                        "status": "failed",
                        "restaurant_name": real_extracted[0].get("name", ""),
                        "error_message": "高德地图未找到该店铺",
                        "parse_reason": parse_reason_bg or f"AI识别到店铺「{real_extracted[0].get('name')}」但高德地图未找到",
                        "data_source": "background_scan",
                        "api_cost": api_cost_bg,
                        "api_cost_note": api_cost_note_bg,
                    })
            else:
                # 未提取到店铺，更新缓存记录原因
                upsert_video_cache({
                    "video_url": video_url,
                    "video_id": vid,
                    "author_id": author_id,
                    "status": "failed",
                    "parse_reason": parse_reason_bg or "AI未识别到店铺",
                    "data_source": "background_scan",
                    "api_cost": api_cost_bg,
                    "api_cost_note": api_cost_note_bg,
                })

            # 更新缓存状态（如果已有记录但未完成）
            if existing_cache := get_video_cache_by_id(vid):
                if existing_cache.get("status") not in ("completed", "failed"):
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
    debug_info = f" (调试模式: 限制 {DEBUG_MAX_VIDEOS} 条)" if DEBUG_MODE else ""
    print(f"[后台解析] 博主 {author_id} 后台解析完成,新增 {saved_count} 家店铺{debug_info}")


@app.post("/api/parse-link")
async def parse_link(req: ParseLinkRequest, background_tasks: BackgroundTasks):
    """
    解析抖音分享链接（新流程）

    优化策略：
    1. 先从 URL 提取 video_id，用 video_id 精确匹配缓存（同一视频多链接复用）
    2. 未命中则解析当前视频（优化1：一次调用获取所有信息），立即返回结果
    3. 启动后台任务异步解析博主历史探店视频（不阻塞用户）
       - 优化3.3：冷却期检查（1 天内不重复扫描）
       - 优化3.2：AI 标题过滤（非美食视频跳过）
    """
    try:
        raw_url = req.url.strip()
        # 先提取纯 URL（去掉分享文字前缀），确保缓存命中不受分享格式影响
        clean_url = extract_url_from_text(raw_url)

        # 第一步：尝试从 URL 提取 video_id（优化2：支持同一视频多个分享格式）
        vid = extract_video_id_from_url(clean_url)

        # 第二步：检查视频缓存
        # 优先用 video_id 精确匹配（同一视频多链接共享缓存）
        if vid:
            cached = get_video_cache_by_id(vid)
            if cached and cached.get("status") == "completed":
                # 命中缓存，直接返回（同时更新该 URL 的缓存记录）
                print(f"[解析链接] 视频 ID 缓存命中，直接返回: video_id={vid}")
                update_video_cache_restaurant(clean_url, cached.get("restaurant_id", ""), {
                    "name": cached.get("restaurant_name", ""),
                })
                return {
                    "status": "cached",
                    "restaurant": _cache_to_restaurant(cached),
                    "author_id": cached.get("author_id", ""),
                    "message": "已从缓存加载",
                    "is_background_running": False,
                    "background_progress": None,
                }

        # 第三步：检查 URL 精确匹配（兜底）
        cached = get_video_cache_by_url(clean_url)
        if cached and cached.get("status") == "completed":
            print(f"[解析链接] 视频地址缓存命中，直接返回: {clean_url}")
            return {
                "status": "cached",
                "restaurant": _cache_to_restaurant(cached),
                "author_id": cached.get("author_id", ""),
                "message": "已从缓存加载",
                "is_background_running": False,
                "background_progress": None,
            }

        # 第四步：解析抖音链接获取视频和博主信息
        # 优化1：parse_douyin_link 一次调用获取完整信息（基础+扩展+评论）
        video_info = await parse_douyin_link(raw_url)
        author_douyin_id = video_info.get("author_id", "")
        author_sec_uid = video_info.get("author_sec_uid", "")
        vid = video_info.get("video_id", "")

        if not author_douyin_id:
            author_douyin_id = f"video_{vid}"
            print(f"[解析链接] 未获取到博主 ID，使用视频 ID 兜底: {author_douyin_id}")

        # 第五步：再次检查 video_id 缓存（解析过程中可能其他请求已入库）
        video_cache_by_id = get_video_cache_by_id(vid)
        if video_cache_by_id and video_cache_by_id.get("status") == "completed":
            # 视频已解析过，但 URL 不同（比如同一个视频多个分享格式）
            # 更新该 URL 的缓存记录
            update_video_cache_restaurant(clean_url, video_cache_by_id["restaurant_id"],
                                          {"name": video_cache_by_id.get("restaurant_name", "")})
            print(f"[解析链接] 视频 {vid} 已解析过（解析中入库），更新缓存")

        # 第六步：查询或创建博主记录
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

        # 第七步：为当前视频创建/更新缓存记录（parsing 状态）
        upsert_video_cache({
            "video_url": clean_url,
            "video_id": vid,
            "author_id": author_id,
            "status": "parsing",
        })

        # 第八步：快速解析当前视频（使用已获取的完整信息，不再单独调用）
        parse_result = await parse_single_video_fast(clean_url, video_info, author_id, data_source="user_submit")
        restaurant = parse_result.get("restaurant")

        # 第九步：建立博主-店铺关联（当前视频的店铺）
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
                    "avg_price": restaurant.get("avg_price"),    # 人均消费（元）
                    "photo_url": restaurant.get("photo_url", ""), # 店铺封面图
                })
                restaurant_id = saved["id"]
                is_new_restaurant = True
            if restaurant_id:
                link_author_restaurant(author_id, restaurant_id, vid)

        # 第十步：自动关注博主（single_only 模式下跳过）
        if req.scope != "single_only":
            follow_author(req.user_id, author_id)

        # 第十一步：启用/重新激活博主的自动更新检测（single_only 模式下跳过）
        # 逻辑：
        # - 新博主：首次解析时自动启用
        # - 已有博主但自动更新被关闭：如果当前视频识别出了美食店铺，重新激活
        if req.scope != "single_only":
            try:
                from db import get_author_by_id
                existing_author_record = get_author_by_id(author_id)
                if existing_author_record:
                    auto_update_enabled = existing_author_record.get("auto_update_enabled", True)
                    if not auto_update_enabled and restaurant:
                        # 自动更新被关闭，但当前视频识别出了店铺，说明博主仍在更新，重新激活
                        enable_author_auto_update(author_id)
                        print(f"[解析链接] 博主 {author_id} 自动更新已重新激活（发现新美食视频）")
                    elif auto_update_enabled is None:
                        # 新博主（auto_update_enabled 为 NULL），首次解析时自动启用
                        enable_author_auto_update(author_id)
                        print(f"[解析链接] 新博主 {author_id} 自动更新已启用")
            except Exception as e:
                # 自动更新逻辑不应阻塞主流程
                print(f"[解析链接] 自动更新启用出错: {e}")

        # 第十二步：启动后台任务解析博主历史视频（single_only 模式下跳过）
        # 优化3.3：冷却期检查 - 1 天内不重复扫描
        is_bg_running = False
        latest_task = None
        if req.scope != "single_only":
            latest_task = get_latest_bg_task(author_id)
            should_start_bg = (
                latest_task is None  # 新博主，从未创建过后台任务
                or latest_task.get("status") in ("completed", "failed")  # 上次任务已结束
            )
            if should_start_bg and author_sec_uid:
                # 冷却期检查
                if is_author_in_cool_down(author_id, hours=24):
                    print(f"[解析链接] 博主 {author_id} 在冷却期内（24小时），跳过后台任务")
                else:
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
        else:
            print(f"[解析链接] single_only 模式，跳过关注博主和后台任务")

        # 第十三步：返回结果
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
    返回两类数据：
    - restaurants：用户关注的博主推荐的店铺（含博主头像信息）
    - user_restaurants：用户自建的推荐店铺（v4.0 新增）
    """
    try:
        data = get_map_restaurants_for_user(user_id)
        return data  # 已包含 restaurants 和 user_restaurants 两个字段
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 用户自建推荐店铺 API（v4.0 新增）
# ─────────────────────────────────────────

@app.get("/api/user-restaurants/search")
async def search_user_restaurant(name: str, city: str):
    """
    搜索高德 POI 候选店铺（用于用户自建推荐时选择）
    返回最多 5 条候选结果
    """
    try:
        if not name or len(name.strip()) < 2:
            raise HTTPException(status_code=400, detail="店铺名称至少需要 2 个字符")
        if not city or len(city.strip()) < 2:
            raise HTTPException(status_code=400, detail="请选择所在城市")

        # 复用 search_restaurant_for_review，返回多条候选（最多 5 条）
        results = await search_restaurant_for_review(name.strip(), city.strip())

        return {"results": results[:5]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


class UserRestaurantRequest(BaseModel):
    """用户自建推荐店铺请求体"""
    user_id: str
    amap_id: str
    restaurant_name: str
    address: str = ""
    city: str = ""
    latitude: float = 0.0
    longitude: float = 0.0
    category: str = ""
    note: str = ""
    avg_price: int | None = None  # 人均消费（元），来自高德搜索结果
    photo_url: str = ""           # 店铺封面图 URL，来自高德搜索结果


@app.post("/api/user-restaurants")
async def create_user_restaurant(req: UserRestaurantRequest):
    """
    用户自建推荐店铺
    流程：upsert restaurants（按 amap_id 去重）→ insert user_created_restaurants
    """
    try:
        if not req.restaurant_name or len(req.restaurant_name.strip()) < 2:
            raise HTTPException(status_code=400, detail="店铺名称至少需要 2 个字符")
        if not req.amap_id:
            raise HTTPException(status_code=400, detail="缺少高德 POI ID")

        # upsert restaurants（以 amap_id 为唯一键，避免重复）
        saved = upsert_restaurant({
            "name": req.restaurant_name.strip(),
            "address": req.address,
            "city": req.city,
            "latitude": req.latitude,
            "longitude": req.longitude,
            "amap_id": req.amap_id,
            "category": req.category,
            "avg_price": req.avg_price,    # 人均消费（元）
            "photo_url": req.photo_url,    # 店铺封面图
        })
        restaurant_id = saved.get("id")
        if not restaurant_id:
            raise HTTPException(status_code=500, detail="店铺入库失败")

        # 添加用户自建关联
        add_user_restaurant(req.user_id, restaurant_id, req.note)

        return {
            "status": "success",
            "restaurant_id": restaurant_id,
            "message": "店铺已添加到我的推荐",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/user-restaurants")
async def get_user_restaurants(user_id: str):
    """获取用户自建的所有推荐店铺列表"""
    try:
        data = get_user_created_restaurants(user_id)
        return {"restaurants": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/user-restaurants/{restaurant_id}")
async def delete_user_restaurant(restaurant_id: str, user_id: str):
    """
    删除用户自建推荐店铺
    只删除 user_created_restaurants 关联记录，不删 restaurants 表
    """
    try:
        remove_user_restaurant(user_id, restaurant_id)
        return {"status": "success", "message": "已从我的推荐中移除"}
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
# 收藏理由接口（v5.0 新增）
# ─────────────────────────────────────────

@app.post("/api/favorites/update-note")
async def update_note(req: UpdateFavoriteNoteRequest):
    """更新收藏理由（一个店铺只维护一条用户的收藏理由）"""
    try:
        result = update_favorite_note(req.user_id, req.restaurant_id, req.note)
        if not result:
            raise HTTPException(status_code=404, detail="未找到该收藏记录，请先收藏店铺")
        return {"status": "ok", "message": "收藏理由已更新"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 避雷店铺接口（v5.0 新增，前端文案统一用"避雷"）
# ─────────────────────────────────────────

@app.post("/api/restaurants/avoid")
async def avoid(req: AvoidRestaurantRequest):
    """避雷店铺"""
    try:
        result = avoid_restaurant(req.user_id, req.restaurant_id)
        return {"status": "ok", "data": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/restaurants/unavoid")
async def unavoid(req: AvoidRestaurantRequest):
    """取消避雷"""
    try:
        unavoid_restaurant(req.user_id, req.restaurant_id)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/restaurants/avoided")
async def get_avoided(user_id: str):
    """获取用户避雷的店铺列表"""
    try:
        data = get_avoided_restaurants(user_id)
        return {"restaurants": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 删除店铺接口（v5.0 新增，全局隐藏）
# ─────────────────────────────────────────

@app.post("/api/restaurants/delete")
async def delete_restaurant(req: DeleteRestaurantRequest):
    """删除店铺（对当前用户全局隐藏，不影响其他用户）"""
    try:
        result = delete_restaurant_for_user(req.user_id, req.restaurant_id)
        return {"status": "ok", "data": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 用户自定义分组接口（v5.0 新增）
# ─────────────────────────────────────────

@app.get("/api/groups")
async def list_groups(user_id: str):
    """获取用户的所有自定义分组"""
    try:
        groups = get_user_groups(user_id)
        return {"groups": groups}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/groups")
async def create_group(req: CreateGroupRequest):
    """创建自定义分组"""
    try:
        name = req.name.strip()
        if not name or len(name) > 20:
            raise HTTPException(status_code=400, detail="分组名称长度需在 1-20 字符之间")
        group = create_user_group(req.user_id, name)
        return {"status": "ok", "group": group}
    except HTTPException:
        raise
    except Exception as e:
        if "duplicate" in str(e).lower() or "unique" in str(e).lower():
            raise HTTPException(status_code=400, detail="已存在同名分组")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/groups/{group_id}")
async def remove_group(group_id: str, user_id: str):
    """删除自定义分组（级联删除分组内的店铺关联）"""
    try:
        delete_user_group(user_id, group_id)
        return {"status": "ok", "message": "分组已删除"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/groups/{group_id}/restaurants")
async def add_to_group(group_id: str, req: AddToGroupRequest):
    """添加店铺到分组"""
    try:
        result = add_restaurant_to_group(req.user_id, group_id, req.restaurant_id)
        return {"status": "ok", "data": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/groups/{group_id}/restaurants/{restaurant_id}")
async def remove_from_group(group_id: str, restaurant_id: str, user_id: str):
    """从分组中移除店铺"""
    try:
        remove_restaurant_from_group(user_id, group_id, restaurant_id)
        return {"status": "ok", "message": "已从分组中移除"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/groups/{group_id}/restaurants")
async def list_group_restaurants(group_id: str, user_id: str):
    """获取分组内的所有店铺"""
    try:
        data = get_group_restaurants(group_id, user_id)
        return {"restaurants": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# 博主统计接口（v5.0 新增）
# ─────────────────────────────────────────

@app.get("/api/authors/{author_id}/stats")
async def author_stats(author_id: str):
    """获取博主统计数据（餐厅数、粉丝数、城市数）"""
    try:
        stats = get_author_stats(author_id)
        return stats
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
            "avg_price": amap_result.get("avg_price"),      # 人均消费（元）
            "photo_url": amap_result.get("photo_url", ""),  # 店铺封面图
            # v2.5 新增字段
            "parse_reason": f"用户手动添加店铺「{req.restaurant_name}」",
            "data_source": "manual_add",
            "api_cost": 0.0,  # 手动添加不消耗 JustOneAPI（视频已解析过）
            "api_cost_note": "用户手动添加，无 API 调用成本",
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
                "avg_price": restaurant_data.get("avg_price"),    # 人均消费（元）
                "photo_url": restaurant_data.get("photo_url", ""), # 店铺封面图
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
# 后台人工复核 API（v3.0 新增）
# 所有接口需要管理员鉴权（X-User-ID Header）
# ─────────────────────────────────────────

# 复核相关请求模型
class AdminConfirmCorrectRequest(BaseModel):
    cache_id: str   # video_parse_cache 的 id

class AdminConfirmEmptyRequest(BaseModel):
    cache_id: str

class AdminCorrectRequest(BaseModel):
    cache_id: str
    amap_id: str
    restaurant_name: str
    address: str
    city: str
    latitude: float
    longitude: float
    category: str   # 管理员最终确认的分类

class AdminSkipRequest(BaseModel):
    cache_id: str


async def require_admin(x_user_id: str = Header(None, alias="X-User-ID")) -> str:
    """
    管理员鉴权依赖函数。
    从请求头 X-User-ID 读取用户 ID，校验是否在 admin_users 表中。
    """
    if not x_user_id:
        raise HTTPException(status_code=403, detail="需要管理员权限")
    if not is_admin_user(x_user_id):
        raise HTTPException(status_code=403, detail="无管理员权限")
    return x_user_id


@app.get("/api/admin/check")
async def admin_check(x_user_id: str = Header(None, alias="X-User-ID")):
    """
    检查当前用户是否为管理员。
    普通用户调用返回 {is_admin: false}，不报错。
    """
    if not x_user_id:
        return {"is_admin": False}
    is_admin = is_admin_user(x_user_id)
    return {"is_admin": is_admin, "user_id": x_user_id if is_admin else None}


@app.get("/api/admin/review/list")
async def review_list(
    page: int = 1,
    page_size: int = 20,
    tab: str = "pending",
    admin_user_id: str = Depends(require_admin),
):
    """
    获取复核列表。
    tab=pending（默认）：待复核，P0 优先。
    tab=reviewed：已复核，按 reviewed_at 倒序。
    """
    result = get_review_list(page=page, page_size=page_size, tab=tab)
    return result


@app.get("/api/admin/review/search-restaurant")
async def review_search_restaurant(
    name: str,
    city: str = "",
    admin_user_id: str = Depends(require_admin),
):
    """
    复核时搜索店铺候选列表（调用高德 POI 搜索）。
    返回最多 10 条候选，每条含 category_raw 和 category_mapped。
    """
    candidates = await search_restaurant_for_review(name, city)
    return {"candidates": candidates}


@app.post("/api/admin/review/confirm-correct")
async def review_confirm_correct(
    req: AdminConfirmCorrectRequest,
    admin_user_id: str = Depends(require_admin),
):
    """
    确认 AI 识别结果正确：
    - 更新 restaurants.verified = true
    - 同步 video_parse_cache 快照字段
    - 设置 review_status = 'approved'
    """
    success = admin_confirm_correct(req.cache_id, admin_user_id)
    if not success:
        raise HTTPException(status_code=404, detail="未找到该复核记录或记录无关联店铺")
    return {"status": "ok", "message": "已确认正确"}


@app.post("/api/admin/review/confirm-empty")
async def review_confirm_empty(
    req: AdminConfirmEmptyRequest,
    admin_user_id: str = Depends(require_admin),
):
    """确认该视频无店铺，更新 review_status = 'confirmed'"""
    admin_confirm_empty(req.cache_id, admin_user_id)
    return {"status": "ok", "message": "已确认无店铺"}


@app.post("/api/admin/review/correct")
async def review_correct(
    req: AdminCorrectRequest,
    admin_user_id: str = Depends(require_admin),
):
    """
    人工修正店铺：
    - upsert restaurants（以 amap_id 为唯一键，设 verified=true）
    - 更新 author_restaurants 关联
    - 更新 video_parse_cache 所有快照字段，review_status = 'corrected'
    """
    success = admin_correct_restaurant(
        cache_id=req.cache_id,
        admin_user_id=admin_user_id,
        amap_id=req.amap_id,
        name=req.restaurant_name,
        address=req.address,
        city=req.city,
        latitude=req.latitude,
        longitude=req.longitude,
        category=req.category,
    )
    if not success:
        raise HTTPException(status_code=404, detail="未找到该复核记录")
    return {"status": "ok", "message": "店铺已修正入库"}


@app.post("/api/admin/review/skip")
async def review_skip(
    req: AdminSkipRequest,
    admin_user_id: str = Depends(require_admin),
):
    """跳过该条复核记录，更新 review_status = 'skipped'"""
    admin_skip(req.cache_id, admin_user_id)
    return {"status": "ok", "message": "已跳过"}


@app.post("/api/admin/backfill-restaurant-data")
async def backfill_restaurant_data(admin_user_id: str = Depends(require_admin)):
    """
    管理员接口：回填数据库中 avg_price / photo_url 为 null 的店铺数据。
    通过高德 POI 详情接口（/v3/place/detail）按 amap_id 精准查询，
    将返回的均价和图片 URL 写回 restaurants 表。
    """
    # 查询所有 avg_price 为 null 且有 amap_id 的店铺
    resp = supabase.table("restaurants") \
        .select("id, name, amap_id, city") \
        .is_("avg_price", "null") \
        .not_.is_("amap_id", "null") \
        .execute()
    rows = resp.data or []

    updated = 0
    failed = []

    for row in rows:
        amap_id = row.get("amap_id")
        if not amap_id:
            continue
        detail = await get_poi_detail(amap_id)
        if detail is None:
            failed.append({"id": row["id"], "name": row["name"], "reason": "高德接口无返回"})
            continue
        # 只更新有实际值的字段，避免覆盖已有数据
        update_data = {}
        if detail.get("avg_price") is not None:
            update_data["avg_price"] = detail["avg_price"]
        if detail.get("photo_url"):
            update_data["photo_url"] = detail["photo_url"]
        if update_data:
            supabase.table("restaurants").update(update_data).eq("id", row["id"]).execute()
            updated += 1
        else:
            failed.append({"id": row["id"], "name": row["name"], "reason": "高德无均价/图片数据"})

    return {
        "status": "ok",
        "total": len(rows),
        "updated": updated,
        "failed": failed,
    }


# ─────────────────────────────────────────
# 用户 Profile 接口（昵称 + 头像）
# ─────────────────────────────────────────

class UpdateProfileRequest(BaseModel):
    user_id: str
    nickname: str  # 1-20 字符


@app.get("/api/profile/{user_id}")
async def get_profile(user_id: str):
    """
    获取用户 profile。
    若用户尚未设置过 profile，返回默认值（昵称"美食探索者"，avatar_url null）。
    """
    profile = get_user_profile(user_id)
    if not profile:
        return {"user_id": user_id, "nickname": "美食探索者", "avatar_url": None}
    return profile


@app.post("/api/profile/update")
async def update_profile(req: UpdateProfileRequest):
    """
    更新用户昵称。
    昵称长度限制 1-20 字符，超出则返回 400。
    """
    nickname = req.nickname.strip()
    if not nickname or len(nickname) > 20:
        raise HTTPException(status_code=400, detail="昵称长度需在 1-20 字符之间")
    profile = upsert_user_profile(req.user_id, nickname=nickname)
    return {"status": "ok", "profile": profile}


@app.post("/api/profile/upload-avatar")
async def upload_avatar(
    user_id: str = Form(...),
    file: UploadFile = File(...)
):
    """
    上传用户头像。
    接收 multipart/form-data，校验文件类型（jpg/png/webp）和大小（≤2MB）。
    上传到 Supabase Storage avatars bucket，路径为 {user_id}.jpg，覆盖旧文件。
    成功后将 avatar_url 写入 user_profiles 表。
    """
    # 校验文件类型
    if file.content_type not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(status_code=400, detail="仅支持 JPG/PNG/WebP 格式")

    content = await file.read()
    if len(content) > 2 * 1024 * 1024:  # 2MB
        raise HTTPException(status_code=400, detail="图片大小不能超过 2MB")

    # 上传到 Supabase Storage（固定路径，upsert 覆盖旧头像）
    from db import supabase as _supabase
    path = f"{user_id}.jpg"
    _supabase.storage.from_("avatars").upload(
        path, content,
        file_options={"content-type": "image/jpeg", "upsert": "true"}
    )

    # 构造公开 URL
    avatar_url = _supabase.storage.from_("avatars").get_public_url(path)

    # 写入 user_profiles
    profile = upsert_user_profile(user_id, avatar_url=avatar_url)
    return {"status": "ok", "avatar_url": avatar_url, "profile": profile}


# ─────────────────────────────────────────
# 本地开发启动入口
# ─────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    # 本地开发时运行：python main.py
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
