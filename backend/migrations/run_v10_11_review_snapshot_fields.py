# 数据库迁移脚本 v10.11 - 复核模块店铺快照字段
# 运行方式：python backend/migrations/run_v10_11_review_snapshot_fields.py

import os
from pathlib import Path

import httpx
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://ygsxhvsmivcckmjmjmhr.supabase.co")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN")


def run_sql(sql: str, description: str = "") -> bool:
    headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/rpc/exec_sql",
        headers=headers,
        json={"sql": sql},
        timeout=30,
    )
    if resp.status_code in (200, 204):
        print(f"  ✓ {description}")
        return True
    print(f"  ✗ {description}: {resp.text[:300]}")
    return False


def main() -> int:
    print("=" * 60)
    print("数据库迁移：复核模块店铺快照字段 v10.11")
    print("=" * 60)

    sql = Path(__file__).with_name("v10_11_review_snapshot_fields.sql").read_text(encoding="utf-8")
    if not run_sql(sql, "补齐 video_parse_cache.restaurant_avg_price / restaurant_photo_url"):
        return 1

    print("\n迁移完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
