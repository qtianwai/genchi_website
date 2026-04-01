#!/usr/bin/env python3
"""
诊断脚本（修正版）：直接测试 JustOneAPI 各接口的原始响应
"""
import httpx
import re
import os

TOKEN = os.getenv("JUSTONEAPI_TOKEN", "2UJdMdkQiP4xaOIS")
BASE = "https://api.justoneapi.com"

def get(path, params=None):
    params = params or {}
    params["token"] = TOKEN
    params = {k: v for k, v in params.items() if v is not None}
    with httpx.Client(timeout=30, follow_redirects=True) as client:
        resp = client.get(f"{BASE}{path}", params=params)
        return resp.status_code, resp.json()


# 测试链接
TEST_URL = "https://v.douyin.com/4zIppExRIAg/"

print("=" * 60)
print("1. share-url-transfer/v1")
print("=" * 60)
code, data = get("/api/douyin/share-url-transfer/v1", {"shareUrl": TEST_URL})
print(f"status_code={code}, code={data.get('code')}, message={data.get('message')}")
redirect_url = (data.get("data") or {}).get("redirect_url", "")
print(f"redirect_url: {redirect_url}")

# 修正：支持 ?previous_page=... 格式
match = re.search(r'/video/(\d+)', redirect_url)
video_id = match.group(1) if match else None
print(f"提取到视频ID: {video_id}")

print("\n" + "=" * 60)
print("2. get-video-detail/v2")
print("=" * 60)
if video_id:
    code2, data2 = get("/api/douyin/get-video-detail/v2", {"videoId": video_id})
    print(f"status_code={code2}, code={data2.get('code')}, message={data2.get('message')}")
    if data2.get("code") == 0:
        aweme = data2.get("data", {}).get("aweme_detail", {})
        author = aweme.get("author", {})
        print(f"  标题: {aweme.get('desc', '')[:80]}")
        print(f"  博主昵称: {author.get('nickname')}")
        print(f"  博主uid: {author.get('uid')}")
        print(f"  博主sec_uid: {author.get('sec_uid', '')}")
        print(f"  博主头像: {author.get('avatar_thumb', {}).get('url_list', [''])[0][:60]}...")
        # 看看有哪些额外字段
        print(f"  aweme keys: {list(aweme.keys())}")
    else:
        print(f"  完整响应: {data2}")

print("\n" + "=" * 60)
print("3. get-user-video-list/v3 (博主视频列表)")
print("=" * 60)
if video_id:
    sec_uid = None
    code2b, data2b = get("/api/douyin/get-video-detail/v2", {"videoId": video_id})
    if data2b.get("code") == 0:
        sec_uid = data2b.get("data", {}).get("aweme_detail", {}).get("author", {}).get("sec_uid", "")
    if sec_uid:
        print(f"使用 sec_uid: {sec_uid[:40]}...")
        code3, data3 = get("/api/douyin/get-user-video-list/v3", {"secUid": sec_uid, "maxCursor": 0})
        print(f"status_code={code3}, code={data3.get('code')}, message={data3.get('message')}")
        if data3.get("code") == 0:
            aweme_list = data3.get("data", {}).get("aweme_list", []) or []
            print(f"获取到 {len(aweme_list)} 条视频（总数: {data3.get('data', {}).get('total', '?')}）")
            for v in aweme_list[:5]:
                print(f"  - [{v.get('aweme_id')}] {v.get('desc', '')[:60]}")
        else:
            print(f"  完整响应: {data3}")
    else:
        print("无法获取 sec_uid")

print("\n" + "=" * 60)
print("4. get-video-comment/v1 (视频评论)")
print("=" * 60)
if video_id:
    code4, data4 = get("/api/douyin/get-video-comment/v1", {"awemeId": video_id, "page": 1})
    print(f"status_code={code4}, code={data4.get('code')}, message={data4.get('message')}")
    if data4.get("code") == 0:
        comments = (data4.get("data") or {}).get("comments", []) or []
        print(f"获取到 {len(comments)} 条评论")
        for c in comments[:10]:
            text = c.get("text", "")[:60]
            digg = c.get("digg_count", 0)
            reply_count = c.get("reply_count", 0)
            print(f"  [{digg}赞 | 回复{reply_count}] {text}")
    else:
        print(f"  完整响应: {data4}")

print("\n" + "=" * 60)
print("诊断完成")
print("=" * 60)
