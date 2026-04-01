#!/usr/bin/env python3
"""
诊断：查看完整评论结构，包括 user、is_author_digged、reply_comment 等字段
"""
import httpx
import os
import json

TOKEN = os.getenv("JUSTONEAPI_TOKEN", "2UJdMdkQiP4xaOIS")
BASE = "https://api.justoneapi.com"

def get(path, params=None):
    params = params or {}
    params["token"] = TOKEN
    params = {k: v for k, v in params.items() if v is not None}
    with httpx.Client(timeout=30, follow_redirects=True) as client:
        resp = client.get(f"{BASE}{path}", params=params)
        return resp.json()

VIDEO_ID = "7621134274259171761"
AUTHOR_UID = "84161710260"  # 博主 uid

raw = get("/api/douyin/get-video-comment/v1", {"awemeId": VIDEO_ID, "page": 1})
comments = (raw.get("data") or {}).get("comments", []) or []

print(f"共 {len(comments)} 条评论")
print(f"博主 uid: {AUTHOR_UID}")
print()

# 分析每条评论的字段
for i, c in enumerate(comments[:5]):
    print(f"--- 评论{i+1} ---")
    print(f"  text: {c.get('text')}")
    print(f"  digg_count: {c.get('digg_count')}")
    print(f"  is_author_digged: {c.get('is_author_digged')}")
    print(f"  is_hot: {c.get('is_hot')}")
    print(f"  is_note_comment: {c.get('is_note_comment')}")
    print(f"  reply_count: {c.get('reply_comment_total', 0)}")

    # 回复列表
    replies = c.get("reply_comment", []) or []
    if replies:
        print(f"  回复数: {len(replies)}")
        for j, r in enumerate(replies[:3]):
            print(f"    回复{j+1}: [{r.get('digg_count')}赞] {r.get('text', '')[:60]}")
            print(f"    回复用户: {r.get('user', {}).get('nickname')} (uid={r.get('user', {}).get('uid')})")
    print()

# 筛选博主点赞/置顶的评论
print("=" * 60)
print("博主点赞的评论（is_author_digged=True）：")
author_liked = [c for c in comments if c.get("is_author_digged")]
for c in author_liked:
    print(f"  [{c['digg_count']}赞] {c['text'][:60]}")

print()
print("热门评论（is_hot=True）：")
hot = [c for c in comments if c.get("is_hot")]
for c in hot:
    print(f"  [{c['digg_count']}赞] {c['text'][:60]}")

# 看看 reply_comment 的结构
print()
print("=" * 60)
print("检查回复列表的完整结构")
if replies := (comments[0] or {}).get("reply_comment"):
    print(f"reply_comment keys: {list(replies[0].keys()) if replies else '空'}")
    if replies:
        print(f"第一条回复完整内容:\n{json.dumps(replies[0], ensure_ascii=False, indent=2)[:600]}")
