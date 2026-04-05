-- =============================================
-- v10.10 饭团养成体系 — 数据库迁移脚本
-- 在 Supabase Dashboard → SQL Editor 中执行
-- =============================================

-- 1. 创建 fantuan_status 表
CREATE TABLE IF NOT EXISTS fantuan_status (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    satiety INTEGER NOT NULL DEFAULT 80,               -- 饱食度 0-100
    intimacy INTEGER NOT NULL DEFAULT 0,               -- 亲密度 0-∞
    intimacy_level INTEGER NOT NULL DEFAULT 1,         -- 亲密度等级 1-5
    consecutive_login_days INTEGER NOT NULL DEFAULT 0,  -- 连续登录天数
    last_login_date DATE,                              -- 最后登录日期
    last_pet_date DATE,                                -- 最后摸摸日期
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

-- 2. 索引
CREATE INDEX IF NOT EXISTS idx_fantuan_status_user ON fantuan_status(user_id);

-- 3. RLS 策略（使用 service_role key 绕过，但仍需启用 RLS）
ALTER TABLE fantuan_status ENABLE ROW LEVEL SECURITY;

-- 允许 service_role 完整访问
CREATE POLICY "service_role_full_access" ON fantuan_status
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- 4. 验证
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'fantuan_status'
ORDER BY ordinal_position;
