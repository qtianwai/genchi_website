#!/usr/bin/env python3
"""验证 get_videos_by_restaurant 函数是否正确返回 video_url"""

import requests
import json

SUPABASE_URL = "https://ygsxhvsmivcckmjmjmhr.supabase.co"
SUPABASE_KEY = "sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN"

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json"
}

# 1. 找一个有视频的餐厅
print("🔍 查找有视频的餐厅...")
resp = requests.get(
    f"{SUPABASE_URL}/rest/v1/video_parse_cache",
    headers=headers,
    params={"select": "restaurant_id", "restaurant_id": "not.is.null", "limit": 1}
)
rows = resp.json()
if not rows:
    print("❌ video_parse_cache 中没有关联餐厅的视频")
    exit(1)

restaurant_id = rows[0]["restaurant_id"]
print(f"📍 测试餐厅 ID: {restaurant_id}")

# 2. 调用 RPC 函数
resp = requests.post(
    f"{SUPABASE_URL}/rest/v1/rpc/get_videos_by_restaurant",
    headers=headers,
    json={"p_restaurant_id": restaurant_id}
)

if resp.status_code != 200:
    print(f"❌ RPC 调用失败: {resp.status_code} {resp.text}")
    exit(1)

data = resp.json()
if not data:
    print("⚠️  该餐厅无关联视频")
    exit(0)

print(f"\n✅ 返回 {len(data)} 条视频\n")

# 3. 检查字段
first = data[0]
fields = ["video_id", "video_url", "author_name", "author_avatar", "video_desc"]
for field in fields:
    value = first.get(field)
    status = "✅" if value else "❌"
    print(f"  {status} {field}: {str(value)[:80] if value else '(空)'}")

# 4. 判断 video_url 质量
video_url = first.get("video_url", "")
print()
if video_url.startswith("bg://"):
    print(f"⚠️  video_url 仍是占位符，迁移未生效: {video_url}")
elif video_url.startswith("http"):
    print(f"✅ video_url 是真实链接，一切正常！")
elif not video_url:
    print(f"❌ video_url 为空，函数可能未正确关联 video_parse_cache")
else:
    print(f"❓ video_url 格式未知: {video_url}")
