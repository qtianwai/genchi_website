# 数据库迁移脚本 v4.0 - 用户自建推荐店铺
# 运行方式：python migrate_v4_user_restaurants.py
# 前提：需要在 Supabase Dashboard SQL Editor 中先创建 exec_sql 函数（见 migrate.py 注释）

import os
import httpx
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://ygsxhvsmivcckmjmjmhr.supabase.co")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN")


def run_sql(sql: str, description: str = "") -> bool:
    """通过 exec_sql RPC 函数执行 SQL"""
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
        print(f"  ✓ {description or sql[:60]}")
        return True
    else:
        print(f"  ✗ {description}: {resp.text[:200]}")
        return False


def check_table_exists(table: str) -> bool:
    """检查表是否存在"""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers={
            "apikey": SUPABASE_SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        },
        params={"select": "*", "limit": "1"},
        timeout=10,
    )
    return resp.status_code != 404


def run_migrations():
    print("=" * 60)
    print("数据库迁移：用户自建推荐店铺 v4.0")
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
        print("\n然后重新运行：python migrate_v4_user_restaurants.py")
        return False

    migrations = [
        # 1. 创建 user_created_restaurants 表
        (
            """CREATE TABLE IF NOT EXISTS user_created_restaurants (
                id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
                user_id         uuid NOT NULL,
                restaurant_id   uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
                note            text,
                created_at      timestamptz DEFAULT now(),
                UNIQUE(user_id, restaurant_id)
            )""",
            "创建 user_created_restaurants 表",
        ),
        # 2. 创建索引
        (
            "CREATE INDEX IF NOT EXISTS idx_ucr_user ON user_created_restaurants(user_id)",
            "创建 idx_ucr_user 索引",
        ),
        (
            "CREATE INDEX IF NOT EXISTS idx_ucr_restaurant ON user_created_restaurants(restaurant_id)",
            "创建 idx_ucr_restaurant 索引",
        ),
        # 3. 启用 RLS
        (
            "ALTER TABLE user_created_restaurants ENABLE ROW LEVEL SECURITY",
            "user_created_restaurants 启用 RLS",
        ),
        # 4. 创建 RLS 策略
        (
            """DO $$ BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_policies
                    WHERE tablename = 'user_created_restaurants'
                    AND policyname = '用户只能查看自己的自建推荐'
                ) THEN
                    CREATE POLICY "用户只能查看自己的自建推荐"
                    ON user_created_restaurants FOR SELECT USING (auth.uid() = user_id);
                END IF;
            END $$""",
            "创建 SELECT RLS 策略",
        ),
        (
            """DO $$ BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_policies
                    WHERE tablename = 'user_created_restaurants'
                    AND policyname = '用户只能添加自己的自建推荐'
                ) THEN
                    CREATE POLICY "用户只能添加自己的自建推荐"
                    ON user_created_restaurants FOR INSERT WITH CHECK (auth.uid() = user_id);
                END IF;
            END $$""",
            "创建 INSERT RLS 策略",
        ),
        (
            """DO $$ BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_policies
                    WHERE tablename = 'user_created_restaurants'
                    AND policyname = '用户只能删除自己的自建推荐'
                ) THEN
                    CREATE POLICY "用户只能删除自己的自建推荐"
                    ON user_created_restaurants FOR DELETE USING (auth.uid() = user_id);
                END IF;
            END $$""",
            "创建 DELETE RLS 策略",
        ),
    ]

    print("\n执行迁移：")
    for sql, desc in migrations:
        if not run_sql(sql, desc):
            print("  迁移失败，停止执行")
            return False

    print(f"\n✅ 迁移完成：{len(migrations)}/{len(migrations)} 条成功")

    # 验证
    print("\n验证迁移结果：")
    exists = check_table_exists("user_created_restaurants")
    print(f"  {'✓' if exists else '✗'} user_created_restaurants 表")
    return True


if __name__ == "__main__":
    run_migrations()
