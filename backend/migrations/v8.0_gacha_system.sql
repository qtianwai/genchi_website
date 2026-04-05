-- =====================================================
-- v8.0 迁移脚本：AI 美食决策助手（饭团）
-- 在 Supabase Dashboard SQL Editor 中执行此文件
-- =====================================================

-- 18. 用户打卡记录表
create table if not exists user_checkins (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  rating          integer,
  comment         text,
  photo_urls      text[],
  created_at      timestamptz default now()
);

create index if not exists idx_checkins_user on user_checkins(user_id);
create index if not exists idx_checkins_restaurant on user_checkins(restaurant_id);
create index if not exists idx_checkins_user_time on user_checkins(user_id, created_at desc);

alter table user_checkins enable row level security;
create policy "用户只能操作自己的打卡" on user_checkins
  for all using (auth.uid() = user_id);
create policy "打卡记录公开可读" on user_checkins
  for select using (true);


-- 19. 抽卡记录表
create table if not exists gacha_records (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  restaurant_id   uuid not null references restaurants(id) on delete cascade,
  rarity          text not null,
  is_selected     boolean default false,
  session_id      uuid not null,
  trigger_type    text not null default 'gacha',
  recommend_reason text,
  created_at      timestamptz default now()
);

create index if not exists idx_gacha_user on gacha_records(user_id);
create index if not exists idx_gacha_user_date on gacha_records(user_id, created_at desc);
create index if not exists idx_gacha_session on gacha_records(session_id);

alter table gacha_records enable row level security;
create policy "用户只能操作自己的抽卡记录" on gacha_records
  for all using (auth.uid() = user_id);


-- 20. 成就定义表
create table if not exists achievements (
  id              text primary key,
  name            text not null,
  description     text not null,
  icon_name       text,
  category        text not null,
  condition_type  text not null,
  condition_value integer not null,
  created_at      timestamptz default now()
);

alter table achievements enable row level security;
create policy "成就定义公开可读" on achievements
  for select using (true);


-- 21. 用户已解锁成就表
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


-- 22. 用户行为日志表
create table if not exists user_behavior_logs (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  action          text not null,
  target_type     text,
  target_id       uuid,
  metadata        jsonb,
  created_at      timestamptz default now()
);

create index if not exists idx_behavior_user_time on user_behavior_logs(user_id, created_at desc);
create index if not exists idx_behavior_action on user_behavior_logs(action);

alter table user_behavior_logs enable row level security;
create policy "用户只能操作自己的行为日志" on user_behavior_logs
  for all using (auth.uid() = user_id);


-- 23. 每日抽卡次数统计表
create table if not exists daily_gacha_counts (
  user_id         uuid not null,
  date            date not null default current_date,
  count           integer not null default 0,
  primary key (user_id, date)
);

alter table daily_gacha_counts enable row level security;
create policy "用户只能操作自己的抽卡计数" on daily_gacha_counts
  for all using (auth.uid() = user_id);


-- 初始成就数据
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
