# v15.0 用户反馈系统 - 通过 psycopg2 直接执行 SQL 建表
import os
import sys
sys.path.insert(0, os.path.dirname(__file__) + "/..")
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

import psycopg2

# 从 SUPABASE_URL 提取数据库连接信息
# Supabase URL 格式: https://xxx.supabase.co
# 数据库连接: postgresql://postgres:[password]@db.xxx.supabase.co:5432/postgres
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

# 提取 project ref
project_ref = SUPABASE_URL.replace("https://", "").replace(".supabase.co", "")
DB_HOST = f"db.{project_ref}.supabase.co"
DB_PASSWORD = os.getenv("SUPABASE_DB_PASSWORD", "")

SQL = """
-- 22. 用户反馈表
CREATE TABLE IF NOT EXISTS user_feedback (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         uuid NOT NULL,
  category        text NOT NULL,
  content         text NOT NULL,
  image_urls      text[],
  device_model    text,
  ios_version     text,
  app_version     text,
  status          text NOT NULL DEFAULT 'pending',
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feedback_user ON user_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON user_feedback(status);
CREATE INDEX IF NOT EXISTS idx_feedback_created ON user_feedback(created_at DESC);

-- 23. 用户反馈回复表
CREATE TABLE IF NOT EXISTS user_feedback_replies (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  feedback_id     uuid NOT NULL REFERENCES user_feedback(id) ON DELETE CASCADE,
  admin_user_id   uuid NOT NULL,
  content         text NOT NULL,
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feedback_replies_fid ON user_feedback_replies(feedback_id);
"""

if __name__ == "__main__":
    if not DB_PASSWORD:
        print("请设置 SUPABASE_DB_PASSWORD 环境变量（Supabase Dashboard → Settings → Database → Connection string 中的密码）")
        print("或者直接在 Supabase Dashboard 的 SQL Editor 中执行以下 SQL：")
        print("=" * 60)
        print(SQL)
        print("=" * 60)
        sys.exit(1)

    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=5432, dbname="postgres",
            user="postgres", password=DB_PASSWORD,
            sslmode="require"
        )
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(SQL)
        print("[OK] user_feedback + user_feedback_replies 表创建成功")
        cur.close()
        conn.close()
    except Exception as e:
        print(f"[ERROR] 连接失败: {e}")
        print("请在 Supabase Dashboard 的 SQL Editor 中手动执行以上 SQL")
