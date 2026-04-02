-- ============================================================
-- 数据库迁移脚本 v3.0：后台人工复核功能
-- 执行方式：在 Supabase Dashboard → SQL Editor 中粘贴并运行
-- ============================================================

-- 1. 创建管理员用户表
CREATE TABLE IF NOT EXISTS admin_users (
    user_id    uuid PRIMARY KEY,
    note       text,
    created_at timestamptz DEFAULT now()
);

-- 2. 启用 RLS（禁止客户端直接访问，只有后端 service_role 可读）
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- 3. 创建 RLS 策略（所有客户端请求均拒绝）
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'admin_users'
        AND policyname = 'admin_users_no_client_access'
    ) THEN
        CREATE POLICY admin_users_no_client_access
        ON admin_users FOR ALL USING (false);
    END IF;
END $$;

-- 4. video_parse_cache 新增复核状态字段
--    review_status 枚举值：pending / approved / corrected / confirmed / skipped
ALTER TABLE video_parse_cache
    ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS reviewed_by   uuid,
    ADD COLUMN IF NOT EXISTS reviewed_at   timestamptz;

-- 5. 为 review_status 创建索引（复核列表查询会频繁过滤此字段）
CREATE INDEX IF NOT EXISTS idx_vpc_review_status ON video_parse_cache(review_status);

-- 6. restaurants 新增人工验证字段
ALTER TABLE restaurants
    ADD COLUMN IF NOT EXISTS verified    boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS verified_at timestamptz;

-- ============================================================
-- 验证迁移结果（执行后检查输出是否符合预期）
-- ============================================================

-- 检查 admin_users 表是否存在
SELECT 'admin_users 表' AS check_item,
       EXISTS (
           SELECT 1 FROM information_schema.tables
           WHERE table_name = 'admin_users'
       ) AS result;

-- 检查 video_parse_cache 新字段
SELECT 'video_parse_cache.review_status' AS check_item,
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'video_parse_cache' AND column_name = 'review_status'
       ) AS result
UNION ALL
SELECT 'video_parse_cache.reviewed_by',
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'video_parse_cache' AND column_name = 'reviewed_by'
       )
UNION ALL
SELECT 'video_parse_cache.reviewed_at',
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'video_parse_cache' AND column_name = 'reviewed_at'
       );

-- 检查 restaurants 新字段
SELECT 'restaurants.verified' AS check_item,
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'restaurants' AND column_name = 'verified'
       ) AS result
UNION ALL
SELECT 'restaurants.verified_at',
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'restaurants' AND column_name = 'verified_at'
       );
