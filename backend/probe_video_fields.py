#!/usr/bin/env python3
"""
探测 JustOneAPI 视频列表接口返回的数据结构
看看是否包含视频分享链接字段
"""

import os
import asyncio
import httpx
from dotenv import load_dotenv

load_dotenv()

JUSTONEAPI_BASE = "https://api.justoneapi.com"
JUSTONEAPI_TOKEN = os.getenv("JUSTONEAPI_TOKEN", "2UJdMdkQiP4xaOIS")
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")


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


async def probe_video_list_fields():
    # 先从数据库拿一个 sec_uid
    authors = query_supabase("authors", "id,name,sec_uid")
    author = next((a for a in authors if a.get("sec_uid")), None)
    if not author:
        print("没有找到有 sec_uid 的博主")
        return

    print(f"使用博主: {author['name']} (sec_uid={author['sec_uid'][:20]}...)")

    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f"{JUSTONEAPI_BASE}/api/douyin/get-user-video-list/v3",
            params={
                "token": JUSTONEAPI_TOKEN,
                "secUid": author["sec_uid"],
                "maxCursor": 0,
            }
        )
        result = resp.json()

    if result.get("code") != 0:
        print(f"接口失败: {result}")
        return

    aweme_list = result.get("data", {}).get("aweme_list", [])
    if not aweme_list:
        print("没有视频数据")
        return

    # 打印第一个视频的所有顶层字段
    v = aweme_list[0]
    print(f"\n视频顶层字段（共 {len(v)} 个）:")
    for key in sorted(v.keys()):
        val = v[key]
        if isinstance(val, (str, int, float, bool)) or val is None:
            print(f"  {key}: {val}")
        elif isinstance(val, list):
            print(f"  {key}: [list, len={len(val)}]")
        elif isinstance(val, dict):
            print(f"  {key}: {{dict, keys={list(val.keys())[:5]}}}")

    # 重点检查可能包含分享链接的字段
    print("\n重点字段检查:")
    for key in ["share_url", "share_info", "video_url", "aweme_id", "desc"]:
        if key in v:
            print(f"  {key}: {v[key]}")

    # 检查 share_info 子字段
    if "share_info" in v:
        print(f"\nshare_info 详情:")
        for k, val in v["share_info"].items():
            print(f"  {k}: {val}")


asyncio.run(probe_video_list_fields())
