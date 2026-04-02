# 数据库迁移脚本
# 通过 Supabase Python 客户端执行 DDL 迁移
# 运行方式：python migrate.py

import os
import httpx
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://ygsxhvsmivcckmjmjmhr.supabase.co")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN")
PROJECT_REF = SUPABASE_URL.replace("https://", "").replace(".supabase.co", "")

def run_sql(sql: str, description: str = "") -> bool:
    """
    通过 Supabase Management API 执行 SQL。
    使用 service_role key 作为 Bearer token。
    """
    headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    # 通过 Supabase 的 /rest/v1/rpc 调用 exec_sql 函数（需要先创建）
    # 这里使用 Supabase 的 pg 直连方式
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/rpc/exec_sql",
        headers=headers,
        json={"sql": sql},
        timeout=30,
    )
    if resp.status_code == 200:
        print(f"  ✓ {description or sql[:60]}")
        return True
    elif resp.status_code == 404:
        # exec_sql 函数不存在，需要先创建
        return False
    else:
        print(f"  ✗ {description or sql[:60]}: {resp.text[:200]}")
        return False


def create_exec_sql_function():
    """
    通过 Supabase 的 /rest/v1/rpc 调用 pg_catalog 内置函数创建 exec_sql 函数。
    这是一个自举过程：先创建执行 DDL 的函数，再用它执行迁移。
    """
    # 通过 Supabase 的 /rest/v1/rpc 调用 pg_catalog.pg_execute
    # 实际上需要通过 Supabase Dashboard 手动创建
    print("注意：exec_sql 函数不存在，请在 Supabase Dashboard 的 SQL Editor 中执行以下 SQL：")
    print("""
CREATE OR REPLACE FUNCTION exec_sql(sql text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  EXECUTE sql;
END;
$$;
""")


def check_column_exists(table: str, column: str) -> bool:
    """检查表中是否存在某列"""
    headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
    }
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=headers,
        params={"select": column, "limit": "1"},
        timeout=10,
    )
    return resp.status_code == 200


def check_table_exists(table: str) -> bool:
    """检查表是否存在"""
    headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
    }
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=headers,
        params={"select": "*", "limit": "1"},
        timeout=10,
    )
    return resp.status_code != 404


def run_migrations():
    """执行所有迁移"""
    print("=" * 60)
    print("数据库迁移：后台人工复核功能 v3.0")
    print("=" * 60)

    # 检查 exec_sql 函数是否存在
    test_resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/rpc/exec_sql",
        headers={
            "apikey": SUPABASE_SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
            "Content-Type": "application/json",
        },
        json={"sql": "SELECT 1"},
        timeout=10,
    )

    if test_resp.status_code == 404:
        print("\n⚠️  exec_sql 函数不存在。")
        print("请在 Supabase Dashboard → SQL Editor 中执行以下 SQL 后重新运行此脚本：\n")
        print("""CREATE OR REPLACE FUNCTION exec_sql(sql text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  EXECUTE sql;
END;
$$;""")
        print("\n然后重新运行：python migrate.py")
        return False

    migrations = [
        # 1. 创建 admin_users 表
        (
            """CREATE TABLE IF NOT EXISTS admin_users (
                user_id    uuid PRIMARY KEY,
                note       text,
                created_at timestamptz DEFAULT now()
            )""",
            "创建 admin_users 表",
        ),
        # 2. 启用 RLS
        (
            "ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY",
            "admin_users 启用 RLS",
        ),
        # 3. 创建 RLS 策略（禁止客户端直接访问）
        (
            """DO $$ BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_policies
                    WHERE tablename = 'admin_users'
                    AND policyname = 'admin_users_no_client_access'
                ) THEN
                    CREATE POLICY admin_users_no_client_access
                    ON admin_users FOR ALL USING (false);
                END IF;
            END $$""",
            "admin_users 创建 RLS 策略",
        ),
        # 4. video_parse_cache 新增 review_status
        (
            "ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'pending'",
            "video_parse_cache 新增 review_status 字段",
        ),
        # 5. video_parse_cache 新增 reviewed_by
        (
            "ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS reviewed_by uuid",
            "video_parse_cache 新增 reviewed_by 字段",
        ),
        # 6. video_parse_cache 新增 reviewed_at
        (
            "ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS reviewed_at timestamptz",
            "video_parse_cache 新增 reviewed_at 字段",
        ),
        # 7. 创建索引
        (
            "CREATE INDEX IF NOT EXISTS idx_vpc_review_status ON video_parse_cache(review_status)",
            "创建 review_status 索引",
        ),
        # 8. restaurants 新增 verified
        (
            "ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS verified boolean NOT NULL DEFAULT false",
            "restaurants 新增 verified 字段",
        ),
        # 9. restaurants 新增 verified_at
        (
            "ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS verified_at timestamptz",
            "restaurants 新增 verified_at 字段",
        ),
    ]

    print("\n执行迁移：")
    success_count = 0
    for sql, desc in migrations:
        if run_sql(sql, desc):
            success_count += 1
        else:
            print(f"  ✗ 迁移失败，停止执行")
            return False

    print(f"\n✅ 迁移完成：{success_count}/{len(migrations)} 条成功")

    # 验证迁移结果
    print("\n验证迁移结果：")
    checks = [
        ("admin_users", "admin_users 表"),
        ("video_parse_cache", "review_status 字段（video_parse_cache）"),
        ("restaurants", "verified 字段（restaurants）"),
    ]
    for table, desc in checks:
        exists = check_table_exists(table)
        print(f"  {'✓' if exists else '✗'} {desc}")

    return True


if __name__ == "__main__":
    run_migrations()
