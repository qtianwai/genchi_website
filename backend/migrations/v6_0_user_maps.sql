-- ============================================================
-- v6.0 个人专属美食地图 - 数据库迁移脚本
-- 执行位置：Supabase Dashboard → SQL Editor
-- ============================================================

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
CREATE POLICY "公开地图可读" ON user_maps
  FOR SELECT USING (is_public = true OR auth.uid() = user_id);

-- 用户只能修改自己的地图设置
CREATE POLICY "用户只能修改自己的地图设置" ON user_maps
  FOR ALL USING (auth.uid() = user_id);

-- ============================================================

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
CREATE POLICY "用户只能操作自己的订阅" ON user_map_subscriptions
  FOR ALL USING (auth.uid() = subscriber_id);

-- ============================================================
-- 迁移完成
-- ============================================================
