#!/usr/bin/env python3
"""
验证脚本：测试抖音解析相关接口是否正常工作
"""
import asyncio
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from douyin_parser import parse_douyin_link, fetch_author_videos, fetch_video_comments
from ai_extractor import extract_restaurants_from_video

# 示例抖音链接
TEST_URL = "https://v.douyin.com/4zIppExRIAg/"


async def main():
    print("=" * 60)
    print("第一步：解析示例抖音链接")
    print("=" * 60)
    try:
        video_info = await parse_douyin_link(TEST_URL)
        print(f"\n✅ 解析成功！")
        print(f"   视频ID: {video_info['video_id']}")
        print(f"   标题: {video_info['title']}")
        print(f"   博主ID: {video_info['author_id']}")
        print(f"   博主昵称: {video_info['author_name']}")
        print(f"   博主sec_uid: {video_info['author_sec_uid'][:30]}...")
    except Exception as e:
        print(f"\n❌ 解析失败: {e}")
        return

    # ─────────────────────────────────────────
    print("\n" + "=" * 60)
    print("第二步：获取博主视频列表")
    print("=" * 60)
    sec_uid = video_info.get("author_sec_uid", "")
    if not sec_uid:
        print("❌ 没有 sec_uid，无法获取博主视频列表")
    else:
        try:
            videos = await fetch_author_videos(sec_uid, max_count=5)
            print(f"\n✅ 获取到 {len(videos)} 条视频（前5条）:")
            for i, v in enumerate(videos[:5], 1):
                title = v.get("title", "")[:50]
                print(f"   [{i}] {v['video_id']} - {title}...")
        except Exception as e:
            print(f"❌ 获取博主视频列表失败: {e}")

    # ─────────────────────────────────────────
    print("\n" + "=" * 60)
    print("第三步：获取示例视频评论")
    print("=" * 60)
    try:
        comments = await fetch_video_comments(video_info["video_id"], max_count=10)
        print(f"\n✅ 获取到 {len(comments)} 条评论（按点赞数排序）:")
        for i, c in enumerate(comments[:10], 1):
            text = c.get("text", "")[:60]
            digg = c.get("digg_count", 0)
            print(f"   [{i}] {digg}赞: {text}...")
    except Exception as e:
        print(f"❌ 获取评论失败: {e}")

    # ─────────────────────────────────────────
    print("\n" + "=" * 60)
    print("第四步：AI 提取示例视频店铺（当前算法）")
    print("=" * 60)
    try:
        restaurants = await extract_restaurants_from_video(
            video_title=video_info["title"],
            comments=comments,
            author_name=video_info["author_name"],
        )
        print(f"\n✅ AI 提取结果: {len(restaurants)} 家店铺")
        for r in restaurants:
            print(f"   店名: {r.get('name')}")
            print(f"   城市: {r.get('city')}")
            print(f"   分类: {r.get('category')}")
            print(f"   置信度: {r.get('confidence')}")
    except Exception as e:
        print(f"❌ AI 提取失败: {e}")

    # ─────────────────────────────────────────
    print("\n" + "=" * 60)
    print("验证完成")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
