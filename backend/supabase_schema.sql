-- =====================================================
-- 达人美食推荐 App - Supabase 数据库表结构
-- 在 Supabase 控制台的 SQL Editor 中执行此文件
-- =====================================================

-- 启用 UUID 扩展（Supabase 默认已启用）
create extension if not exists "uuid-ossp";


-- ─────────────────────────────────────────
-- 1. 博主表
-- 存储抖音博主的基本信息
-- ─────────────────────────────────────────
create table if not exists authors (
  id            uuid primary key default uuid_generate_v4(),
  douyin_uid    text unique not null,   -- 抖音用户 uid（数字 ID）
  sec_uid       text,                   -- 抖音 sec_uid（用于获取视频列表）
  name          text not null,          -- 博主昵称
  avatar_url    text,                   -- 博主头像 URL
  created_at    timestamptz default now()
);

-- 索引：按 douyin_uid 快速查找
create index if not exists idx_authors_douyin_uid on authors(douyin_uid);


-- ─────────────────────────────────────────
-- 2. 店铺表
-- 存储餐厅/店铺的详细信息
-- ─────────────────────────────────────────
create table if not exists restaurants (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null,          -- 店铺名称
  address       text,                   -- 详细地址
  city          text,                   -- 所在城市
  latitude      double precision,       -- 纬度
  longitude     double precision,       -- 经度
  amap_id       text unique,            -- 高德 POI ID（唯一标识，避免重复）
  category      text,                   -- 美食分类（火锅、烤肉等）
  created_at    timestamptz default now()
);

-- 索引：按城市查询（地图按城市筛选时用）
create index if not exists idx_restaurants_city on restaurants(city);
-- 索引：按坐标范围查询（地图附近搜索时用）
create index if not exists idx_restaurants_location on restaurants(latitude, longitude);


-- ─────────────────────────────────────────
-- 3. 博主-店铺关联表
-- 记录哪个博主推荐了哪家店铺（多对多关系）
-- ─────────────────────────────────────────
create table if not exists author_restaurants (
  id              uuid primary key default uuid_generate_v4(),
  author_id       uuid not null references authors(id) on delete cascade,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  video_id        text,                 -- 来源视频 ID（可追溯）
  created_at      timestamptz default now(),
  unique(author_id, restaurant_id)      -- 同一博主不重复关联同一店铺
);

create index if not exists idx_author_restaurants_author on author_restaurants(author_id);
create index if not exists idx_author_restaurants_restaurant on author_restaurants(restaurant_id);


-- ─────────────────────────────────────────
-- 4. 用户关注博主表
-- 记录用户关注了哪些博主
-- ─────────────────────────────────────────
create table if not exists user_follows (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null,          -- Supabase Auth 用户 ID
  author_id     uuid not null references authors(id) on delete cascade,
  created_at    timestamptz default now(),
  unique(user_id, author_id)
);

create index if not exists idx_user_follows_user on user_follows(user_id);


-- ─────────────────────────────────────────
-- 5. 用户收藏店铺表
-- 记录用户收藏了哪些店铺
-- ─────────────────────────────────────────
create table if not exists user_favorites (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  created_at      timestamptz default now(),
  unique(user_id, restaurant_id)
);

create index if not exists idx_user_favorites_user on user_favorites(user_id);


-- ─────────────────────────────────────────
-- 6. 解析记录表
-- 记录哪些博主已经解析过，避免重复调用 AI
-- ─────────────────────────────────────────
create table if not exists parse_records (
  id            uuid primary key default uuid_generate_v4(),
  author_id     uuid unique not null references authors(id) on delete cascade,
  video_count   int default 0,          -- 解析的视频数量
  parsed_at     timestamptz default now()
);


-- ─────────────────────────────────────────
-- Row Level Security (RLS) 策略
-- 保护数据安全：用户只能读写自己的数据
-- ─────────────────────────────────────────

-- 开启 RLS
alter table user_follows enable row level security;
alter table user_favorites enable row level security;

-- user_follows：用户只能操作自己的关注记录
create policy "用户只能查看自己的关注" on user_follows
  for select using (auth.uid() = user_id);

create policy "用户只能添加自己的关注" on user_follows
  for insert with check (auth.uid() = user_id);

create policy "用户只能删除自己的关注" on user_follows
  for delete using (auth.uid() = user_id);

-- user_favorites：用户只能操作自己的收藏记录
create policy "用户只能查看自己的收藏" on user_favorites
  for select using (auth.uid() = user_id);

create policy "用户只能添加自己的收藏" on user_favorites
  for insert with check (auth.uid() = user_id);

create policy "用户只能删除自己的收藏" on user_favorites
  for delete using (auth.uid() = user_id);

-- authors、restaurants、author_restaurants 对所有人可读（公开数据）
alter table authors enable row level security;
alter table restaurants enable row level security;
alter table author_restaurants enable row level security;

create policy "博主信息公开可读" on authors for select using (true);
create policy "店铺信息公开可读" on restaurants for select using (true);
create policy "博主店铺关联公开可读" on author_restaurants for select using (true);
