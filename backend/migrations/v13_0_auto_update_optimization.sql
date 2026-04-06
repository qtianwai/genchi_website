-- v13.0 数据库迁移脚本
-- 博主自动更新检测优化 + 解析成本优化

-- authors 表新增字段
ALTER TABLE authors ADD COLUMN IF NOT EXISTS food_video_ratio float DEFAULT 0;
ALTER TABLE authors ADD COLUMN IF NOT EXISTS food_video_count int DEFAULT 0;
ALTER TABLE authors ADD COLUMN IF NOT EXISTS last_food_video_at timestamptz;

-- author_background_tasks 表新增字段
ALTER TABLE author_background_tasks ADD COLUMN IF NOT EXISTS api_cost numeric(10,6) DEFAULT 0;
ALTER TABLE author_background_tasks ADD COLUMN IF NOT EXISTS api_cost_note text DEFAULT '';
