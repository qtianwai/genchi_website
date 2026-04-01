#!/usr/bin/env python3
"""检查迁移失败的 bg:// 记录"""

import requests

SUPABASE_URL = "https://ygsxhvsmivcckmjmjmhr.supabase.co"
SUPABASE_KEY = "sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN"

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json"
}

# 查找所有仍然是 bg:// 开头的记录
resp = requests.get(
    f"{SUPABASE_URL}/rest/v1/video_parse_cache",
    headers=headers,
    params={
        "select": "video_id,video_url,author_sec_uid,created_at",
        "video_url": "like.bg://%"
    }
)

data = resp.json()
if not data:
    print("✅ 所有 bg:// 记录已成功迁移！")
    exit(0)

print(f"⚠️  发现 {len(data)} 条未迁移的 bg:// 记录：\n")

for idx, row in enumerate(data, 1):
    print(f"{idx}. video_id: {row['video_id']}")
    print(f"   video_url: {row['video_url']}")
    print(f"   author_sec_uid: {row.get('author_sec_uid', '(空)')}")
    print(f"   created_at: {row['created_at']}")

    # 尝试用 JustOneAPI 获取视频信息
    video_id = row['video_id']
    api_resp = requests.get(
        "https://api.justone-api.com/api/douyin/get-video-info/v3",
        params={"video_id": video_id},
        headers={"Authorization": "Bearer 2UJdMdkQiP4xaOIS"}
    )

    if api_resp.status_code == 200:
        api_data = api_resp.json()
        if api_data.get("code") == 200:
            share_url = api_data.get("data", {}).get("share_url")
            if share_url:
                print(f"   ✅ API 可获取 share_url: {share_url}")
            else:
                print(f"   ❌ API 返回成功但无 share_url")
        else:
            print(f"   ❌ API 返回错误: {api_data.get('message', 'unknown')}")
    else:
        print(f"   ❌ API 请求失败: {api_resp.status_code}")

    print()
