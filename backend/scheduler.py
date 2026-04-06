# 定时任务调度器
# 用于执行博主自动更新检测等后台任务
# 支持两种运行模式：
# 1. 独立运行：python scheduler.py（本地开发测试）
# 2. Web 模式：uvicorn scheduler:app（Railway 部署，定时触发）
#
# v13.0 重写：
# - 博主筛选条件增加美食视频占比、关联数量、更新频率排序
# - 检测流程与后台解析博主历史视频保持一致
# - 真正执行视频解析（之前只做检测，有 TODO 未实现）
# - 成本记录到 author_background_tasks 表

import os
import asyncio
import logging
from datetime import datetime
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 读取配置
# AUTO_UPDATE_ENABLED: 是否启用博主自动更新检测（true/false）
AUTO_UPDATE_ENABLED = os.getenv("AUTO_UPDATE_ENABLED", "false").lower() == "true"

# v13.0 博主筛选配置
AUTO_UPDATE_MIN_FOOD_RATIO = float(os.getenv("AUTO_UPDATE_MIN_FOOD_RATIO", "0.4"))  # 美食视频占比最低阈值
AUTO_UPDATE_MIN_FOOD_COUNT = int(os.getenv("AUTO_UPDATE_MIN_FOOD_COUNT", "5"))  # 平台关联美食视频最低数量
AUTO_UPDATE_MAX_AUTHORS = int(os.getenv("AUTO_UPDATE_MAX_AUTHORS", "50"))  # 每次最多处理的博主数量
AUTO_UPDATE_NO_NEW_DAYS_LIMIT = int(os.getenv("AUTO_UPDATE_NO_NEW_DAYS_LIMIT", "7"))  # 连续无新视频天数阈值

# v12.0 后台解析配置（与 main.py 共用）
FETCH_AUTHOR_VIDEOS_MAX = int(os.getenv("FETCH_AUTHOR_VIDEOS_MAX", "15"))
MAX_PARSE_VIDEOS = int(os.getenv("MAX_PARSE_VIDEOS", "15"))

# v11.0：解析算法版本号（与 main.py 保持一致）
PARSE_ALGORITHM_VERSION = os.getenv("PARSE_ALGORITHM_VERSION", "v13.0")


def run_auto_update_check():
    """
    触发博主自动更新检测（同步入口，供外部调用）
    在独立运行时直接执行，在 web 模式下供 /api/trigger-auto-update 调用
    """
    logger.info("[调度器] 开始执行博主自动更新检测...")

    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        result = loop.run_until_complete(_run_auto_update_async())
        logger.info(f"[调度器] 自动更新检测完成: {result}")
        return result
    except Exception as e:
        logger.error(f"[调度器] 自动更新检测出错: {e}")
        return {"status": "error", "message": str(e)}
    finally:
        loop.close()


async def _run_auto_update_async():
    """
    异步执行博主自动更新检测（v13.0 重写）

    流程：
    1. 检查 AUTO_UPDATE_ENABLED 配置
    2. 获取符合条件的博主（美食占比 + 关联数量 + 更新频率排序）
    3. 对每个博主执行完整的解析流程（与后台解析博主历史视频一致）
    4. 更新博主统计数据和自动更新状态
    """
    from db import (
        get_authors_for_auto_update,
        update_author_auto_check_time,
        increment_no_new_food_video_days,
        reset_no_new_food_video_days,
        disable_author_auto_update,
        get_author_by_id,
        get_video_cache_by_id,
        create_bg_task, update_bg_task_started, update_bg_task_progress,
        complete_bg_task, fail_bg_task, update_bg_task_cost,
        upsert_video_cache, update_video_cache_restaurant,
        update_video_cache_failed, update_video_cache_extra_by_video_id,
        upsert_restaurant, link_author_restaurant, get_restaurant_by_amap_id,
        update_author_food_stats, get_author_food_video_count,
    )
    from douyin_parser import fetch_author_videos, fetch_video_detail_extra
    from ai_extractor import filter_food_video_titles, extract_restaurants_priority
    from amap_service import batch_search_restaurants
    from rule_extractor import extract_candidates

    # 检查是否启用
    if not AUTO_UPDATE_ENABLED:
        logger.info("[调度器] 博主自动更新检测未启用（AUTO_UPDATE_ENABLED=false）")
        return {"status": "skipped", "message": "功能未启用"}

    # v13.0：使用新的筛选条件获取博主
    authors = get_authors_for_auto_update(
        min_food_ratio=AUTO_UPDATE_MIN_FOOD_RATIO,
        min_food_count=AUTO_UPDATE_MIN_FOOD_COUNT,
        limit=AUTO_UPDATE_MAX_AUTHORS,
    )
    if not authors:
        logger.info("[调度器] 没有符合条件的博主需要检测")
        return {"status": "success", "authors_checked": 0}

    logger.info(f"[调度器] 发现 {len(authors)} 个博主需要检测"
                f"（筛选条件: 美食占比>={AUTO_UPDATE_MIN_FOOD_RATIO}, "
                f"美食视频数>={AUTO_UPDATE_MIN_FOOD_COUNT}）")

    total_new_videos = 0
    total_authors_with_new = 0
    total_new_restaurants = 0

    for author in authors:
        author_id = author.get("id")
        author_name = author.get("name", "未知")
        sec_uid = author.get("sec_uid", "")

        if not sec_uid:
            logger.warning(f"[调度器] 博主 {author_name} 无 sec_uid，跳过")
            continue

        # 为每个博主创建 auto_check 类型的后台任务（用于成本记录）
        task = create_bg_task(author_id, "auto_check")
        task_id = task.get("id", "")
        update_bg_task_started(task_id)
        task_api_cost = 0.0
        task_cost_parts = []

        try:
            # ─── 第一步：获取博主视频列表 ───
            videos, fetch_api_calls = await fetch_author_videos(sec_uid, max_count=FETCH_AUTHOR_VIDEOS_MAX)
            fetch_cost = fetch_api_calls * 0.1
            task_api_cost += fetch_cost
            task_cost_parts.append(f"get-user-video-list/v3 × {fetch_api_calls} 次分页，¥{fetch_cost:.2f}")

            if not videos:
                logger.info(f"[调度器] 博主 {author_name} 无视频记录")
                increment_no_new_food_video_days(author_id)
                _check_and_disable_author(author_id)
                update_author_auto_check_time(author_id)
                complete_bg_task(task_id, 0)
                update_bg_task_cost(task_id, task_api_cost, "\n".join(task_cost_parts))
                continue

            # ─── 第二步：过滤已解析视频（v12.0：只要有记录就跳过） ───
            pending_videos = []
            for v in videos:
                vid = v.get("video_id", "")
                existing_cache = get_video_cache_by_id(vid)
                if existing_cache:
                    logger.debug(f"[调度器] 视频 {vid} 已有记录（status={existing_cache.get('status')}），跳过")
                else:
                    pending_videos.append(v)

            if not pending_videos:
                logger.info(f"[调度器] 博主 {author_name} 无新视频")
                increment_no_new_food_video_days(author_id)
                _check_and_disable_author(author_id)
                update_author_auto_check_time(author_id)
                complete_bg_task(task_id, 0)
                update_bg_task_cost(task_id, task_api_cost, "\n".join(task_cost_parts))
                continue

            # ─── 第三步：AI 标题过滤 ───
            food_videos = await filter_food_video_titles(pending_videos)

            if not food_videos:
                logger.info(f"[调度器] 博主 {author_name} 无新美食视频")
                increment_no_new_food_video_days(author_id)
                _check_and_disable_author(author_id)
                update_author_auto_check_time(author_id)
                complete_bg_task(task_id, 0)
                update_bg_task_cost(task_id, task_api_cost, "\n".join(task_cost_parts))
                continue

            # v12.0：AI 过滤后截断到 MAX_PARSE_VIDEOS 条
            if len(food_videos) > MAX_PARSE_VIDEOS:
                logger.info(f"[调度器] 美食视频数量超限，截断: {len(food_videos)} -> {MAX_PARSE_VIDEOS}")
                food_videos = food_videos[:MAX_PARSE_VIDEOS]

            # 重置连续无新视频天数（发现有新美食视频）
            reset_no_new_food_video_days(author_id)

            logger.info(f"[调度器] 博主 {author_name} 有 {len(food_videos)} 条新美食视频待解析")

            # ─── 第四步：逐个解析待处理视频 ───
            saved_count = 0
            for i, video in enumerate(food_videos):
                vid = video.get("video_id", "")
                title = video.get("title", "")
                share_url = video.get("share_url", "")
                video_url = share_url if share_url else f"https://www.iesdouyin.com/share/video/{vid}/"

                # 创建缓存记录
                upsert_video_cache({
                    "video_url": video_url,
                    "video_id": vid,
                    "author_id": author_id,
                    "status": "parsing",
                    "parse_algorithm_version": PARSE_ALGORITHM_VERSION,
                })

                try:
                    # 获取视频扩展信息（detail + comments = ¥0.2）
                    extra = await fetch_video_detail_extra(vid, author_id)
                    video_cost = 0.2
                    task_api_cost += video_cost

                    # 写入视频扩展信息
                    bg_video_extra = {
                        "title": title,
                        "city_name": extra.get("city_name", ""),
                        "publish_time": extra.get("video_publish_time", ""),
                        "publish_timestamp": extra.get("video_publish_timestamp", 0),
                        "digg_count": extra.get("video_digg_count", 0),
                        "comment_count": extra.get("video_comment_count", 0),
                        "cover_url": extra.get("video_cover_url", ""),
                        "hashtags": extra.get("hashtags", []),
                        "video_tags": extra.get("video_tags", []),
                        "cha_list": extra.get("cha_list", []),
                        "hot_search_keywords": extra.get("hot_search_keywords", []),
                        "aweme_type_tags": extra.get("aweme_type_tags", ""),
                        "share_url": video_url,
                    }
                    update_video_cache_extra_by_video_id(vid, bg_video_extra)

                    # 规则预提取
                    rule_candidates = extract_candidates(
                        title=title,
                        hashtags=extra.get("hashtags", []),
                        author_name="",
                        author_liked_comments=extra.get("author_liked_comments", []),
                        all_comments=extra.get("all_comments", []),
                        poi_info=extra.get("poi_info"),
                    )

                    # AI 提取店铺
                    extracted = await extract_restaurants_priority(
                        video_title=title,
                        author_name="",
                        hashtags=extra.get("hashtags", []),
                        city_name=extra.get("city_name", "未知"),
                        author_liked_comments=extra.get("author_liked_comments", []),
                        hot_comments=extra.get("hot_comments", []),
                        all_comments=extra.get("all_comments", []),
                        rule_candidates=rule_candidates,
                    )

                    # 收集 parse_reason
                    parse_reason = ""
                    ai_confidence = None
                    if extracted:
                        if extracted[0].get("_no_result"):
                            parse_reason = extracted[0].get("reason", "AI未识别到店铺")
                        else:
                            parse_reason = extracted[0].get("reason", "")
                            ai_confidence = extracted[0].get("confidence", "low")

                    api_cost_note = f"get-video-detail/v2 + get-video-comment/v1；合计 2 次调用，约 ¥{video_cost:.4f}"

                    # 过滤掉 _no_result 标记
                    real_extracted = [r for r in extracted if not r.get("_no_result")] if extracted else []

                    if real_extracted:
                        if ai_confidence == "low":
                            # 低置信度：缓存但不入库
                            upsert_video_cache({
                                "video_url": video_url,
                                "video_id": vid,
                                "author_id": author_id,
                                "status": "failed",
                                "restaurant_name": real_extracted[0].get("name", ""),
                                "restaurant_city": real_extracted[0].get("city", ""),
                                "error_message": "低置信度结果，待人工复核",
                                "parse_reason": parse_reason,
                                "data_source": "auto_check",
                                "api_cost": video_cost,
                                "api_cost_note": api_cost_note,
                                "parse_algorithm_version": PARSE_ALGORITHM_VERSION,
                            })
                        else:
                            # 高德搜索
                            search_results = await batch_search_restaurants([real_extracted[0]])
                            # AI 结果搜不到时，用规则候选兜底
                            if not search_results and rule_candidates:
                                ai_name = real_extracted[0].get("name", "")
                                for cand in rule_candidates:
                                    cand_name = cand.get("name", "")
                                    if cand_name and cand_name != ai_name:
                                        fallback = await batch_search_restaurants([{
                                            "name": cand_name,
                                            "city": extra.get("city_name", "未知"),
                                            "category": real_extracted[0].get("category", ""),
                                        }])
                                        if fallback:
                                            search_results = fallback
                                            parse_reason = f"AI识别「{ai_name}」高德未命中，规则候选「{cand_name}」命中"
                                            break

                            if search_results:
                                amap_result = search_results[0]
                                # 入库店铺
                                restaurant_data = {
                                    "name": real_extracted[0].get("name", ""),
                                    "address": amap_result.get("address", ""),
                                    "city": real_extracted[0].get("city", ""),
                                    "latitude": amap_result.get("latitude"),
                                    "longitude": amap_result.get("longitude"),
                                    "amap_id": amap_result.get("amap_id"),
                                    "category": real_extracted[0].get("category", ""),
                                    "avg_price": amap_result.get("avg_price"),
                                    "photo_url": amap_result.get("photo_url", ""),
                                    "tel": amap_result.get("tel", ""),
                                }
                                saved_restaurant = upsert_restaurant(restaurant_data)
                                restaurant_id = saved_restaurant.get("id")
                                if restaurant_id:
                                    link_author_restaurant(author_id, restaurant_id, vid)

                                # 更新缓存
                                real_extracted[0].update({
                                    "address": amap_result.get("address", ""),
                                    "latitude": amap_result.get("latitude"),
                                    "longitude": amap_result.get("longitude"),
                                    "amap_id": amap_result.get("amap_id"),
                                    "avg_price": amap_result.get("avg_price"),
                                    "photo_url": amap_result.get("photo_url", ""),
                                    "parse_reason": parse_reason,
                                    "data_source": "auto_check",
                                    "api_cost": video_cost,
                                    "api_cost_note": api_cost_note,
                                    "parse_algorithm_version": PARSE_ALGORITHM_VERSION,
                                })
                                # 使用 _save_video_restaurant 的逻辑
                                upsert_video_cache({
                                    "video_url": video_url,
                                    "video_id": vid,
                                    "author_id": author_id,
                                    "status": "completed",
                                    "restaurant_id": restaurant_id,
                                    "restaurant_name": real_extracted[0].get("name", ""),
                                    "restaurant_address": amap_result.get("address", ""),
                                    "restaurant_city": real_extracted[0].get("city", ""),
                                    "restaurant_lat": amap_result.get("latitude"),
                                    "restaurant_lng": amap_result.get("longitude"),
                                    "restaurant_amap_id": amap_result.get("amap_id"),
                                    "restaurant_category": real_extracted[0].get("category", ""),
                                    "parse_reason": parse_reason,
                                    "data_source": "auto_check",
                                    "api_cost": video_cost,
                                    "api_cost_note": api_cost_note,
                                    "parse_algorithm_version": PARSE_ALGORITHM_VERSION,
                                })
                                saved_count += 1
                            else:
                                # 高德搜不到
                                upsert_video_cache({
                                    "video_url": video_url,
                                    "video_id": vid,
                                    "author_id": author_id,
                                    "status": "failed",
                                    "restaurant_name": real_extracted[0].get("name", ""),
                                    "error_message": "高德地图未找到该店铺",
                                    "parse_reason": parse_reason or f"AI识别到店铺「{real_extracted[0].get('name')}」但高德地图未找到",
                                    "data_source": "auto_check",
                                    "api_cost": video_cost,
                                    "api_cost_note": api_cost_note,
                                    "parse_algorithm_version": PARSE_ALGORITHM_VERSION,
                                })
                    else:
                        # 未提取到店铺
                        upsert_video_cache({
                            "video_url": video_url,
                            "video_id": vid,
                            "author_id": author_id,
                            "status": "failed",
                            "parse_reason": parse_reason or "AI未识别到店铺",
                            "data_source": "auto_check",
                            "api_cost": video_cost,
                            "api_cost_note": api_cost_note,
                            "parse_algorithm_version": PARSE_ALGORITHM_VERSION,
                        })

                except Exception as e:
                    logger.error(f"[调度器] 视频 {vid} 解析失败: {e}")
                    update_video_cache_failed(video_url, str(e))

                update_bg_task_progress(task_id, i + 1, saved_count)

            # 任务完成
            complete_bg_task(task_id, saved_count)
            task_cost_parts.append(f"解析 {len(food_videos)} 个视频: ¥{len(food_videos) * 0.2:.2f}")
            update_bg_task_cost(task_id, task_api_cost, "\n".join(task_cost_parts))

            total_new_videos += len(food_videos)
            total_authors_with_new += 1
            total_new_restaurants += saved_count

            # 更新博主统计数据
            try:
                food_ratio = len(food_videos) / len(pending_videos) if pending_videos else 0
                food_count = get_author_food_video_count(author_id)
                last_food_ts = None
                if videos:
                    first_ts = videos[0].get("create_time", 0)
                    if first_ts:
                        from datetime import timezone
                        last_food_ts = datetime.fromtimestamp(first_ts, tz=timezone.utc).isoformat()
                update_author_food_stats(author_id, food_ratio, food_count, last_food_ts)
            except Exception as e:
                logger.error(f"[调度器] 更新博主 {author_name} 统计数据出错: {e}")

            # 更新检测时间
            update_author_auto_check_time(author_id)

            logger.info(f"[调度器] 博主 {author_name} 检测完成: {len(food_videos)} 条新美食视频，新增 {saved_count} 家店铺，成本 ¥{task_api_cost:.2f}")

        except Exception as e:
            logger.error(f"[调度器] 博主 {author_name} 检测出错: {e}")
            fail_bg_task(task_id, str(e))
            update_bg_task_cost(task_id, task_api_cost, "\n".join(task_cost_parts))

    logger.info(f"[调度器] 检测完成: {len(authors)} 个博主，{total_authors_with_new} 个有新视频，"
                f"共 {total_new_videos} 条待解析，新增 {total_new_restaurants} 家店铺")

    return {
        "status": "success",
        "authors_checked": len(authors),
        "authors_with_new_videos": total_authors_with_new,
        "new_videos_count": total_new_videos,
        "new_restaurants_count": total_new_restaurants,
    }


def _check_and_disable_author(author_id: str):
    """
    检查博主的连续无新视频天数，超过阈值则关闭自动更新
    """
    from db import get_author_by_id, disable_author_auto_update

    author = get_author_by_id(author_id)
    if author:
        no_new_days = author.get("no_new_food_video_days", 0)
        if no_new_days >= AUTO_UPDATE_NO_NEW_DAYS_LIMIT:
            disable_author_auto_update(author_id)
            logger.info(f"[调度器] 博主 {author.get('name')} 连续 {no_new_days} 天无新美食视频，关闭自动更新检测")


# ─────────────────────────────────────────
# Web 模式入口（供 Railway 定时触发）
# ─────────────────────────────────────────

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="调度器", version="2.0.0")


class TriggerRequest(BaseModel):
    """触发自动更新的请求参数"""
    secret: str  # 触发密钥，用于验证请求来源


@app.get("/")
async def health_check():
    """健康检查"""
    return {
        "status": "ok",
        "service": "调度器",
        "version": "v13.0",
        "auto_update_enabled": AUTO_UPDATE_ENABLED,
        "config": {
            "min_food_ratio": AUTO_UPDATE_MIN_FOOD_RATIO,
            "min_food_count": AUTO_UPDATE_MIN_FOOD_COUNT,
            "max_authors": AUTO_UPDATE_MAX_AUTHORS,
            "no_new_days_limit": AUTO_UPDATE_NO_NEW_DAYS_LIMIT,
        },
    }


@app.post("/api/trigger-auto-update")
async def trigger_auto_update(req: TriggerRequest):
    """
    触发博主自动更新检测

    v13.0 配置说明：
    - AUTO_UPDATE_ENABLED: 是否启用（默认 false）
    - AUTO_UPDATE_MIN_FOOD_RATIO: 美食视频占比最低阈值（默认 0.4）
    - AUTO_UPDATE_MIN_FOOD_COUNT: 平台关联美食视频最低数量（默认 5）
    - AUTO_UPDATE_MAX_AUTHORS: 每次最多处理的博主数量（默认 50）
    - AUTO_UPDATE_NO_NEW_DAYS_LIMIT: 连续无新视频天数阈值（默认 7）
    """
    # 验证触发密钥
    trigger_secret = os.getenv("AUTO_UPDATE_TRIGGER_SECRET", "")
    if trigger_secret and req.secret != trigger_secret:
        raise HTTPException(status_code=403, detail="触发密钥错误")

    # 检查是否启用
    if not AUTO_UPDATE_ENABLED:
        raise HTTPException(status_code=400, detail="博主自动更新检测未启用")

    # 执行检测
    result = run_auto_update_check()
    return result


@app.post("/api/trigger-single-author/{author_id}")
async def trigger_single_author(author_id: str, req: TriggerRequest):
    """
    触发单个博主的自动更新检测（用于测试）
    """
    # 验证触发密钥
    trigger_secret = os.getenv("AUTO_UPDATE_TRIGGER_SECRET", "")
    if trigger_secret and req.secret != trigger_secret:
        raise HTTPException(status_code=403, detail="触发密钥错误")

    from db import get_author_by_id

    author = get_author_by_id(author_id)
    if not author:
        raise HTTPException(status_code=404, detail="博主不存在")

    # 执行检测
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        sec_uid = author.get("sec_uid", "")
        if not sec_uid:
            return {"status": "skipped", "message": "博主无 sec_uid"}

        from douyin_parser import fetch_author_videos
        videos, api_calls = loop.run_until_complete(fetch_author_videos(sec_uid, max_count=20))
        return {
            "status": "success",
            "author_name": author.get("name"),
            "videos_count": len(videos),
            "food_video_ratio": author.get("food_video_ratio", 0),
            "food_video_count": author.get("food_video_count", 0),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        loop.close()


# ─────────────────────────────────────────
# 独立运行入口（本地开发测试）
# ─────────────────────────────────────────

if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "--now":
        # 立即执行
        print("立即执行博主自动更新检测...")
        result = run_auto_update_check()
        print(f"执行结果: {result}")
    else:
        # Web 模式运行
        import uvicorn
        port = int(os.getenv("SCHEDULER_PORT", "8001"))
        print(f"启动调度器 Web 服务，端口 {port}...")
        print(f"触发接口: POST /api/trigger-auto-update")
        print(f"触发密钥: {os.getenv('AUTO_UPDATE_TRIGGER_SECRET', '(未设置)')}")
        uvicorn.run(app, host="0.0.0.0", port=port)
