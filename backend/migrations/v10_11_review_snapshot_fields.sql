-- v10.11 新增：复核模块店铺快照字段
-- 用途：video_parse_cache 直接存店铺图片和均价，避免复核列表/详情额外联表

ALTER TABLE video_parse_cache
ADD COLUMN IF NOT EXISTS restaurant_avg_price integer;

ALTER TABLE video_parse_cache
ADD COLUMN IF NOT EXISTS restaurant_photo_url text;
