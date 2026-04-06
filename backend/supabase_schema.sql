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
  signature     text,                   -- 账号简介（v7.0 新增）
  video_count   int,                   -- 发布视频数（来自 aweme_count，v7.0 新增）
  total_likes   bigint,                -- 获赞数（来自 total_favorited，v7.0 新增）
  -- 自动更新检测相关字段（v2.4 新增）
  auto_update_enabled    boolean default true,  -- 是否启用自动更新检测
  last_update_check      timestamptz,          -- 上次执行自动检测的时间
  no_new_food_video_days int default 0,         -- 连续未检测到新美食视频的天数
  -- v13.0 新增：美食视频统计（用于自动更新检测的博主筛选）
  food_video_ratio       float default 0,       -- 美食视频占比（0~1），上次后台解析时计算
  food_video_count       int default 0,         -- 平台关联的美食视频数量（status=completed 的记录数）
  last_food_video_at     timestamptz,           -- 最近一条美食视频的发布时间
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
  -- v3.0 新增：人工验证字段
  verified      boolean not null default false,  -- 是否经过人工复核验证
  verified_at   timestamptz,            -- 人工验证时间
  -- v5.0 新增：高德扩展信息
  avg_price     integer,                -- 人均消费（元），来自高德 biz_ext.avgprice
  photo_url     text,                   -- 店铺封面图 URL，来自高德 photos[0].url
  tel           text,                   -- 商家联系电话，来自高德 tel 字段
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
  unique(author_id, restaurant_id, video_id)  -- 同一博主-店铺-视频组合唯一
);

create index if not exists idx_author_restaurants_author on author_restaurants(author_id);
create index if not exists idx_author_restaurants_restaurant on author_restaurants(restaurant_id);
create index if not exists idx_author_restaurants_video on author_restaurants(video_id);


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
  note            text,                    -- 收藏理由（v5.0 新增）
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
-- 7. 视频地址缓存表（解决重复解析同一视频的问题）
-- 记录每个视频链接对应的解析结果（店铺+坐标）
-- 一个视频地址对应一条记录，URL 完全一致才命中缓存
-- ─────────────────────────────────────────
create table if not exists video_parse_cache (
  id              uuid primary key default uuid_generate_v4(),
  video_url       text not null,        -- 用户提交的原始抖音分享链接（精确匹配）
  video_id        text,                 -- 抖音视频 ID
  author_id       uuid references authors(id) on delete cascade,
  restaurant_id   uuid references restaurants(id) on delete set null,
  status          text not null default 'pending',  -- pending/parsing/completed/failed/cold_start（v14.0 新增 cold_start：冷启动录入，未经解析）
  -- 解析结果快照（直接从 video_parse_cache 返回，避免联表查询）
  restaurant_name    text,
  restaurant_address text,
  restaurant_city    text,
  restaurant_lat     double precision,
  restaurant_lng     double precision,
  restaurant_amap_id text,
  restaurant_category text,
  restaurant_avg_price integer,         -- 店铺均价快照（复核模块直接读取）
  restaurant_photo_url text,            -- 店铺封面图快照（复核模块直接读取）
  error_message   text,                 -- 解析失败时的错误信息
  -- v2.5 新增字段
  parse_reason    text,                 -- 解析说明：AI 判断依据（包括未提取到店名的原因）
  data_source     text not null default 'user_submit',  -- 数据来源：user_submit/background_scan/auto_check/manual_add/cold_start（v14.0 新增）
  api_cost        numeric(10,6),        -- 本条数据消耗的 JustOneAPI 成本（单位：元）
  api_cost_note   text,                 -- API 成本说明（如：调用了哪些接口、各自消耗多少）
  -- v7.0 新增：视频扩展信息（JSON）
  video_extra     jsonb,                -- 视频扩展信息，包含标题/城市/时间/互动数据/封面图/标签等
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  -- v3.0 新增：人工复核字段
  review_status   text not null default 'pending',  -- pending/approved/corrected/confirmed/skipped
  reviewed_by     uuid,                -- 复核操作人（管理员 user_id）
  reviewed_at     timestamptz,         -- 复核时间
  -- v9.0 新增：多店铺修正记录（JSON 数组）
  corrected_restaurants jsonb,           -- [{restaurant_id, amap_id, name, address, city, lat, lng, category}]
  -- v11.0 新增：解析算法版本号（用于判断 failed 记录是否值得重试）
  parse_algorithm_version text           -- 如 "v11.0"，每次优化 AI prompt/规则/搜索策略时递增
);

-- 索引：按视频 URL 精确查询（唯一索引保证每个 URL 只有一条记录）
create unique index if not exists idx_video_cache_url on video_parse_cache(video_url);
-- 索引：按视频 ID 查询（用于去重判断）
create index if not exists idx_video_cache_videoid on video_parse_cache(video_id);
-- 索引：按复核状态查询（v3.0 新增，用于复核列表查询）
create index if not exists idx_vpc_review_status on video_parse_cache(review_status);
-- 索引：按 video_extra JSON 字段内容查询（v7.0 新增，用于按标签/话题筛选）
create index if not exists idx_video_cache_video_extra on video_parse_cache using gin (video_extra);


-- ─────────────────────────────────────────
-- 9. 管理员用户表（v3.0 新增）
-- 记录平台管理员账号，用于后台人工复核功能鉴权
-- ─────────────────────────────────────────
create table if not exists admin_users (
  user_id    uuid primary key,          -- 对应 auth 的 user_id
  note       text,                      -- 备注（如：谁的账号）
  created_at timestamptz default now()
);

-- admin_users 不开放客户端访问，仅后端 Service Role Key 可操作
alter table admin_users enable row level security;
create policy "admin_users_no_client_access" on admin_users for all using (false);


-- ─────────────────────────────────────────
-- 8. 博主后台解析任务表
-- 记录博主历史探店视频的后台异步解析任务
-- 用户新提交链接时，立即解析当前视频；其他历史视频在后台逐步解析
-- ─────────────────────────────────────────
create table if not exists author_background_tasks (
  id              uuid primary key default uuid_generate_v4(),
  author_id       uuid not null references authors(id) on delete cascade,
  task_type       text not null,        -- 'full_scan': 首次入库的全量扫描; 'incremental': 增量更新; 'auto_check': 自动更新检测; 'cold_start': 冷启动博主录入（v14.0 新增）
  total_videos    int default 0,        -- 该任务需要处理的总视频数
  processed_videos int default 0,        -- 已处理完成的视频数
  status          text not null default 'pending',  -- pending/running/completed/failed
  new_restaurants_found int default 0,  -- 本次任务发现的新店铺数
  error_message   text,
  started_at      timestamptz,
  completed_at   timestamptz,
  -- v13.0 新增：任务成本记录
  api_cost        numeric(10,6) default 0,  -- 本次任务消耗的 JustOneAPI 总成本（元）
  api_cost_note   text default '',           -- 成本明细说明
  created_at      timestamptz default now()
);

-- 索引：按博主 ID 查最新任务状态
create index if not exists idx_bg_tasks_author on author_background_tasks(author_id);
create index if not exists idx_bg_tasks_status on author_background_tasks(status);

-- 索引：按自动更新字段查询（v2.4 新增，用于定时任务）
create index if not exists idx_authors_auto_update on authors(auto_update_enabled) where auto_update_enabled = true;


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

-- authors 表允许更新（后端需要更新 auto_update_enabled 等字段）
create policy "博主信息可更新" on authors for update using (true) with check (true);


-- ─────────────────────────────────────────
-- v2.4 迁移脚本：新增博主自动更新检测字段
-- 如果 authors 表已存在，执行以下 ALTER 语句添加新字段
-- ─────────────────────────────────────────
-- ALTER TABLE authors ADD COLUMN IF NOT EXISTS auto_update_enabled boolean DEFAULT true;
-- ALTER TABLE authors ADD COLUMN IF NOT EXISTS last_update_check timestamptz;
-- ALTER TABLE authors ADD COLUMN IF NOT EXISTS no_new_food_video_days int DEFAULT 0;
-- CREATE INDEX IF NOT EXISTS idx_authors_auto_update ON authors(auto_update_enabled) WHERE auto_update_enabled = true;


-- ─────────────────────────────────────────
-- v2.5 迁移脚本：新增解析说明、数据来源、API 成本字段
-- 如果 video_parse_cache 表已存在，执行以下 ALTER 语句添加新字段
-- ─────────────────────────────────────────
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS parse_reason text;
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS data_source text NOT NULL DEFAULT 'user_submit';
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS api_cost numeric(10,6);
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS api_cost_note text;
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS restaurant_avg_price integer;
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS restaurant_photo_url text;


-- ─────────────────────────────────────────
-- 10. 用户自建推荐店铺表（v4.0 新增）
-- 记录用户手动添加的推荐店铺（不依赖博主/视频）
-- ─────────────────────────────────────────
create table if not exists user_created_restaurants (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,           -- 创建者（Supabase Auth user_id）
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  note            text,                    -- 用户备注（预留）
  created_at      timestamptz default now(),
  unique(user_id, restaurant_id)           -- 同一用户不能重复添加同一家店
);

create index if not exists idx_ucr_user on user_created_restaurants(user_id);
create index if not exists idx_ucr_restaurant on user_created_restaurants(restaurant_id);

-- RLS：用户只能操作自己的记录
alter table user_created_restaurants enable row level security;

create policy "用户只能查看自己的自建推荐" on user_created_restaurants
  for select using (auth.uid() = user_id);
create policy "用户只能添加自己的自建推荐" on user_created_restaurants
  for insert with check (auth.uid() = user_id);
create policy "用户只能删除自己的自建推荐" on user_created_restaurants
  for delete using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- v3.0 迁移脚本：后台人工复核功能（已实施，字段已合并至上方表定义）
-- 若在已有数据库上增量执行，运行以下 ALTER 语句：
-- ─────────────────────────────────────────

-- 1. 新增管理员用户表（已合并至第 9 节）
-- CREATE TABLE IF NOT EXISTS admin_users (
--     user_id    uuid PRIMARY KEY,
--     note       text,
--     created_at timestamptz DEFAULT now()
-- );
-- ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY admin_users_no_client_access ON admin_users FOR ALL USING (false);

-- 2. video_parse_cache 新增复核字段（已合并至第 7 节）
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'pending';
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS reviewed_by uuid;
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;
-- CREATE INDEX IF NOT EXISTS idx_vpc_review_status ON video_parse_cache(review_status);

-- 3. restaurants 新增人工验证字段（已合并至第 2 节）
-- ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS verified boolean NOT NULL DEFAULT false;
-- ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS verified_at timestamptz;


-- ─────────────────────────────────────────
-- 11. 用户 Profile 表（v5.0 新增）
-- 存储用户自定义昵称和头像 URL
-- ─────────────────────────────────────────
create table if not exists user_profiles (
  user_id     uuid primary key,                        -- 对应 phone_to_user_id 生成的 UUID
  nickname    text not null default '美食探索者',       -- 用户昵称，默认"美食探索者"
  avatar_url  text,                                    -- 头像公开 URL（Supabase Storage avatars bucket），null 表示未上传
  updated_at  timestamptz default now()
);

-- RLS：profile 公开可读（地图标注异步加载头像需要），写操作走后端 service_role key 绕过 RLS
alter table user_profiles enable row level security;

create policy "profile 公开可读" on user_profiles
  for select using (true);
create policy "用户只能修改自己的 profile" on user_profiles
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 12. 用户避雷店铺表（v5.0 新增）
-- 前端文案统一用"避雷"，表名保留 blocked 兼容
-- ─────────────────────────────────────────
create table if not exists user_blocked_restaurants (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  created_at      timestamptz default now(),
  unique(user_id, restaurant_id)
);

create index if not exists idx_ubr_user on user_blocked_restaurants(user_id);

alter table user_blocked_restaurants enable row level security;
create policy "用户只能操作自己的避雷记录" on user_blocked_restaurants
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 13. 用户删除店铺表（v5.0 新增，全局隐藏）
-- 用户删除后该店铺不再出现在地图和列表中，不影响其他用户
-- ─────────────────────────────────────────
create table if not exists user_deleted_restaurants (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  created_at      timestamptz default now(),
  unique(user_id, restaurant_id)
);

create index if not exists idx_udr_user on user_deleted_restaurants(user_id);

alter table user_deleted_restaurants enable row level security;
create policy "用户只能操作自己的删除记录" on user_deleted_restaurants
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 14. 用户自定义分组表（v5.0 新增）
-- ─────────────────────────────────────────
create table if not exists user_restaurant_groups (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null,
  name        text not null,
  created_at  timestamptz default now(),
  unique(user_id, name)
);

create index if not exists idx_urg_user on user_restaurant_groups(user_id);

alter table user_restaurant_groups enable row level security;
create policy "用户只能操作自己的分组" on user_restaurant_groups
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 15. 分组-店铺关联表（v5.0 新增）
-- ─────────────────────────────────────────
create table if not exists user_group_restaurants (
  id              uuid primary key default uuid_generate_v4(),
  group_id        uuid not null references user_restaurant_groups(id) on delete cascade,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  user_id         uuid not null,
  created_at      timestamptz default now(),
  unique(group_id, restaurant_id)
);

create index if not exists idx_ugr_group on user_group_restaurants(group_id);

alter table user_group_restaurants enable row level security;
create policy "用户只能操作自己的分组店铺" on user_group_restaurants
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- v5.0 迁移脚本：user_favorites 新增收藏理由字段
-- 若在已有数据库上增量执行，运行以下 ALTER 语句：
-- ─────────────────────────────────────────
-- ALTER TABLE user_favorites ADD COLUMN IF NOT EXISTS note text;


-- ─────────────────────────────────────────
-- v7.0 迁移脚本：新增博主扩展字段和视频扩展字段
-- 若在已有数据库上增量执行，运行以下 ALTER 语句：
-- ─────────────────────────────────────────

-- authors 表新增字段
-- ALTER TABLE authors ADD COLUMN IF NOT EXISTS signature TEXT;
-- ALTER TABLE authors ADD COLUMN IF NOT EXISTS video_count INT;
-- ALTER TABLE authors ADD COLUMN IF NOT EXISTS total_likes BIGINT;

-- video_parse_cache 表新增字段
-- ALTER TABLE video_parse_cache ADD COLUMN IF NOT EXISTS video_extra JSONB;

-- JSONB 字段索引（用于按视频标签、话题等查询）
-- CREATE INDEX IF NOT EXISTS idx_video_cache_video_extra ON video_parse_cache USING GIN (video_extra);

-- ─────────────────────────────────────────
-- 17. 用户地图表（v6.0 新增）
-- 控制用户地图的公开/私密状态
-- ─────────────────────────────────────────
create table if not exists user_maps (
  user_id    uuid primary key,
  is_public  boolean not null default true,
  updated_at timestamptz default now()
);

-- 为现有用户初始化地图记录（默认公开）
insert into user_maps (user_id, is_public)
select user_id, true from user_profiles
on conflict (user_id) do nothing;

alter table user_maps enable row level security;

-- 公开地图任何人可读
create policy "公开地图可读" on user_maps
  for select using (is_public = true or auth.uid() = user_id);

-- 用户只能修改自己的地图设置
create policy "用户只能修改自己的地图设置" on user_maps
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 17. 用户地图订阅表（v6.0 新增）
-- 记录用户订阅其他用户的地图
-- ─────────────────────────────────────────
create table if not exists user_map_subscriptions (
  id              uuid primary key default uuid_generate_v4(),
  subscriber_id   uuid not null,
  target_user_id  uuid not null,
  is_enabled      boolean not null default true,
  created_at      timestamptz default now(),
  unique(subscriber_id, target_user_id)
);

create index if not exists idx_ums_subscriber on user_map_subscriptions(subscriber_id);
create index if not exists idx_ums_target     on user_map_subscriptions(target_user_id);

alter table user_map_subscriptions enable row level security;

-- 用户只能操作自己的订阅
create policy "用户只能操作自己的订阅" on user_map_subscriptions
  for all using (auth.uid() = subscriber_id);


-- =====================================================
-- v8.0 新增：AI 美食决策助手（饭团）相关表
-- =====================================================


-- ─────────────────────────────────────────
-- 18. 用户打卡记录表（v8.0 新增）
-- 记录用户去过哪些店铺，含评价和照片
-- ─────────────────────────────────────────
create table if not exists user_checkins (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  rating          integer,                    -- 评分 1-5（可选）
  comment         text,                       -- 评价文字（可选）
  photo_urls      text[],                     -- 照片 URL 数组（可选）
  created_at      timestamptz default now()
);

create index if not exists idx_checkins_user on user_checkins(user_id);
create index if not exists idx_checkins_restaurant on user_checkins(restaurant_id);
create index if not exists idx_checkins_user_time on user_checkins(user_id, created_at desc);

alter table user_checkins enable row level security;
create policy "用户只能操作自己的打卡" on user_checkins
  for all using (auth.uid() = user_id);
-- 打卡记录公开可读（其他用户可以看到某店铺的打卡）
create policy "打卡记录公开可读" on user_checkins
  for select using (true);


-- ─────────────────────────────────────────
-- 19. 抽卡记录表（v8.0 新增）
-- 记录每次抽卡的 6 张卡片和用户选择
-- ─────────────────────────────────────────
create table if not exists gacha_records (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  rarity          text not null,              -- 稀有度：normal / quality / rare / limited
  is_selected     boolean default false,      -- 是否为用户抽中的那张
  session_id      uuid not null,              -- 同一次抽卡的 6 张共享 session_id
  trigger_type    text not null default 'gacha',  -- 来源：gacha（抽卡）/ qa（问答推荐）
  recommend_reason text,                      -- AI 生成的推荐理由
  created_at      timestamptz default now()
);

create index if not exists idx_gacha_user on gacha_records(user_id);
create index if not exists idx_gacha_user_date on gacha_records(user_id, created_at desc);
create index if not exists idx_gacha_session on gacha_records(session_id);

alter table gacha_records enable row level security;
create policy "用户只能操作自己的抽卡记录" on gacha_records
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 20. 成就定义表（v8.0 新增）
-- 存储所有成就的定义和达成条件
-- ─────────────────────────────────────────
create table if not exists achievements (
  id              text primary key,           -- 如 'food_hunter_10', 'daily_streak_7'
  name            text not null,              -- 成就名称
  description     text not null,              -- 成就描述
  icon_name       text,                       -- SF Symbol 图标名（iOS 端用）
  category        text not null,              -- collection / streak / limited
  condition_type  text not null,              -- rare_count / daily_streak / limited_card / checkin_count / total_gacha
  condition_value integer not null,           -- 达成条件数值
  created_at      timestamptz default now()
);

-- 成就定义公开可读
alter table achievements enable row level security;
create policy "成就定义公开可读" on achievements
  for select using (true);


-- ─────────────────────────────────────────
-- 21. 用户已解锁成就表（v8.0 新增）
-- ─────────────────────────────────────────
create table if not exists user_achievements (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  achievement_id  text not null references achievements(id) on delete cascade,
  unlocked_at     timestamptz default now(),
  unique(user_id, achievement_id)
);

create index if not exists idx_user_achievements_user on user_achievements(user_id);

alter table user_achievements enable row level security;
create policy "用户成就公开可读" on user_achievements
  for select using (true);
create policy "用户只能操作自己的成就" on user_achievements
  for insert with check (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 22. 用户行为日志表（v8.0 新增）
-- 记录用户关键行为，用于 AI 推荐的偏好分析
-- ─────────────────────────────────────────
create table if not exists user_behavior_logs (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  action          text not null,              -- view / favorite / checkin / gacha / navigate / unfavorite
  target_type     text,                       -- restaurant / author / card
  target_id       uuid,                       -- 目标对象 ID
  metadata        jsonb,                      -- 额外信息（品类、价位、稀有度等）
  created_at      timestamptz default now()
);

create index if not exists idx_behavior_user_time on user_behavior_logs(user_id, created_at desc);
create index if not exists idx_behavior_action on user_behavior_logs(action);

alter table user_behavior_logs enable row level security;
create policy "用户只能操作自己的行为日志" on user_behavior_logs
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- 23. 每日抽卡次数统计表（v8.0 新增）
-- 记录每个用户每天的抽卡次数，用于限制每日上限
-- ─────────────────────────────────────────
create table if not exists daily_gacha_counts (
  user_id         uuid not null,
  date            date not null default current_date,
  count           integer not null default 0,
  primary key (user_id, date)
);

alter table daily_gacha_counts enable row level security;
create policy "用户只能操作自己的抽卡计数" on daily_gacha_counts
  for all using (auth.uid() = user_id);


-- ─────────────────────────────────────────
-- v8.0 初始成就数据
-- ─────────────────────────────────────────
insert into achievements (id, name, description, icon_name, category, condition_type, condition_value) values
  ('first_gacha',       '初次抽卡',     '完成第一次美食抽卡',                'sparkles',          'collection', 'total_gacha',   1),
  ('gacha_10',          '抽卡新手',     '累计完成 10 次抽卡',               'star',              'collection', 'total_gacha',   10),
  ('gacha_50',          '抽卡达人',     '累计完成 50 次抽卡',               'star.fill',         'collection', 'total_gacha',   50),
  ('gacha_100',         '抽卡大师',     '累计完成 100 次抽卡',              'crown',             'collection', 'total_gacha',   100),
  ('rare_1',            '稀有发现',     '抽到第 1 张稀有卡',                'bolt.fill',         'collection', 'rare_count',    1),
  ('rare_5',            '稀有猎人',     '累计抽到 5 张稀有卡',              'bolt.circle.fill',  'collection', 'rare_count',    5),
  ('rare_10',           '美食猎人',     '累计抽到 10 张稀有卡',             'trophy',            'collection', 'rare_count',    10),
  ('limited_1',         '限定收藏家',   '抽到第 1 张限定卡',                'sparkle',           'limited',    'limited_card',  1),
  ('limited_3',         '限定达人',     '累计抽到 3 张限定卡',              'diamond',           'limited',    'limited_card',  3),
  ('daily_streak_3',    '三日连抽',     '连续 3 天使用抽卡',                'flame',             'streak',     'daily_streak',  3),
  ('daily_streak_7',    '干饭达人',     '连续 7 天使用抽卡',                'flame.fill',        'streak',     'daily_streak',  7),
  ('daily_streak_30',   '美食狂热者',   '连续 30 天使用抽卡',               'heart.circle.fill', 'streak',     'daily_streak',  30),
  ('checkin_1',         '首次打卡',     '完成第一次店铺打卡',               'mappin',            'collection', 'checkin_count', 1),
  ('checkin_10',        '美食探索者',   '累计打卡 10 家店铺',               'mappin.circle',     'collection', 'checkin_count', 10),
  ('checkin_50',        '美食版图家',   '累计打卡 50 家店铺',               'map.fill',          'collection', 'checkin_count', 50)
on conflict (id) do nothing;


-- ─────────────────────────────────────────
-- 21. 用户勘误表（v10.0 新增）
-- 用户反馈店铺信息错误，勘误后店铺重新进入复核队列
-- ─────────────────────────────────────────
create table if not exists user_corrections (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null,                          -- 提交勘误的用户
  restaurant_id     uuid references restaurants(id),        -- 被勘误的店铺（地图卡片勘误时有值）
  video_cache_id    uuid references video_parse_cache(id),  -- 关联的视频缓存记录（解析结果勘误时有值）
  correction_type   text not null,                          -- 勘误类型：wrong_restaurant / wrong_address / closed / duplicate / other
  correction_detail text,                                   -- 用户补充说明
  status            text not null default 'pending',        -- pending / reviewed / resolved
  reviewed_by       uuid,                                   -- 复核人
  reviewed_at       timestamptz,                            -- 复核时间
  review_note       text,                                   -- 复核备注
  created_at        timestamptz default now()
);

create index if not exists idx_user_corrections_status on user_corrections(status);
create index if not exists idx_user_corrections_restaurant on user_corrections(restaurant_id);
create index if not exists idx_user_corrections_video_cache on user_corrections(video_cache_id);

-- ─────────────────────────────────────────
-- v10.10 饭团养成体系
-- ─────────────────────────────────────────

create table if not exists fantuan_status (
    id                      uuid default gen_random_uuid() primary key,
    user_id                 uuid not null,
    satiety                 integer not null default 80,           -- 饱食度 0-100
    intimacy                integer not null default 0,            -- 亲密度 0-∞
    intimacy_level          integer not null default 1,            -- 亲密度等级 1-5
    consecutive_login_days  integer not null default 0,            -- 连续登录天数
    last_login_date         date,                                  -- 最后登录日期
    last_pet_date           date,                                  -- 最后摸摸日期
    created_at              timestamptz default now(),
    updated_at              timestamptz default now(),
    unique(user_id)
);

create index if not exists idx_fantuan_status_user on fantuan_status(user_id);
