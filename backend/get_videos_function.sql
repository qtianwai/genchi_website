-- 新增：获取店铺关联的视频信息
-- 用于在店铺详情页显示该店铺相关的抖音视频列表

create or replace function get_videos_by_restaurant(p_restaurant_id uuid)
returns table (
  video_id text,
  author_id uuid,
  author_name text,
  author_avatar_url text,
  created_at timestamptz
) as $$
begin
  return query
  select
    ar.video_id,
    a.id as author_id,
    a.name as author_name,
    a.avatar_url as author_avatar_url,
    ar.created_at
  from author_restaurants ar
  join authors a on ar.author_id = a.id
  where ar.restaurant_id = p_restaurant_id
    and ar.video_id is not null
    and ar.video_id != ''
  order by ar.created_at desc;
end;
$$ language plpgsql;
