-- get_videos_by_restaurant
-- 查询某店铺关联的所有视频信息（含博主资料和分享链接）
-- v7.1 修复：增加 video_parse_cache LEFT JOIN 以补全 video_url
--
-- 返回字段：
--   video_id      - 抖音视频 ID（author_restaurants.video_id）
--   author_id     - 博主 ID
--   author_name  - 博主昵称
--   author_avatar_url - 博主头像
--   created_at   - 推荐记录创建时间
--   video_url    - 抖音分享链接（来自 video_parse_cache，若为空则为空字符串）
--
-- 注意：author_restaurants.video_id 可为空（历史数据），
-- 此时 LEFT JOIN video_parse_cache 返回 NULL，
-- 前端 fallback 到博主 douyin_uid 打开抖音主页。

CREATE OR REPLACE FUNCTION get_videos_by_restaurant(p_restaurant_id UUID)
RETURNS TABLE (
    video_id         TEXT,
    author_id        UUID,
    author_name      TEXT,
    author_avatar_url TEXT,
    created_at       TIMESTAMPTZ,
    video_url        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ar.video_id         AS video_id,
        ar.author_id        AS author_id,
        a.name              AS author_name,
        a.avatar_url        AS author_avatar_url,
        ar.created_at       AS created_at,
        -- 优先从 video_parse_cache 取分享链接，没有则返回 NULL（前端子系统会 fallback）
        COALESCE(
            NULLIF(vpc.video_url, ''),
            NULL
        )                   AS video_url
    FROM author_restaurants ar
    -- 博主信息
    LEFT JOIN authors a ON a.id = ar.author_id
    -- 视频缓存（按 video_id 关联，获取抖音分享链接）
    LEFT JOIN video_parse_cache vpc
        ON vpc.video_id = ar.video_id
        AND vpc.video_id IS NOT NULL
    WHERE ar.restaurant_id = p_restaurant_id
      -- 保留有 video_id 的记录（即使 video_url 为 NULL，也允许前端展示博主主页入口）
      AND ar.video_id IS NOT NULL
    ORDER BY ar.created_at DESC;
END;
$$;

-- 授权（所有人可调用该函数读取数据）
GRANT EXECUTE ON FUNCTION get_videos_by_restaurant TO anon;
GRANT EXECUTE ON FUNCTION get_videos_by_restaurant TO authenticated;
