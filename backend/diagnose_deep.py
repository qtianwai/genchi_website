#!/usr/bin/env python3
"""
深入诊断：挖掘 get-video-detail/v2 中所有可能与店铺相关的字段
"""
import httpx
import re
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

video_id = "7621134274259171761"  # 示例视频

data = get("/api/douyin/get-video-detail/v2", {"videoId": video_id})
aweme = data.get("data", {}).get("aweme_detail", {})

print("=" * 60)
print("1. poi_biz（店铺信息）")
print("=" * 60)
poi_biz = aweme.get("poi_biz", {})
print(json.dumps(poi_biz, ensure_ascii=False, indent=2)[:1000])

print("\n" + "=" * 60)
print("2. cha_list（话题列表）")
print("=" * 60)
cha_list = aweme.get("cha_list", []) or []
for c in cha_list:
    print(f"  话题: {c.get('cha_name')} | view_count: {c.get('view_count', 0)}")

print("\n" + "=" * 60)
print("3. geofencing（地理围栏/城市）")
print("=" * 60)
geo = aweme.get("geofencing", []) or []
for g in geo:
    print(f"  {g}")

print("\n" + "=" * 60)
print("4. city（城市字段）")
print("=" * 60)
print(aweme.get("city"))

print("\n" + "=" * 60)
print("5. statistics（统计数据）")
print("=" * 60)
print(json.dumps(aweme.get("statistics", {}), ensure_ascii=False, indent=2))

print("\n" + "=" * 60)
print("6. text_extra（标题中的话题标签详情）")
print("=" * 60)
text_extra = aweme.get("text_extra", []) or []
for t in text_extra:
    print(f"  type={t.get('type')}, hashtag_name={t.get('hashtag_name')}, hashtag_id={t.get('hashtag_id')}")

print("\n" + "=" * 60)
print("7. interaction_stickers（互动贴纸）")
print("=" * 60)
stickers = aweme.get("interaction_stickers", []) or []
for s in stickers[:3]:
    print(f"  {json.dumps(s, ensure_ascii=False)[:100]}")

print("\n" + "=" * 60)
print("8. comment_list（内嵌评论）")
print("=" * 60)
comment_list = aweme.get("comment_list", []) or []
print(f"共 {len(comment_list)} 条内嵌评论")
for c in comment_list[:5]:
    text = c.get("text", "")
    digg = c.get("digg_count", 0)
    reply = c.get("reply_count", 0)
    print(f"  [{digg}赞 | 回复{reply}] {text[:60]}")

print("\n" + "=" * 60)
print("9. comment_gid")
print("=" * 60)
print(aweme.get("comment_gid"))

print("\n" + "=" * 60)
print("10. anchors（锚点信息）")
print("=" * 60)
anchors = aweme.get("anchors", []) or []
for a in anchors[:3]:
    print(f"  {json.dumps(a, ensure_ascii=False)[:150]}")

print("\n" + "=" * 60)
print("11. label_top_text")
print("=" * 60)
print(aweme.get("label_top_text"))

print("\n" + "=" * 60)
print("12. origin_comment_ids")
print("=" * 60)
print(json.dumps(aweme.get("origin_comment_ids", {}), ensure_ascii=False, indent=2)[:500])

print("\n" + "=" * 60)
print("13. promotion（推广信息）")
print("=" * 60)
promo = aweme.get("promotions", []) or []
for p in promo:
    print(f"  {json.dumps(p, ensure_ascii=False)[:200]}")

print("\n" + "=" * 60)
print("14. author_comments（博主回复）")
print("=" * 60)
# 检查 statistics 里有没有评论相关
stats = aweme.get("statistics", {})
print(f"评论数: {stats.get('comment_count', 0)}")

print("\n" + "=" * 60)
print("15. video_text（视频字幕文本）")
print("=" * 60)
video_text = aweme.get("video_text", [])
if isinstance(video_text, list):
    for vt in video_text[:3]:
        print(f"  {json.dumps(vt, ensure_ascii=False)[:200]}")
elif isinstance(video_text, dict):
    print(json.dumps(video_text, ensure_ascii=False, indent=2)[:500])
else:
    print(video_text)

print("\n诊断完成")
