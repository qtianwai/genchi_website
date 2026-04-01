-- 数据库清理脚本：清空博主-店铺关联表，准备重新解析
-- 执行时间：2026-04-01
-- 目的：清除旧的单视频关联数据，准备重新解析生成多视频关联数据

-- ⚠️ 警告：此操作会删除所有博主-店铺关联关系，但不会删除店铺和博主数据
-- 重新粘贴视频链接后，会自动重新建立关联关系

-- 方案1：清空所有博主-店铺关联数据（推荐）
TRUNCATE TABLE author_restaurants;

-- 方案2：只清空特定博主的关联数据（如果只想清理某个博主）
-- DELETE FROM author_restaurants WHERE author_id = 'your-author-id';

-- 方案3：只清空特定店铺的关联数据（如果只想清理某个店铺）
-- DELETE FROM author_restaurants WHERE restaurant_id = 'your-restaurant-id';

-- 验证：查询清理后的数据量
SELECT COUNT(*) as remaining_count FROM author_restaurants;

-- 说明：
-- 1. 清理后，用户需要重新粘贴视频链接，系统会自动重新解析并建立关联
-- 2. 因为有 video_parse_cache 缓存，重新解析速度很快（不会重复调用 AI）
-- 3. 店铺数据（restaurants 表）和博主数据（authors 表）不会被删除
-- 4. 用户的关注关系（user_follows）和收藏（user_favorites）不会被删除
