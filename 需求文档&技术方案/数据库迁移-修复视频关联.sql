-- 数据库迁移脚本：修复博主-店铺-视频关联表结构
-- 执行时间：2026-04-01
-- 目的：允许同一博主-店铺组合有多个视频记录，解决视频列表显示问题

-- 步骤1：删除旧的唯一约束
ALTER TABLE author_restaurants
DROP CONSTRAINT IF EXISTS author_restaurants_author_id_restaurant_id_key;

-- 步骤2：添加新的唯一约束（包含 video_id）
ALTER TABLE author_restaurants
ADD CONSTRAINT author_restaurants_author_id_restaurant_id_video_id_key
UNIQUE (author_id, restaurant_id, video_id);

-- 步骤3：为 video_id 字段添加索引（提升查询性能）
CREATE INDEX IF NOT EXISTS idx_author_restaurants_video ON author_restaurants(video_id);

-- 验证：查询某个店铺的所有关联视频
-- SELECT * FROM author_restaurants WHERE restaurant_id = 'your-restaurant-id' ORDER BY created_at DESC;
