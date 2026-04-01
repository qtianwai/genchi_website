# 定时任务调度器
# 用于执行博主自动更新检测等后台任务
# 支持两种运行模式：
# 1. 独立运行：python scheduler.py（本地开发测试）
# 2. Web 模式：uvicorn scheduler:app（Railway 部署，定时触发）

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
# AUTO_UPDATE_SCHEDULE_HOUR: 每天定时检测的小时（0-23，默认 2，即凌晨 2 点）
AUTO_UPDATE_ENABLED = os.getenv("AUTO_UPDATE_ENABLED", "false").lower() == "true"
AUTO_UPDATE_SCHEDULE_HOUR = int(os.getenv("AUTO_UPDATE_SCHEDULE_HOUR", "2"))

# 最大处理博主数（防止一次处理太多，费用失控）
# 每次任务最多处理 MAX_AUTHORS_PER_RUN 个博主
MAX_AUTHORS_PER_RUN = int(os.getenv("AUTO_UPDATE_MAX_AUTHORS_PER_RUN", "50"))

# 单个博主最多解析的新视频数
MAX_NEW_VIDEOS_PER_AUTHOR = 5


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
    异步执行博主自动更新检测

    流程：
    1. 检查 AUTO_UPDATE_ENABLED 配置
    2. 获取所有 auto_update_enabled=true 的博主
    3. 对每个博主执行检测（最多 MAX_AUTHORS_PER_RUN 个）
    4. 更新博主的 no_new_food_video_days 和 auto_update_enabled
    """
    from db import (
        get_authors_with_auto_update_enabled,
        update_author_auto_check_time,
        increment_no_new_food_video_days,
        reset_no_new_food_video_days,
        disable_author_auto_update,
    )
    from douyin_parser import fetch_author_videos, extract_video_id_from_url
    from ai_extractor import filter_food_video_titles
    from db import get_video_cache_by_id

    # 检查是否启用
    if not AUTO_UPDATE_ENABLED:
        logger.info("[调度器] 博主自动更新检测未启用（AUTO_UPDATE_ENABLED=false）")
        return {"status": "skipped", "message": "功能未启用"}

    # 获取需要检测的博主
    authors = get_authors_with_auto_update_enabled(limit=MAX_AUTHORS_PER_RUN)
    if not authors:
        logger.info("[调度器] 没有需要检测的博主")
        return {"status": "success", "authors_checked": 0}

    logger.info(f"[调度器] 发现 {len(authors)} 个博主需要检测")

    total_new_videos = 0
    total_authors_with_new = 0

    for author in authors:
        author_id = author.get("id")
        author_name = author.get("name", "未知")
        sec_uid = author.get("sec_uid", "")

        if not sec_uid:
            logger.warning(f"[调度器] 博主 {author_name} 无 sec_uid，跳过")
            continue

        try:
            # 获取博主最新视频列表（不分页，单次调用获取一批）
            videos = await fetch_author_videos(sec_uid, max_count=20)

            if not videos:
                logger.info(f"[调度器] 博主 {author_name} 无视频记录")
                increment_no_new_food_video_days(author_id)
                _check_and_disable_author(author_id)
                update_author_auto_check_time(author_id)
                continue

            # 过滤掉数据库中已有解析记录的视频
            pending_videos = []
            for v in videos:
                vid = v.get("video_id", "")
                existing_cache = get_video_cache_by_id(vid)
                if not existing_cache or existing_cache.get("status") != "completed":
                    pending_videos.append(v)
                else:
                    logger.info(f"[调度器] 视频 {vid} 已解析过，跳过")

            if not pending_videos:
                logger.info(f"[调度器] 博主 {author_name} 无新视频")
                increment_no_new_food_video_days(author_id)
                _check_and_disable_author(author_id)
                update_author_auto_check_time(author_id)
                continue

            # AI 标题过滤（判断是否为美食/探店类）
            food_videos = await filter_food_video_titles(pending_videos)

            if not food_videos:
                logger.info(f"[调度器] 博主 {author_name} 无新美食视频")
                increment_no_new_food_video_days(author_id)
                _check_and_disable_author(author_id)
                update_author_auto_check_time(author_id)
                continue

            # 重置连续无新视频天数（发现有新美食视频）
            reset_no_new_food_video_days(author_id)

            # 限制解析数量（最多 MAX_NEW_VIDEOS_PER_AUTHOR 条）
            videos_to_parse = food_videos[:MAX_NEW_VIDEOS_PER_AUTHOR]
            logger.info(f"[调度器] 博主 {author_name} 有 {len(food_videos)} 条新美食视频，解析前 {len(videos_to_parse)} 条")

            # TODO: 触发视频解析（复用 parse_single_video_fast 逻辑）
            # 注意：这里需要调用 main.py 中的解析逻辑，但 scheduler 是独立脚本
            # 解决方案：后续可以将解析逻辑提取为独立函数

            total_new_videos += len(videos_to_parse)
            total_authors_with_new += 1

            # 更新检测时间
            update_author_auto_check_time(author_id)

        except Exception as e:
            logger.error(f"[调度器] 博主 {author_name} 检测出错: {e}")

    logger.info(f"[调度器] 检测完成: {len(authors)} 个博主，{total_authors_with_new} 个有新视频，共 {total_new_videos} 条待解析")

    return {
        "status": "success",
        "authors_checked": len(authors),
        "authors_with_new_videos": total_authors_with_new,
        "new_videos_count": total_new_videos,
    }


def _check_and_disable_author(author_id: str):
    """
    检查博主的连续无新视频天数，超过阈值则关闭自动更新
    """
    from db import get_author_by_id

    # 连续 7 天无新美食视频，自动关闭检测
    MAX_NO_NEW_DAYS = 7

    author = get_author_by_id(author_id)
    if author:
        no_new_days = author.get("no_new_food_video_days", 0)
        if no_new_days >= MAX_NO_NEW_DAYS:
            disable_author_auto_update(author_id)
            logger.info(f"[调度器] 博主 {author.get('name')} 连续 {no_new_days} 天无新美食视频，关闭自动更新检测")


# ─────────────────────────────────────────
# Web 模式入口（供 Railway 定时触发）
# ─────────────────────────────────────────

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="调度器", version="1.0.0")


class TriggerRequest(BaseModel):
    """触发自动更新的请求参数"""
    secret: str  # 触发密钥，用于验证请求来源


@app.get("/")
async def health_check():
    """健康检查"""
    return {
        "status": "ok",
        "service": "调度器",
        "auto_update_enabled": AUTO_UPDATE_ENABLED,
        "schedule_hour": AUTO_UPDATE_SCHEDULE_HOUR,
    }


@app.post("/api/trigger-auto-update")
async def trigger_auto_update(req: TriggerRequest):
    """
    触发博主自动更新检测

    配置说明：
    - AUTO_UPDATE_TRIGGER_SECRET: 触发密钥（必填，用于验证请求来源）
    - AUTO_UPDATE_ENABLED: 是否启用（默认 false）
    - AUTO_UPDATE_SCHEDULE_HOUR: 定时触发小时（默认 2，即凌晨 2 点）

    Railway 部署时，可配置：
    - 在 Railway 控制台添加 cron job，定时调用此接口
    - Cron 表达式示例：0 2 * * *（每天凌晨 2 点）
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

        videos = loop.run_until_complete(fetch_author_videos(sec_uid, max_count=20))
        return {
            "status": "success",
            "author_name": author.get("name"),
            "videos_count": len(videos),
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
