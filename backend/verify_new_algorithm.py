#!/usr/bin/env python3
"""
验证优化后的解析算法（基于优先级）
"""
import asyncio
import sys
import os
import json

sys.path.insert(0, os.path.dirname(__file__))

from douyin_parser import fetch_video_detail_extra, fetch_video_comments
from ai_extractor import extract_restaurants_priority, extract_restaurants_from_video

# 示例视频数据（通过 parse_douyin_link 已知）
VIDEO_ID = "7621134274259171761"
AUTHOR_ID = "84161710260"
VIDEO_TITLE = "上海超级巨无敌好吃的不改良重庆火锅，而且巨巨巨便宜#味道好极了你们想吃吗 #上海火锅去哪吃 #上海火锅店 #上海重庆火锅天花板"
AUTHOR_NAME = "不吃西瓜不要关注"


async def main():
    print("=" * 60)
    print("第一步：fetch_video_detail_extra（新函数 - P1 扩展信息）")
    print("=" * 60)
    extra = await fetch_video_detail_extra(VIDEO_ID, AUTHOR_ID)
    print(f"✅ 话题标签: {extra['hashtags']}")
    print(f"✅ 城市: {extra['city_name']}")
    print(f"✅ 博主点赞评论({len(extra['author_liked_comments'])}条):")
    for c in extra["author_liked_comments"]:
        print(f"   [{c['digg_count']}赞] {c['text']}")
    print(f"✅ 热门评论({len(extra['hot_comments'])}条):")
    for c in extra["hot_comments"][:5]:
        print(f"   [{c['digg_count']}赞] {c['text'][:50]}")

    print("\n" + "=" * 60)
    print("第二步：fetch_video_comments")
    print("=" * 60)
    comments = await fetch_video_comments(VIDEO_ID, max_count=20)
    print(f"✅ 获取 {len(comments)} 条评论")

    print("\n" + "=" * 60)
    print("第三步：新旧算法对比")
    print("=" * 60)

    print("\n[旧算法 - 仅标题+普通评论排序]")
    old_result = await extract_restaurants_from_video(
        video_title=VIDEO_TITLE,
        comments=comments,
        author_name=AUTHOR_NAME,
    )
    print(f"结果: {json.dumps(old_result, ensure_ascii=False, indent=2)}")

    print("\n[新算法 - 优先级策略]")
    new_result = await extract_restaurants_priority(
        video_title=VIDEO_TITLE,
        author_name=AUTHOR_NAME,
        hashtags=extra["hashtags"],
        city_name=extra["city_name"],
        author_liked_comments=extra["author_liked_comments"],
        hot_comments=extra["hot_comments"],
        all_comments=comments,
    )
    print(f"结果: {json.dumps(new_result, ensure_ascii=False, indent=2)}")

    print("\n" + "=" * 60)
    print("✅ 验证完成")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
