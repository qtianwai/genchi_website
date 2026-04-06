-- v15.0 用户反馈系统
-- user_feedback: 用户提交的反馈（Bug报告/功能建议/其他）
-- user_feedback_replies: 管理员回复

-- 22. 用户反馈表
create table if not exists user_feedback (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid not null,
  category        text not null,                     -- bug_report / feature_request / other
  content         text not null,
  image_urls      text[],                            -- 截图 URL 数组（最多3张）
  device_model    text,                              -- 设备型号，如 "iPhone16,1"
  ios_version     text,                              -- iOS 版本，如 "17.4"
  app_version     text,                              -- App 版本号，如 "1.0.0 (42)"
  status          text not null default 'pending',   -- pending / in_progress / resolved
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create index if not exists idx_feedback_user on user_feedback(user_id);
create index if not exists idx_feedback_status on user_feedback(status);
create index if not exists idx_feedback_created on user_feedback(created_at desc);

-- 23. 用户反馈回复表
create table if not exists user_feedback_replies (
  id              uuid primary key default uuid_generate_v4(),
  feedback_id     uuid not null references user_feedback(id) on delete cascade,
  admin_user_id   uuid not null,
  content         text not null,
  created_at      timestamptz default now()
);

create index if not exists idx_feedback_replies_fid on user_feedback_replies(feedback_id);
