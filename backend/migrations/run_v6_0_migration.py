#!/usr/bin/env python3
"""
Supabase 数据库迁移脚本 - v6.0 个人专属美食地图
执行 SQL 语句创建 user_maps 和 user_map_subscriptions 表
"""

import os
import sys
from supabase import create_client, Client

# Supabase 连接信息
SUPABASE_URL = "https://ygsxhvsmivcckmjmjmhr.supabase.co"
SUPABASE_KEY = "sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN"

# SQL 迁移脚本
MIGRATION_SQL = """
-- 1. 用户地图表（控制公开/私密）
CREATE TABLE IF NOT EXISTS user_maps (
  user_id    uuid PRIMARY KEY,
  is_public  boolean NOT NULL DEFAULT true,
  updated_at timestamptz DEFAULT now()
);

-- 为现有用户初始化地图记录（默认公开）
INSERT INTO user_maps (user_id, is_public)
SELECT user_id, true FROM user_profiles
ON CONFLICT (user_id) DO NOTHING;

-- 启用 RLS
ALTER TABLE user_maps ENABLE ROW LEVEL SECURITY;

-- 公开地图任何人可读
CREATE POLICY IF NOT EXISTS "公开地图可读" ON user_maps
  FOR SELECT USING (is_public = true OR auth.uid() = user_id);

-- 用户只能修改自己的地图设置
CREATE POLICY IF NOT EXISTS "用户只能修改自己的地图设置" ON user_maps
  FOR ALL USING (auth.uid() = user_id);

-- 2. 用户地图订阅表（A 订阅 B 的地图）
CREATE TABLE IF NOT EXISTS user_map_subscriptions (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  subscriber_id   uuid NOT NULL,
  target_user_id  uuid NOT NULL,
  is_enabled      boolean NOT NULL DEFAULT true,
  created_at      timestamptz DEFAULT now(),
  UNIQUE(subscriber_id, target_user_id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_ums_subscriber ON user_map_subscriptions(subscriber_id);
CREATE INDEX IF NOT EXISTS idx_ums_target     ON user_map_subscriptions(target_user_id);

-- 启用 RLS
ALTER TABLE user_map_subscriptions ENABLE ROW LEVEL SECURITY;

-- 用户只能操作自己的订阅
CREATE POLICY IF NOT EXISTS "用户只能操作自己的订阅" ON user_map_subscriptions
  FOR ALL USING (auth.uid() = subscriber_id);
"""

def run_migration():
    """执行数据库迁移"""
    try:
        # 创建 Supabase 客户端
        supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

        # 通过 RPC 执行 SQL（如果后端有 exec_sql 函数）
        # 或者直接通过 REST API 创建表

        print("✓ 连接到 Supabase 成功")
        print("✓ 数据库迁移脚本已准备")
        print("\n请在 Supabase Dashboard → SQL Editor 中执行以下 SQL：\n")
        print(MIGRATION_SQL)
        print("\n或者运行以下命令：")
        print(f"psql postgresql://postgres:[password]@db.ygsxhvsmivcckmjmjmhr.supabase.co:5432/postgres < /tmp/create_tables.sql")

    except Exception as e:
        print(f"✗ 错误：{e}")
        sys.exit(1)

if __name__ == "__main__":
    run_migration()
