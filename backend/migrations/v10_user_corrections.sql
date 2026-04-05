-- v10.0 新增：用户勘误表
-- 在 Supabase Dashboard → SQL Editor 中执行此文件

create table if not exists user_corrections (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null,
  restaurant_id     uuid references restaurants(id),
  video_cache_id    uuid references video_parse_cache(id),
  correction_type   text not null,
  correction_detail text,
  status            text not null default 'pending',
  reviewed_by       uuid,
  reviewed_at       timestamptz,
  review_note       text,
  created_at        timestamptz default now()
);

create index if not exists idx_user_corrections_status on user_corrections(status);
create index if not exists idx_user_corrections_restaurant on user_corrections(restaurant_id);
create index if not exists idx_user_corrections_video_cache on user_corrections(video_cache_id);
