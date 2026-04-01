-- 获取店铺关联的视频信息
-- 用于在店铺详情页显示该店铺相关的抖音视频列表
-- video_url 从 video_parse_cache 表中获取（真实的抖音分享链接）

create or replace function get_videos_by_restaurant(p_restaurant_id uuid)
returns table (
  video_id text,
  author_id uuid,
  author_name text,
  author_avatar_url text,
  video_url text,       -- 抖音视频分享链接（可直接在抖音中打开）
  created_at timestamptz
) as $$
begin
  return query
  select
    ar.video_id,
    a.id as author_id,
    a.name as author_name,
    a.avatar_url as author_avatar_url,
    -- 从 video_parse_cache 获取真实链接，过滤掉 bg:// 占位符
    -- 用子查询确保每个 video_id 只取一条最新的有效 video_url，避免 join 多行导致结果混乱
    (
      select vpc.video_url
      from video_parse_cache vpc
      where vpc.video_id = ar.video_id
        and vpc.video_url is not null
        and vpc.video_url not like 'bg://%'
      order by vpc.created_at desc
      limit 1
    ) as video_url,
    ar.created_at
  from author_restaurants ar
  join authors a on ar.author_id = a.id
  where ar.restaurant_id = p_restaurant_id
    and ar.video_id is not null
    and ar.video_id != ''
  order by ar.created_at desc;
end;
$$ language plpgsql;
