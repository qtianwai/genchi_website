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
| iOS | `Views/LottieView.swift` | 新建：Lottie SwiftUI 封装组件（10.9） |
| iOS | `Views/FanTuanStatusView.swift` | 新建：饭团状态面板（10.10） |
| iOS | `Resources/Animations/*.json` | 新建：9 个 Lottie 动画文件（10.9） |
| 数据库 | `fantuan_status` 表 | 新增：饭团养成数据（10.10） |

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

---

## 十、头脑风暴已确认但尚未实现的功能（待后续迭代）

以下功能在产品头脑风暴中已确认方案，代码中已预留接口或 TODO，但第一版未完整实现：

> **已完成并移除的功能**（代码已实现，不再列入待办）：
> - ~~10.1 关联博主+探店视频~~ → 后端返回博主信息，前端展示博主头像+视频列表弹窗
> - ~~10.2 收藏留言 AI 摘要~~ → GachaResultView 异步加载并展示
> - ~~10.5 个人主页成就徽章展示~~ → ProfileView 展示最近 4 个已解锁成就+进度
> - ~~10.8 抽卡导航功能接通~~ → onNavigate 传递完整 GachaCard，接通高德/百度/Apple 地图

### 10.3 饭点冒泡 — 精准预测文案
- **需求**：第一轮冒泡"是不是想吃 XXX 啦？"需基于用户最近偏好生成具体品类
- **当前状态**：FanTuanViewModel 冒泡文案为固定文本，未调用行为日志分析
- **待做**：
  - 饭团初始化时调用 `get_recent_user_behaviors` 获取最近收藏/打卡的品类
  - 提取高频品类填入冒泡文案（如"是不是想吃火锅啦？"）
  - 无行为数据时降级为通用文案

### 10.4 打卡照片上传
- **需求**：完整打卡支持上传照片
- **当前状态**：CheckinSheet UI 有照片选择器，但提交时标注 `// TODO: 照片上传到 Supabase Storage`，实际不上传
- **待做**：
  - 接入 Supabase Storage，上传照片获取公开 URL
  - 将 URL 数组传入 `createCheckin` 的 `photo_urls` 参数
  - 店铺打卡列表中展示照片缩略图

### 10.6 节日限定卡
- **需求**：春节年夜饭卡、中秋月饼卡等节日限定
- **当前状态**：`_determine_rarity` 只做了天气和时段限定，无节日判定
- **待做**：
  - 维护节日日期配置表（春节/元宵/中秋/圣诞等）
  - 节日当天 + 品类匹配 → 触发限定卡
  - 节日限定卡有专属视觉样式

### 10.7 场景选择（外卖 vs 到店）
- **需求**：用户点击饭团后先选择"外卖还是到店"
- **当前状态**：第一版只做到店，FanTuanMenuSheet 直接展示抽卡/问答，无场景选择
- **待做**（外卖场景上线时）：
  - FanTuanMenuSheet 顶部增加场景切换（到店/外卖）
  - 外卖场景：AI 推荐菜品方向 + URL Scheme 跳转美团/饿了么搜索页

### 10.9 饭团形象升级 — Lottie 动画 + Q版可爱风格（一阶段重点）

> **定位**：将饭团从 Emoji 占位符升级为有灵魂的 Q 版可爱角色，配合 Lottie 动画实现流畅的多状态表情和微交互，让用户觉得饭团是一个"活的"伙伴而非工具图标。

#### 10.9.1 饭团形象设计规范

**风格定义**：Q 版圆润可爱，类似角落生物/molly 风格
- 主体：白色饭团造型，圆滚滚的身体，顶部有一条海苔腰带
- 眼睛：大而圆的豆豆眼，黑色，略带高光，是表情变化的核心
- 嘴巴：简笔风格，不同状态下变化（微笑/张大/口水/睡觉气泡）
- 腮红：两团淡粉色圆形腮红，增加可爱感
- 四肢：短小的手脚（可选，也可以无四肢纯圆润造型）
- 配色：主体白色，海苔深绿，腮红粉色，整体色调温暖

**尺寸规格**：
- 地图浮动按钮：56×56pt（@2x 112px，@3x 168px）
- 抽卡页面饭团：120×120pt
- 吃卡动画饭团：80×80pt
- 冒泡旁饭团：同浮动按钮尺寸

#### 10.9.2 饭团状态与 Lottie 动画清单

需要制作以下 Lottie 动画文件（每个为独立 .json 文件）：

| 动画文件 | 状态 | 描述 | 循环 | 时长建议 |
|---------|------|------|------|---------|
| `fantuan_idle.json` | 默认/闲逛 | 轻微上下浮动 + 眨眼 | 循环 | 3s |
| `fantuan_hungry.json` | 饿了 | 眼睛变星星 + 流口水 + 肚子咕噜（身体微抖） | 循环 | 2.5s |
| `fantuan_sleepy.json` | 犯困 | 半闭眼 + 头一点一点 + 冒 Zzz 气泡 | 循环 | 3s |
| `fantuan_excited.json` | 兴奋 | 眼睛放光 + 蹦跳 + 周围冒小星星 | 循环 | 2s |
| `fantuan_rainy.json` | 下雨 | 头顶小伞/荷叶 + 缩成一团 + 微微发抖 | 循环 | 3s |
| `fantuan_eating.json` | 吃卡 | 张大嘴 → 咀嚼 → 满足地拍肚子 | 单次 | 1.5s |
| `fantuan_happy.json` | 开心（被摸后） | 眯眼笑 + 脸红加深 + 身体左右摇晃 | 单次 | 1.5s |
| `fantuan_starving.json` | 饿瘪（长期未登录） | 身体缩小变扁 + 眼睛变成 × + 冒虚汗 | 循环 | 3s |
| `fantuan_tap.json` | 点击反馈 | 弹跳 + 眨眼 + 问号冒泡 | 单次 | 0.8s |

#### 10.9.3 Lottie 素材制作流程

**推荐工作流**：AI 生成静态形象 → 手动/工具转 Lottie

1. **生成静态形象**（用户操作）
   - 使用 Midjourney / Stable Diffusion / DALL-E 生成饭团各状态的静态参考图
   - Prompt 参考：`cute kawaii onigiri character, chibi style, round body, big eyes, pink blush cheeks, nori belt, white background, simple flat design, sticker style, no outline`
   - 每个状态生成 2-3 张备选，选定后作为 Lottie 制作的参考

2. **转为 Lottie 动画**（以下方案任选其一）
   - **方案 A — LottieFiles Creator**（推荐，免费）：在 LottieFiles 网站用在线编辑器基于 SVG 制作简单动画
   - **方案 B — Figma + LottieFiles 插件**：在 Figma 中绘制 SVG 矢量图，用 LottieFiles Figma 插件导出
   - **方案 C — After Effects + Bodymovin**：专业方案，效果最好但学习成本高
   - **方案 D — Rive**（备选）：类似 Lottie 的交互动画工具，支持状态机，但需要额外 iOS SDK

3. **备选方案 — 现成素材改造**
   - 在 LottieFiles.com 搜索 `onigiri`、`rice ball`、`cute food character` 等关键词
   - 找到接近的素材后用 LottieFiles Editor 修改颜色和细节
   - 优点：速度最快；缺点：可能找不到完美匹配的

#### 10.9.4 iOS 端技术实现

**依赖引入**：
- `lottie-ios`（SPM）：Airbnb 开源的 Lottie 动画库，SwiftUI 原生支持

**文件组织**：
```
ios/FoodMap/genchi/genchi/
├── Resources/
│   └── Animations/           ← 新建：存放 Lottie JSON 文件
│       ├── fantuan_idle.json
│       ├── fantuan_hungry.json
│       ├── fantuan_sleepy.json
│       ├── fantuan_excited.json
│       ├── fantuan_rainy.json
│       ├── fantuan_eating.json
│       ├── fantuan_happy.json
│       ├── fantuan_starving.json
│       └── fantuan_tap.json
├── Views/
│   ├── FanTuanView.swift     ← 改造：Emoji → LottieView
│   └── GachaView.swift       ← 改造：卡片背面 Emoji → 饭团形象
└── ViewModels/
    └── FanTuanViewModel.swift ← 改造：状态枚举映射到动画文件名
```

**核心改动**：

1. **FanTuanView.swift**
   - 移除 Emoji Text("🍙")，替换为 `LottieView(name: viewModel.currentAnimationName)`
   - 状态切换时平滑过渡动画（crossfade）
   - 点击时播放 `fantuan_tap.json`，播完切回当前状态动画
   - 保留浮动动画（Lottie 内置或 SwiftUI offset 动画叠加）

2. **FanTuanViewModel.swift**
   - `FanTuanMood` 枚举新增 `starving`（饿瘪）和 `happy`（被摸）状态
   - 新增计算属性 `currentAnimationName: String`，根据 mood 返回对应 Lottie 文件名
   - 新增 `animationLoopMode: LottieLoopMode`，区分循环/单次播放

3. **GachaView.swift**
   - 卡片背面的 `🍙` + `?` 替换为饭团静态形象（从 Lottie 首帧截取或单独 SVG）
   - 吃卡动画：未选中卡片飞向饭团位置 + 饭团播放 `fantuan_eating.json`

4. **抽卡页面饭团**
   - 抽卡页顶部或底部展示大号饭团，根据抽卡进度切换表情
   - 等待用户选卡时：`idle` → 用户翻卡时：`excited` → 吃卡时：`eating`

#### 10.9.5 改动范围

| 层 | 文件 | 改动类型 |
|----|------|---------|
| iOS | `genchi.xcodeproj` | 添加 lottie-ios SPM 依赖 |
| iOS | `Resources/Animations/*.json` | 新建：9 个 Lottie 动画文件 |
| iOS | `Views/FanTuanView.swift` | 改造：Emoji → LottieView |
| iOS | `Views/GachaView.swift` | 改造：卡片背面 + 吃卡动画 |
| iOS | `ViewModels/FanTuanViewModel.swift` | 改造：状态映射动画文件 |
| iOS | `Views/LottieView.swift` | 新建：Lottie SwiftUI 封装组件 |

#### 10.9.6 验证清单

- [ ] Lottie 动画在 56pt 和 120pt 尺寸下清晰不模糊
- [ ] 9 种状态动画均能正确播放（循环/单次）
- [ ] 状态切换时无闪烁，过渡自然
- [ ] 点击饭团有弹跳反馈动画
- [ ] 吃卡动画与卡片飞入动画时序配合正确
- [ ] 饭点时间段饭团自动切换到 hungry 状态
- [ ] 下雨天饭团自动切换到 rainy 状态
- [ ] 动画文件总大小 < 500KB（9 个文件合计）
- [ ] 低端设备（iPhone SE 2）动画流畅无卡顿

---

### 10.10 饭团养成体系 — 饱食度 + 亲密度（一阶段轻量版）

> **定位**：通过饱食度和亲密度两个核心数值，将用户的每一次平台行为转化为饭团的"成长"，形成「使用 APP → 饭团变好 → 想继续用」的正向循环，提升用户留存率和日活。

#### 10.10.1 养成数值设计

**饱食度（Satiety）**：0 ~ 100，代表饭团的"肚子"状态
| 区间 | 饭团状态 | 视觉表现 |
|------|---------|---------|
| 80-100 | 饱饱的 | 正常大小，开心表情 |
| 50-79 | 有点饿 | 正常大小，idle 表情 |
| 20-49 | 饿了 | 身体微缩，hungry 表情 |
| 0-19 | 饿瘪了 | 身体明显缩小变扁，starving 表情 |

**饱食度变化规则**：
| 行为 | 饱食度变化 | 说明 |
|------|-----------|------|
| 自然衰减 | -5/天 | 每日 0 点自动扣减（后端定时或登录时计算） |
| 每日登录 | +10 | 当日首次打开 APP |
| 摸摸饭团 | +5 | 每日限 1 次有效 |
| 抽卡 | +3/次 | 每次抽卡喂食 |
| 打卡 | +15 | 打卡是最有营养的行为 |
| 收藏店铺 | +2 | 轻量行为也有贡献 |

**亲密度（Intimacy）**：0 ~ ∞，代表饭团和主人的关系，只增不减
| 等级 | 亲密度区间 | 称呼变化 | 解锁内容 |
|------|-----------|---------|---------|
| Lv.1 初识 | 0-49 | "你好呀~" | 基础冒泡文案 |
| Lv.2 熟悉 | 50-149 | "主人~" | 冒泡文案更亲密 |
| Lv.3 好友 | 150-299 | "主人主人！" | 饭团偶尔撒娇 |
| Lv.4 挚友 | 300-499 | "最爱的主人~" | 冒泡文案带个性化推荐 |
| Lv.5 灵魂伴侣 | 500+ | "只属于你的饭团！" | 专属互动动画（二阶段） |

**亲密度获取规则**：
| 行为 | 亲密度变化 | 说明 |
|------|-----------|------|
| 每日登录 | +2 | 每天来看饭团 |
| 摸摸饭团 | +3 | 每日限 1 次有效 |
| 抽卡 | +1/次 | |
| 打卡 | +5 | 打卡贡献最大 |
| 连续登录加成 | ×1.5 | 连续 3 天及以上，当日所有亲密度获取 ×1.5 |

#### 10.10.2 互动功能 — 摸摸饭团

**交互流程**：
1. 用户在地图页长按饭团（区别于短按打开菜单）
2. 触发"摸摸"动画：饭团播放 `fantuan_happy.json`（眯眼笑 + 身体摇晃）
3. 飘出 "+5 饱食度 +3 亲密度" 的浮动数字动画
4. 每日首次摸摸有效，重复摸摸饭团会说"今天已经被摸过啦~明天再来嘛"

**技术实现**：
- FanTuanView 添加 `LongPressGesture`（0.5 秒触发）
- 调用后端 API 记录摸摸行为 + 更新数值
- 前端播放 happy 动画 + 浮动数字效果

#### 10.10.3 饭团状态联动

饱食度影响饭团的默认表情优先级（高于时间段判定）：

```
if 饱食度 < 20:
    默认状态 = starving（饿瘪，最高优先级）
elif 饱食度 < 50:
    默认状态 = hungry（饿了，高于时间段）
else:
    默认状态 = 按时间段/天气判定（现有逻辑）
```

亲密度影响冒泡文案：
- 根据亲密度等级选择不同语气的文案池
- Lv.1："肚子好饿，快点我试试抽卡吧~"
- Lv.3："主人主人！快来抽卡，我闻到好吃的了！"
- Lv.5："只有主人的抽卡才是最好吃的~快来嘛！"

#### 10.10.4 数据库设计

新增 1 张表：`fantuan_status`

```sql
CREATE TABLE fantuan_status (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    satiety INTEGER NOT NULL DEFAULT 80,           -- 饱食度 0-100
    intimacy INTEGER NOT NULL DEFAULT 0,           -- 亲密度 0-∞
    intimacy_level INTEGER NOT NULL DEFAULT 1,     -- 亲密度等级 1-5
    consecutive_login_days INTEGER NOT NULL DEFAULT 0, -- 连续登录天数
    last_login_date DATE,                          -- 最后登录日期
    last_pet_date DATE,                            -- 最后摸摸日期
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

-- 索引
CREATE INDEX idx_fantuan_status_user ON fantuan_status(user_id);
```

#### 10.10.5 后端 API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/fantuan/status` | GET | 获取饭团状态（饱食度/亲密度/等级/连续登录天数） |
| `/api/fantuan/login` | POST | 每日登录签到（+饱食度 +亲密度，计算连续登录） |
| `/api/fantuan/pet` | POST | 摸摸饭团（每日限 1 次，+饱食度 +亲密度） |

**说明**：抽卡/打卡/收藏时的养成数值变化，在现有 API 中附带处理（如 `/api/gacha/select` 成功后同步更新饱食度和亲密度），不需要单独 API。

#### 10.10.6 iOS 端改动

| 文件 | 改动 |
|------|------|
| `Models/Models.swift` | 新增 `FanTuanStatus` 模型 |
| `Services/APIService.swift` | 新增 3 个 API 调用方法 |
| `ViewModels/FanTuanViewModel.swift` | 新增养成数值管理、登录签到、摸摸逻辑 |
| `Views/FanTuanView.swift` | 新增长按手势、浮动数字动画、饱食度影响外观 |
| `Views/FanTuanStatusView.swift` | 新建：饭团状态面板（显示饱食度/亲密度/等级） |
| `Views/MapView.swift` | APP 启动时调用登录签到 API |

#### 10.10.7 饭团状态面板 UI

用户短按饭团 → 弹出菜单中新增「饭团状态」入口，展示：
- 饭团大号形象（当前状态动画）
- 饱食度进度条（带数字和颜色变化：绿→黄→红）
- 亲密度等级 + 进度条（当前等级进度 / 下一等级所需）
- 连续登录天数
- "今日已摸摸 ✓" 或 "摸摸饭团" 按钮

#### 10.10.8 验证清单

- [ ] 新用户首次打开 APP，饭团饱食度为 80，亲密度为 0
- [ ] 每日首次登录，饱食度 +10，亲密度 +2
- [ ] 长按饭团触发摸摸动画，饱食度 +5，亲密度 +3
- [ ] 同一天重复摸摸，提示"今天已经被摸过啦"
- [ ] 抽卡后饱食度 +3，亲密度 +1
- [ ] 打卡后饱食度 +15，亲密度 +5
- [ ] 饱食度 < 20 时饭团显示饿瘪状态
- [ ] 饱食度 < 50 时饭团显示饿了状态
- [ ] 亲密度达到阈值后等级自动提升
- [ ] 连续登录 3 天后亲密度获取 ×1.5
- [ ] 饭团状态面板正确展示所有数值
- [ ] 3 天未登录后再次打开，饱食度扣减 15（3×5）

---

### 10.11 饭团养成体系 — 二阶段规划（暂不实施）

以下功能在头脑风暴中确认方向，待一阶段上线验证后再推进：

#### 装扮系统
- 抽卡有概率掉落装扮道具（厨师帽、围巾、墨镜、圣诞帽等）
- 用户可在饭团状态面板中切换装扮
- 装扮影响 Lottie 动画（叠加图层或切换动画变体）
- 需要为每个装扮制作对应的 Lottie 动画变体

#### 等级进化
- 亲密度达到阈值后饭团外观进化
- Lv.1 小饭团（小个子）→ Lv.3 饭团（标准）→ Lv.5 饭团大师（戴皇冠/光环）
- 每次进化有专属动画演出

#### 通知推送
- 接入 APNs 推送
- 饱食度 < 20 时推送"主人我好饿，快来看看我..."
- 连续 3 天未登录推送"主人去哪了？饭团好想你..."
- 饭点时间推送"主人，该吃饭啦！要不要我帮你选？"

#### 社交功能
- 饭团亲密度排行榜
- 好友间饭团互访
- 分享饭团状态卡片

### 10.12 分享功能
- **需求**：支持分享抽卡结果（头脑风暴中确认后续迭代）
- **待做**：
  - 抽卡结果生成分享海报（店铺信息 + 稀有度 + 推荐理由）
  - 成就解锁生成分享卡片
  - ShareSheet 集成（微信/朋友圈/保存图片）
