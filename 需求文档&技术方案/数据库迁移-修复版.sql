-- 数据库迁移脚本（修复版）：修复博主-店铺-视频关联表结构
-- 执行时间：2026-04-01

-- 第一步：删除所有可能存在的旧约束
DO $$
BEGIN
    -- 删除旧的双字段唯一约束
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'author_restaurants_author_id_restaurant_id_key'
    ) THEN
        ALTER TABLE author_restaurants
        DROP CONSTRAINT author_restaurants_author_id_restaurant_id_key;
    END IF;

    -- 删除可能已存在的新约束
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'author_restaurants_author_id_restaurant_id_video_id_key'
    ) THEN
        ALTER TABLE author_restaurants
        DROP CONSTRAINT author_restaurants_author_id_restaurant_id_video_id_key;
    END IF;
END $$;

-- 第二步：添加新的唯一约束（包含 video_id）
ALTER TABLE author_restaurants
ADD CONSTRAINT author_restaurants_author_id_restaurant_id_video_id_key
UNIQUE (author_id, restaurant_id, video_id);

-- 第三步：为 video_id 字段添加索引（提升查询性能）
CREATE INDEX IF NOT EXISTS idx_author_restaurants_video ON author_restaurants(video_id);

-- 第四步：清空旧数据
TRUNCATE TABLE author_restaurants;

-- 第五步：创建获取视频函数
CREATE OR REPLACE FUNCTION get_videos_by_restaurant(p_restaurant_id uuid)
RETURNS TABLE (
  video_id text,
  author_id uuid,
  author_name text,
  author_avatar_url text,
  created_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ar.video_id,
    a.id as author_id,
    a.name as author_name,
    a.avatar_url as author_avatar_url,
    ar.created_at
  FROM author_restaurants ar
  JOIN authors a ON ar.author_id = a.id
  WHERE ar.restaurant_id = p_restaurant_id
    AND ar.video_id IS NOT NULL
    AND ar.video_id != ''
  ORDER BY ar.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- 验证：查询清理后的数据量（应该为 0）
SELECT COUNT(*) as remaining_count FROM author_restaurants;
