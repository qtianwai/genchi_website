# AI 美食决策助手（饭团）— 实施计划

> 对应产品功能清单：「AI 美食决策助手」
> 目标：通过卡通形象"饭团"承载 AI 能力，以游戏化抽卡 + 智能问答帮用户解决"今天吃什么"的选择困难

---

## 一、功能概述

### 核心概念
- 一个叫"饭团"的卡通形象常驻地图页右下角，作为 AI 能力载体
- 饭团有微动画和表情状态，饭点时冒泡引导用户互动
- 第一期能力："帮你选吃什么"（到店就餐场景）
- 外卖场景后续迭代（美团/饿了么无 C 端搜索 API）

### 两种推荐模式
- **干饭抽卡**：6 张卡背面朝上 → 用户选 1 张翻开 → 其余 5 张被饭团吃掉 → 展示抽中卡详情
- **智能问答**：AI 生成 3-5 个动态问题 → 用户回答 → 推荐结果列表展示

### 游戏化体系
- 四档卡片稀有度：普通 / 优质 / 稀有 / 限定
- 限定卡触发条件：天气（雨天→火锅）、时段（深夜→烧烤）、下午茶
- 成就系统：15 个预设成就，和抽卡/打卡联动
- 每日抽卡 15 次限制（环境变量可配置）
- 连续换一批 3 次后插入提问收窄范围

---

## 二、改动范围总览

| 层 | 文件 | 改动类型 |
|----|------|---------|
| 数据库 | `backend/supabase_schema.sql` | 新增 6 张表 + 成就初始数据 |
| 数据库 | `backend/migrations/v8.0_gacha_system.sql` | 迁移脚本（需在 Supabase Dashboard 执行） |
| 后端 | `backend/db.py` | 新增 ~25 个数据库操作函数 |
| 后端 | `backend/main.py` | 新增 12 个 API 端点 + 请求模型 + AI 推荐核心逻辑 |
| 后端 | `backend/weather_service.py` | 新建：和风天气 API 接入（30 分钟缓存） |
| 后端 | `backend/amap_service.py` | 新增 `search_nearby_restaurants` 周边搜索 |
| 后端 | `backend/.env` | 新增天气 API Key 和抽卡配置环境变量 |
| iOS | `Models/Models.swift` | 新增 ~15 个数据模型 |
| iOS | `Services/APIService.swift` | 新增 ~15 个 API 调用方法 |
| iOS | `ViewModels/FanTuanViewModel.swift` | 新建：饭团状态管理 |
| iOS | `ViewModels/GachaViewModel.swift` | 新建：抽卡流程管理 |
| iOS | `ViewModels/QARecommendViewModel.swift` | 新建：问答推荐流程管理 |
| iOS | `Views/FanTuanView.swift` | 新建：饭团浮动组件 + 能力菜单 |
| iOS | `Views/GachaView.swift` | 新建：抽卡主页面（翻牌/吃卡动画） |
| iOS | `Views/QARecommendView.swift` | 新建：问答推荐页面 |
| iOS | `Views/CheckinSheet.swift` | 新建：打卡弹窗（评分+评价+照片） |
| iOS | `Views/AchievementsView.swift` | 新建：成就列表页 |
| iOS | `Views/MapView.swift` | 集成饭团组件到地图右下角 |
| iOS | `Views/ProfileView.swift` | 新增成就入口 |

---

## 三、数据库新增表（6 张）

| 表名 | 用途 |
|------|------|
| `user_checkins` | 用户打卡记录（评分/评价/照片） |
| `gacha_records` | 抽卡记录（6 张卡片/稀有度/用户选择） |
| `achievements` | 成就定义（15 个预设成就） |
| `user_achievements` | 用户已解锁成就 |
| `user_behavior_logs` | 用户行为日志（用于 AI 偏好分析） |
| `daily_gacha_counts` | 每日抽卡次数统计 |

---

## 四、后端 API 端点（12 个）

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/weather` | GET | 获取天气（代理和风天气，30 分钟缓存） |
| `/api/gacha/remaining` | GET | 查询今日剩余抽卡次数 |
| `/api/gacha/draw` | POST | 执行抽卡（AI 推荐 6 张卡片） |
| `/api/gacha/select` | POST | 用户选中卡片 + 成就检测 |
| `/api/recommend/questions` | POST | 问答模式：AI 生成动态问题 |
| `/api/recommend/result` | POST | 问答模式：基于回答生成推荐 |
| `/api/checkins` | POST | 创建打卡 + 成就检测 |
| `/api/checkins/restaurant/{id}` | GET | 获取店铺打卡记录 |
| `/api/checkins/user` | GET | 获取用户打卡历史 |
| `/api/achievements` | GET | 获取所有成就定义 |
| `/api/achievements/user` | GET | 获取用户已解锁成就 |
| `/api/behavior/log` | POST | 记录用户行为日志 |
| `/api/restaurants/{id}/reviews-summary` | GET | 收藏留言 AI 摘要 |

---

## 五、AI 推荐核心逻辑

### 推荐池构建
1. 用户已有店铺（达人推荐 + 自建 + 订阅），排除已打卡的
2. 平台热门池（全平台收藏最多的店铺）补充
3. 高德 POI 周边搜索（附近 3km 餐饮）兜底

### 稀有度判定
- **限定卡**：天气+品类匹配（雨天火锅/深夜烧烤/下午茶甜品）
- **稀有卡**：平台收藏数 ≥ 5
- **优质卡**：被 ≥ 3 个达人推荐 或 有人均价格数据
- **普通卡**：默认，另有 3% 概率随机出稀有、12% 概率出优质

### 大模型调用
- 模型：qwen-plus（通义千问）
- 抽卡模式：1 次调用（生成 6 家推荐 + 推荐理由）
- 问答模式：2 次调用（生成问题 + 生成推荐）
- 成本：约 ¥0.01/次，每日 15 次上限

---

## 六、关键技术决策

| 决策项 | 选择 | 原因 |
|--------|------|------|
| 就餐场景 | 仅到店（第一版） | 美团/饿了么无 C 端搜索 API |
| 外部数据源 | 高德 POI | 已有集成，零接入成本 |
| AI 推理 | qwen-plus 实时推理 | 已有集成，成本可控 |
| 卡通形象 | Emoji + SF Symbol（MVP） | 无设计师，后续替换 AI 生成形象 |
| 天气 API | 和风天气免费版 | 每日 1000 次，后端缓存 30 分钟 |
| 稀有度 | 四档，纯随机无保底 | 更有抽卡刺激感 |
| 分享功能 | 后续迭代 | 降低第一版复杂度 |

---

## 七、环境变量配置

```env
# 和风天气 API Key（需注册 https://dev.qweather.com）
QWEATHER_API_KEY=YOUR_KEY
QWEATHER_BASE_URL=https://devapi.qweather.com

# 抽卡配置
DAILY_GACHA_LIMIT=15
GACHA_INSERT_QA_THRESHOLD=3
```

---

## 八、部署前必做

1. 在 Supabase Dashboard SQL Editor 执行 `backend/migrations/v8.0_gacha_system.sql`
2. 注册和风天气开发者账号，获取 API Key，配置到 `.env` 和 Railway 环境变量
3. Railway 环境变量新增：`QWEATHER_API_KEY`、`DAILY_GACHA_LIMIT`
4. 将新增的 iOS 文件添加到 Xcode 项目中

---

## 九、验证清单

- [ ] 数据库 6 张表创建成功
- [ ] 天气 API 返回正确数据
- [ ] 抽卡流程：点击饭团 → 菜单 → 抽卡 → 6 张卡 → 选 1 张 → 吃卡动画 → 结果详情
- [ ] 问答流程：菜单 → 问答 → 3-5 题 → 推荐列表
- [ ] 打卡流程：结果页打卡 → 评分/评价 → 提交成功
- [ ] 成就解锁：抽卡/打卡后触发成就检测，Toast 提示
- [ ] 每日次数限制：超过 15 次返回 429
- [ ] 连续换一批 3 次后插入提问
- [ ] 饭点冒泡引导：11-13 点打开 APP 看到冒泡文案
- [ ] 个人主页成就列表正确展示
