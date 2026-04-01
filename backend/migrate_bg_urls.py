#!/usr/bin/env python3
"""
迁移脚本：将数据库中 bg:// 占位符替换为真实的抖音视频链接
通过 JustOneAPI 获取视频的 share_url，更新 video_parse_cache 表
"""

import os
import asyncio
import httpx
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
JUSTONEAPI_BASE = "https://api.justoneapi.com"
JUSTONEAPI_TOKEN = os.getenv("JUSTONEAPI_TOKEN", "2UJdMdkQiP4xaOIS")


def query_supabase(table: str, select: str = "*", filters: dict = None):
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
    }
    params = {"select": select}
    if filters:
        params.update(filters)
    resp = httpx.get(url, headers=headers, params=params)
    resp.raise_for_status()
    return resp.json()


def update_supabase(table: str, data: dict, match: dict):
    """更新 Supabase 表中的记录"""
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    params = {k: f"eq.{v}" for k, v in match.items()}
    resp = httpx.patch(url, headers=headers, params=params, json=data)
    resp.raise_for_status()
    return resp.json()


async def get_video_share_url(video_id: str) -> str | None:
    """通过 JustOneAPI 获取视频的真实分享链接"""
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f"{JUSTONEAPI_BASE}/api/douyin/get-video-detail/v2",
            params={"token": JUSTONEAPI_TOKEN, "videoId": video_id}
        )
        result = resp.json()

    if result.get("code") != 0:
        return None

    aweme = result.get("data", {}).get("aweme_detail", {})
    # 优先从 share_url 字段获取
    share_url = aweme.get("share_url", "")
    if not share_url:
        share_url = aweme.get("share_info", {}).get("share_url", "")
    # 如果还没有，构造基础链接
    if not share_url:
        share_url = f"https://www.iesdouyin.com/share/video/{video_id}/"

    return share_url


async def migrate():
    print("=" * 60)
    print("迁移：将 bg:// 占位符替换为真实抖音视频链接")
    print("=" * 60)

    # 查询所有 bg:// 记录
    all_records = query_supabase("video_parse_cache", "id,video_url,video_id,status")
    bg_records = [r for r in all_records if r.get("video_url", "").startswith("bg://")]

    print(f"\n找到 {len(bg_records)} 条 bg:// 记录需要迁移")

    success = 0
    failed = 0

    for i, record in enumerate(bg_records, 1):
        video_id = record.get("video_id", "")
        old_url = record.get("video_url", "")
        status = record.get("status", "")

        print(f"\n[{i}/{len(bg_records)}] 处理 video_id={video_id} (status={status})")

        if not video_id:
            print(f"  跳过：无 video_id")
            failed += 1
            continue

        try:
            # 获取真实分享链接
            share_url = await get_video_share_url(video_id)
            if not share_url:
                print(f"  失败：无法获取 share_url")
                failed += 1
                continue

            # 更新数据库（用真实 URL 替换 bg:// 占位符）
            # 注意：video_url 有唯一索引，需要先删除旧记录再插入，或直接 update
            update_supabase(
                "video_parse_cache",
                {"video_url": share_url},
                {"video_url": old_url}
            )
            print(f"  成功：{old_url} → {share_url[:60]}...")
            success += 1

        except Exception as e:
            print(f"  错误：{e}")
            failed += 1

        # 避免 API 限流，每次请求间隔 0.5 秒
        await asyncio.sleep(0.5)

    print(f"\n{'=' * 60}")
    print(f"迁移完成：成功 {success} 条，失败 {failed} 条")
    print("=" * 60)


asyncio.run(migrate())
