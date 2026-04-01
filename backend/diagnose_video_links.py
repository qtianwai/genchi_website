#!/usr/bin/env python3
"""
诊断脚本：检查 video_parse_cache 表中的视频链接格式
查看有多少条记录使用了 bg:// 占位符，以及它们的关联关系
"""

import os
import httpx
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

def query_supabase(table: str, select: str = "*", filters: dict = None):
    """使用 REST API 查询 Supabase"""
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

def main():
    print("=" * 60)
    print("诊断：video_parse_cache 表中的视频链接格式")
    print("=" * 60)

    # 1. 查询所有 bg:// 开头的记录
    print("\n[1] 查询 bg:// 占位符记录...")
    cache_records = query_supabase("video_parse_cache", "*")

    bg_records = [r for r in cache_records if r.get("video_url", "").startswith("bg://")]
    normal_records = [r for r in cache_records if not r.get("video_url", "").startswith("bg://")]

    print(f"   总记录数: {len(cache_records)}")
    print(f"   bg:// 占位符: {len(bg_records)} 条")
    print(f"   正常链接: {len(normal_records)} 条")

    # 2. 查看 bg:// 记录的详细信息
    if bg_records:
        print(f"\n[2] bg:// 记录详情（前 5 条）:")
        for i, record in enumerate(bg_records[:5], 1):
            print(f"\n   记录 {i}:")
            print(f"   - video_url: {record.get('video_url')}")
            print(f"   - video_id: {record.get('video_id')}")
            print(f"   - author_id: {record.get('author_id')}")
            print(f"   - status: {record.get('status')}")
            print(f"   - restaurant_name: {record.get('restaurant_name')}")
            print(f"   - restaurant_id: {record.get('restaurant_id')}")

    # 3. 查询 author_restaurants 表，看看 video_id 字段的情况
    print(f"\n[3] 查询 author_restaurants 表中的 video_id...")
    author_restaurants = query_supabase("author_restaurants", "video_id,author_id,restaurant_id")

    video_ids = [r.get("video_id") for r in author_restaurants if r.get("video_id")]
    print(f"   总关联记录数: {len(author_restaurants)}")
    print(f"   有 video_id 的记录: {len(video_ids)} 条")

    if video_ids:
        print(f"\n   示例 video_id（前 5 条）:")
        for vid in video_ids[:5]:
            print(f"   - {vid}")

    # 4. 检查是否有 video_id 对应多个不同的 video_url
    print(f"\n[4] 检查 video_id 与 video_url 的对应关系...")
    video_id_to_urls = {}
    for record in cache_records:
        vid = record.get("video_id")
        url = record.get("video_url")
        if vid:
            if vid not in video_id_to_urls:
                video_id_to_urls[vid] = []
            video_id_to_urls[vid].append(url)

    multi_url_videos = {vid: urls for vid, urls in video_id_to_urls.items() if len(urls) > 1}
    print(f"   同一 video_id 对应多个 URL 的情况: {len(multi_url_videos)} 个")

    if multi_url_videos:
        print(f"\n   示例（前 3 个）:")
        for vid, urls in list(multi_url_videos.items())[:3]:
            print(f"   - video_id: {vid}")
            for url in urls:
                print(f"     - {url}")

    print("\n" + "=" * 60)
    print("诊断完成")
    print("=" * 60)

if __name__ == "__main__":
    main()
