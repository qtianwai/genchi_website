#!/usr/bin/env python3
"""
完整验证：按优先级测试用户描述的解析流程
"""
import asyncio
import httpx
import re
import os
import json
import sys

sys.path.insert(0, os.path.dirname(__file__))

from douyin_parser import parse_douyin_link, fetch_author_videos, fetch_video_comments
from ai_extractor import extract_restaurants_from_video

TOKEN = os.getenv("JUSTONEAPI_TOKEN", "2UJdMdkQiP4xaOIS")
BASE = "https://api.justoneapi.com"

def get(path, params=None):
    params = params or {}
    params["token"] = TOKEN
    params = {k: v for k, v in params.items() if v is not None}
    with httpx.Client(timeout=30, follow_redirects=True) as client:
        resp = client.get(f"{BASE}{path}", params=params)
        return resp.json()

TEST_URL = "https://v.douyin.com/4zIppExRIAg/"
VIDEO_ID = "7621134274259171761"

async def main():
    print("=" * 60)
    print("1. parse_douyin_link（解析链接）")
    print("=" * 60)
    try:
        info = await parse_douyin_link(TEST_URL)
        print(f"✅ video_id: {info['video_id']}")
        print(f"✅ author: {info['author_name']}")
        print(f"✅ sec_uid: {info['author_sec_uid'][:30]}...")
    except Exception as e:
        print(f"❌ 失败: {e}")
        return

    print("\n" + "=" * 60)
    print("2. fetch_author_videos（获取博主视频列表）")
    print("=" * 60)
    videos = await fetch_author_videos(info["author_sec_uid"], max_count=20)
    print(f"✅ 获取到 {len(videos)} 条视频")

    # 筛选探店相关视频（包含关键词）
    food_keywords = ["好吃", "火锅", "烧烤", "烤肉", "美食", "餐厅", "探店", "推荐", "必吃", "必吃榜",
                     "店", "餐厅", "馆子", "吃", "味道", "巨", "无敌"]
    food_videos = [v for v in videos if any(kw in v.get("title", "") for kw in food_keywords)]
    print(f"✅ 识别出 {len(food_videos)} 条探店相关视频（前3条）：")
    for v in food_videos[:3]:
        print(f"   - {v['video_id']}: {v.get('title', '')[:60]}")

    print("\n" + "=" * 60)
    print("3. fetch_video_comments（获取示例视频评论）")
    print("=" * 60)
    comments = await fetch_video_comments(VIDEO_ID, max_count=20)
    print(f"✅ 获取到 {len(comments)} 条评论")
    for c in comments:
        print(f"   [{c['digg_count']}赞] {c['text'][:60]}")

    print("\n" + "=" * 60)
    print("4. 深入查看评论接口是否有博主点赞/回复等额外字段")
    print("=" * 60)
    raw = get("/api/douyin/get-video-comment/v1", {"awemeId": VIDEO_ID, "page": 1})
    if raw.get("code") == 0:
        raw_comments = (raw.get("data") or {}).get("comments", []) or []
        print(f"原始评论结构 keys: {list(raw_comments[0].keys()) if raw_comments else '空'}")
        if raw_comments:
            print(f"第一条完整评论: {json.dumps(raw_comments[0], ensure_ascii=False, indent=2)[:500]}")

    print("\n" + "=" * 60)
    print("5. 测试分页获取更多评论")
    print("=" * 60)
    for page in [1, 2, 3]:
        raw_p = get("/api/douyin/get-video-comment/v1", {"awemeId": VIDEO_ID, "page": page})
        if raw_p.get("code") == 0:
            cmts = (raw_p.get("data") or {}).get("comments", []) or []
            print(f"  第{page}页: {len(cmts)} 条评论")
        else:
            print(f"  第{page}页: code={raw_p.get('code')} {raw_p.get('message')}")
            break

    print("\n" + "=" * 60)
    print("6. AI 提取测试（当前算法）")
    print("=" * 60)
    result = await extract_restaurants_from_video(
        video_title=info["title"],
        comments=comments,
        author_name=info["author_name"],
    )
    print(f"当前算法结果: {json.dumps(result, ensure_ascii=False, indent=2)}")

    print("\n" + "=" * 60)
    print("7. AI 提取测试（优化算法 - 模拟）")
    print("=" * 60)
    # 模拟新的优先级算法
    # P1: 标题+话题标签+城市
    title = info["title"]
    # 从 text_extra 获取话题
    data_v = get("/api/douyin/get-video-detail/v2", {"videoId": VIDEO_ID})
    aweme = data_v.get("data", {}).get("aweme_detail", {})
    text_extras = aweme.get("text_extra", []) or []
    hashtags = [t.get("hashtag_name", "") for t in text_extras if t.get("type") == 1 and t.get("hashtag_name")]
    city_code = aweme.get("city", "")  # 310000 = 上海

    print(f"  P1 标题: {title}")
    print(f"  P1 话题标签: {hashtags}")
    print(f"  P1 城市编码: {city_code} (310000=上海)")
    print(f"  P1 视频发布地点: {aweme.get('position', {}).get('city', '未知')}")

    # P2: 排序后的评论（按点赞数）
    top_comments = sorted(comments, key=lambda x: x["digg_count"], reverse=True)[:5]
    print(f"  P2 高赞评论: {[(c['digg_count'], c['text'][:30]) for c in top_comments]}")

    # 用优化后的信息重新调用 AI
    prompt_context = f"""
=== P1 信息（最高优先级）===
视频标题: {title}
话题标签: {', '.join(hashtags)}
城市: 上海（编码310000）

=== P2 信息（次优先级）===
按点赞数排序的评论:
{chr(10).join(f"[{c['digg_count']}赞] {c['text']}" for c in top_comments)}

请综合以上信息，判断这条视频探访的是哪一家具体店铺。
要求：
1. 优先根据标题和话题标签判断（通常标题里就含店名）
2. 高赞评论中如果有人直接说出店名，优先采信
3. 只输出一个最可能的店铺
返回 JSON: name, city, category, confidence
"""

    from openai import AsyncOpenAI
    client = AsyncOpenAI(
        api_key=os.getenv("DASHSCOPE_API_KEY"),
        base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
    )
    resp = await client.chat.completions.create(
        model="qwen-plus",
        messages=[
            {"role": "system", "content": "你是专业的美食信息提取助手，擅长从中文文本中识别餐厅店铺信息。"},
            {"role": "user", "content": prompt_context},
        ],
        temperature=0.1,
        max_tokens=300,
    )
    ai_result = resp.choices[0].message.content.strip()
    print(f"\n  优化算法 AI 结果: {ai_result}")

    print("\n✅ 完整验证完成")

if __name__ == "__main__":
    asyncio.run(main())
