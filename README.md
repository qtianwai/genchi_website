# 跟吃 App

跟着喜爱的抖音博主，发现身边好店，变成你的专属美食地图。

---

## 项目结构

```
达人美食推荐/
├── backend/                    # Python FastAPI 后端
│   ├── main.py                 # API 路由主程序
│   ├── douyin_parser.py        # 抖音链接解析
│   ├── ai_extractor.py         # 通义千问 AI 提取店铺信息
│   ├── amap_service.py         # 高德地图地址搜索
│   ├── db.py                   # Supabase 数据库操作
│   ├── supabase_schema.sql     # 数据库建表 SQL
│   ├── requirements.txt        # Python 依赖
│   ├── Procfile                # Railway 部署配置
│   ├── runtime.txt             # Python 版本
│   └── .env                    # 环境变量（不提交 git）
└── ios/FoodMap/FoodMap/        # SwiftUI iOS App
    ├── FoodMapApp.swift         # App 入口
    ├── Models/Models.swift      # 数据模型
    ├── Services/
    │   ├── APIService.swift     # 后端 API 调用
    │   └── AuthState.swift      # 用户认证状态
    └── Views/
        ├── MainTabView.swift    # Tab 导航
        ├── MapView.swift        # 地图主页面
        ├── ParseLinkSheet.swift # 粘贴链接弹窗
        ├── AuthorsView.swift    # 博主列表
        ├── FavoritesView.swift  # 收藏列表
        └── LoginView.swift      # 登录页面
```

---

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| iOS App | SwiftUI | 原生 iOS，支持 iOS 16+ |
| 后端 | Python FastAPI | 轻量高性能 API 框架 |
| 部署 | Railway | 免费起步，自动部署 |
| 数据库 | Supabase (PostgreSQL) | 免费套餐，含用户认证 |
| AI | 通义千问 qwen-plus | 提取视频中的店铺信息 |
| 地图 | 高德地图 API | 地址搜索 + iOS 地图展示 |
| 抖音解析 | JustOneAPI | 第三方付费 API，稳定获取视频详情和博主视频列表 |

---

## 部署步骤

### 第一步：初始化 Supabase 数据库

1. 打开 [Supabase 控制台](https://supabase.com) → 进入你的项目
2. 左侧菜单点击「SQL Editor」
3. 将 `backend/supabase_schema.sql` 的全部内容粘贴进去
4. 点击「Run」执行，创建所有数据表

### 第二步：在 Supabase 开启手机号登录

1. 左侧菜单「Authentication」→「Providers」
2. 找到「Phone」，开启它
3. 选择短信服务商（推荐 Twilio，有免费试用）
4. 填入 Twilio 的 Account SID 和 Auth Token

> 如果暂时不想配置短信，可以在 Supabase 的「Authentication」→「Settings」中开启「Enable email confirmations」关闭，然后用邮箱登录替代

### 第三步：部署后端到 Railway

1. 将项目推送到 GitHub（`backend/` 目录）
2. 打开 [Railway](https://railway.app) → 「New Project」→「Deploy from GitHub repo」
3. 选择你的仓库，Railway 会自动识别 `Procfile` 并部署
4. 部署完成后，进入「Variables」添加环境变量：
   ```
   DASHSCOPE_API_KEY=sk-2c6e706e26524eb696026f1b4c9a57ad
   AMAP_API_KEY=ed74b2610dc920e300ae8e54838e659c
   SUPABASE_URL=https://ygsxhvsmivcckmjmjmhr.supabase.co
   SUPABASE_ANON_KEY=sb_publishable_gQdKpwmrgSIQOV2G45mghg_uWiIRnrd
   SUPABASE_SERVICE_ROLE_KEY=sb_secret_dZmLQbc1r3vmHMt7k770eA_90VW8JtN
   JUSTONEAPI_TOKEN=2UJdMdkQiP4xaOIS
   ```
5. 复制 Railway 给你的域名（如 `https://xxx.railway.app`）

### 第四步：配置 iOS 项目

1. 用 Xcode 打开 `ios/FoodMap/` 目录（需要先创建 Xcode 项目，见下方说明）
2. 修改 [APIService.swift](ios/FoodMap/FoodMap/Services/APIService.swift) 第 10 行，将 `BASE_URL` 替换为 Railway 域名
3. 在 Xcode 的 `Info.plist` 中添加：
   - `NSLocationWhenInUseUsageDescription` → 值：`用于在地图上显示您附近的推荐店铺`
   - `LSApplicationQueriesSchemes` → 添加：`iosamap`、`baidumap`（支持跳转导航 App）
4. 连接 iPhone，点击运行

---

## 创建 Xcode 项目（重要）

由于 Xcode 项目文件（`.xcodeproj`）需要在 Xcode 中创建，请按以下步骤操作：

1. 打开 Xcode → 「Create New Project」
2. 选择「iOS」→「App」
3. 填写：
   - Product Name: `FoodMap`
   - Bundle Identifier: `com.yourname.foodmap`（记住这个，高德 iOS Key 需要对应）
   - Interface: `SwiftUI`
   - Language: `Swift`
4. 保存到 `ios/FoodMap/` 目录
5. 将 `ios/FoodMap/FoodMap/` 下的所有 `.swift` 文件拖入 Xcode 项目（替换默认的 `ContentView.swift`）
6. 删除 Xcode 自动生成的 `ContentView.swift`

---

## 本地开发后端

```bash
cd backend
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
python main.py
# 服务启动在 http://localhost:8000
# 访问 http://localhost:8000/docs 查看 API 文档
```

---

## API 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/parse-link` | 解析抖音链接，提取店铺 |
| GET | `/api/map/restaurants?user_id=` | 获取地图店铺数据 |
| GET | `/api/authors/following?user_id=` | 获取关注的博主 |
| POST | `/api/authors/follow` | 关注博主 |
| POST | `/api/authors/unfollow` | 取消关注 |
| GET | `/api/favorites?user_id=` | 获取收藏列表 |
| POST | `/api/favorites/add` | 收藏店铺 |
| POST | `/api/favorites/remove` | 取消收藏 |

---

## 会话记录

### 2026-03-31 第一次会话：产品分析与方案规划
- 主要目的：分析产品需求，制定技术方案
- 完成任务：技术栈选型、API 注册指引、确认多用户支持需求
- 关键决策：AI 服务选用通义千问（国内易注册）、后端部署选 Railway、数据库选 Supabase
- 技术栈：SwiftUI + FastAPI + Supabase + 通义千问 + 高德地图
- 修改文件：无（仅分析规划）

### 2026-03-31 第二次会话：搭建完整项目骨架
- 主要目的：根据收集到的 API Key，搭建后端和 iOS 前端完整代码骨架
- 完成任务：
  - 后端：`main.py`（FastAPI 路由）、`douyin_parser.py`（抖音解析）、`ai_extractor.py`（通义千问）、`amap_service.py`（高德地图）、`db.py`（Supabase 操作）、`supabase_schema.sql`（数据库建表）、`Procfile`/`runtime.txt`（Railway 部署）
  - iOS：`FoodMapApp.swift`（入口）、`Models.swift`（数据模型）、`APIService.swift`（网络请求）、`AuthState.swift`（认证）、`MapView.swift`（地图主页）、`ParseLinkSheet.swift`（粘贴链接）、`AuthorsView.swift`（博主列表）、`FavoritesView.swift`（收藏）、`LoginView.swift`（登录）、`MainTabView.swift`（Tab 导航）
  - 配置：`.gitignore`、`README.md`
- 关键决策：
  - 博主已入库则直接复用数据，不重复调用 AI（节省费用）
  - 地图标注叠加博主头像，支持按博主筛选
  - 导航支持苹果地图、高德、百度三选一
  - 用户认证使用 Supabase Auth 手机号 OTP
- 技术栈：Python FastAPI + SwiftUI + Supabase + 通义千问 qwen-plus + 高德地图 API
- 修改文件：新建 backend/ 和 ios/ 下共 17 个文件，README.md，.gitignore

### 2026-04-01 第四次会话：产品命名
- 主要目的：为产品取一个合适的名称
- 完成任务：将产品名从"达人美食推荐"改为"跟吃"
- 关键决策：选用"跟吃"——口语化、传播性强，一听就懂是跟着达人吃
- 修改文件：README.md、LoginView.swift、backend/main.py、需求文档/Railway部署步骤.md、需求文档/Xcode项目创建步骤.md

### 2026-04-01 第五次会话：替换短信服务为阿里云
- 主要目的：解决登录页发送验证码失败问题，将短信服务从 Supabase Auth 改为阿里云短信
- 完成任务：
  - 新建 `backend/sms_service.py`：阿里云短信发送、验证码内存存储、手机号生成 user_id（UUID v5）
  - 新增后端接口 `POST /api/auth/send-otp` 和 `POST /api/auth/verify-otp`
  - 改写 `ios/FoodMap/FoodMap/Services/AuthState.swift`：改调后端接口，不再直接调 Supabase Auth
  - 新建 `需求文档/阿里云短信开通步骤.md`：阿里云短信服务开通操作指引
  - 更新 `需求文档/Railway部署步骤.md`：补充阿里云短信相关环境变量
- 关键决策：
  - user_id 用 UUID v5（手机号确定性生成），同一手机号永远对应同一 ID，无需用户表
  - 验证码存内存（dict），5 分钟过期，验证成功即删除
  - 未配置阿里云密钥时自动降级为打印日志（方便本地开发调试）
- 待完成：阿里云短信签名和模板审核通过后，在 Railway 环境变量中填入 ALIYUN_ACCESS_KEY_ID、ALIYUN_ACCESS_KEY_SECRET、SMS_TEMPLATE_CODE
- 修改文件：backend/main.py、backend/sms_service.py（新建）、ios/.../AuthState.swift、需求文档/阿里云短信开通步骤.md（新建）、需求文档/Railway部署步骤.md

### 2026-04-01 第六次会话：修复抖音解析 - 完整 JSON 提取
- 主要目的：修复 _ROUTER_DATA JSON 被截断导致解析失败的问题，并讨论提升店铺识别准确率的方向
- 完成任务：
  - 调试发现 iesdouyin.com 分享页的 `window._ROUTER_DATA` 包含完整视频信息（desc、author、sec_uid、头像），但之前的正则提取在 8964 字符处截断
  - 实现 `extract_json_object()` 函数，用括号深度匹配方式提取完整 JSON，彻底解决截断问题
  - 验证解析结果：title="上海超级巨无敌好吃的不改良重庆火锅...#上海火锅去哪吃 #上海火锅店"，author="不吃西瓜不要关注"，sec_uid 完整
- 关键决策：
  - 放弃 og:title/og:description（JS 渲染页面无法获取），改为直接解析 _ROUTER_DATA 内嵌 JSON
  - 视频 desc 包含完整话题标签（含城市信息），比单纯标题信息量大很多，AI 提取店铺更准确
  - 评论 API 反爬严重，暂不获取；可通过批量处理博主多个视频的 desc 来弥补信息量不足
- 修改文件：backend/douyin_parser.py

### 2026-04-01 第七次会话：替换抖音解析服务为 JustOneAPI
- 主要目的：解决自行爬取抖音不稳定、无法批量获取博主视频的问题，改用 JustOneAPI 第三方服务
- 完成任务：
  - 完全重写 `backend/douyin_parser.py`：移除所有自行爬取逻辑，改用 JustOneAPI 的三个核心接口
    - `share-url-transfer/v1`：分享短链直接解析为结构化视频数据（替代原来的 HTML 爬取）
    - `get-user-video-list/v1`：稳定获取博主视频列表，支持分页（替代原来调用抖音 API 经常失败的方案）
  - 更新 `backend/.env`：新增 `JUSTONEAPI_TOKEN=2UJdMdkQiP4xaOIS`
  - 更新 `backend/requirements.txt`：新增 `justoneapi>=2.0.1` 依赖
- 关键决策：
  - token 通过 query 参数传递（JustOneAPI 的标准认证方式）
  - 保留 `extract_url_from_text()` 函数，兼容用户粘贴整段分享文字的场景
  - 视频列表支持自动翻页，直到达到 max_count 或无更多数据
  - 对外接口（`parse_douyin_link` / `fetch_author_videos`）签名不变，main.py 无需修改
- 修改文件：backend/douyin_parser.py、backend/.env、backend/requirements.txt

### 2026-04-01 第八次会话：优化抖音店铺解析算法（优先级策略）
- 主要目的：优化店铺识别准确率，解决一个视频解析出多个模糊店名的问题
- 验证结果（通过示例链接 https://v.douyin.com/4zIppExRIAg/）：
  - `parse_douyin_link` ✅ 正常：获取到视频ID、作者信息（"不吃西瓜不要关注"）、sec_uid
  - `fetch_author_videos` ✅ 正常：获取到博主20条视频，其中13条识别为探店相关
  - `fetch_video_comments` ✅ 正常：获取到评论，且评论包含 `is_author_digged`（博主点赞）和 `is_hot`（热门）字段
  - `get-video-detail` ✅ 正常：包含 `text_extra`（话题标签）、`city`（城市编码310000=上海）等高价值字段
  - 发现：评论接口每页约19条，支持分页（page=1/2/3...）
- 完成任务：
  - `douyin_parser.py` 新增 `fetch_video_detail_extra()` 函数：提取话题标签、城市编码、博主点赞评论、热门评论
  - `douyin_parser.py` 修复正则 bug：`/video/(\d+)/` → `/video/(\d+)`，解决链接格式差异导致提取失败
  - `douyin_parser.py` `_aget()` 增加自动重试（最多2次），应对 JustOneAPI 偶发 301 错误
  - `ai_extractor.py` 新增 `extract_restaurants_priority()` 函数：实现优先级提取策略
    - P1（最高）：视频标题 + 话题标签 + 博主昵称 + 城市
    - P2（高）：博主点赞评论（is_author_digged=True）
    - P3（中）：热门评论（is_hot=True）
    - P4（低）：普通评论兜底
  - `ai_extractor.py` 修复变量名：`client` → `dashscope_client`（统一客户端命名）
  - `main.py` 集成新函数：每个视频先调用 `fetch_video_detail_extra` 获取 P1/P2 信息，再调用 `extract_restaurants_priority`，未识别时降级旧算法
- 关键决策：
  - 博主点赞评论（is_author_digged=True）是最高价值的评论来源，博主认可即代表视频核心内容
  - 热门评论（is_hot=True）代表大众共识，往往有人直接说出店名
  - 标题和话题标签是最直接的店铺信息来源（如"#上海重庆火锅天花板"直接暗示了火锅店）
  - P1 信息不充分时才依赖评论兜底，避免被误导
- 技术栈：Python FastAPI + JustOneAPI + 通义千问 qwen-plus
- 修改文件：backend/douyin_parser.py、backend/ai_extractor.py、backend/main.py

---

## 会话 2026-04-01：优化解析流程 + 解决前端超时问题

### 主要目的
解决"前端提示超时但后端继续解析"的前后端不一致问题，同时优化用户体验：
1. 视频地址优先缓存命中，不再重复解析
2. 优先解析当前视频快速返回，不等博主所有历史视频
3. 博主历史探店视频在后台异步解析，不阻塞用户
4. 前端展示后台解析进度，让用户感知任务正在进行

### 完成的主要任务
- 新增数据库表 `video_parse_cache`：按视频分享链接精确缓存解析结果
- 新增数据库表 `author_background_tasks`：管理博主历史视频的后台异步解析任务
- `db.py` 新增 11 个函数：视频缓存读写、后台任务状态管理
- 重构 `main.py` `/api/parse-link` 接口：新逻辑流程（缓存优先→快速解析当前→后台异步）
- 新增 `GET /api/parse-status/{author_id}` 接口：前端轮询查询后台任务进度
- 新增后台异步函数 `parse_author_all_videos_background`：独立事件循环解析博主历史视频
- 前端 Models 新增 `BackgroundProgress`、`ParseStatusResponse` 模型
- 前端 APIService 新增 `getParseStatus` 方法
- 前端 ParseLinkSheet 新增后台进度指示器（BgProgressView）、轮询机制、解析完成通知

### 关键决策和解决方案
- **视频级缓存**：用用户提交的原始链接作为唯一键（`video_url`），精确匹配避免重复解析
- **快速返回**：当前视频只用标题解析（不获取评论/额外信息），节省 1-2 个 API 调用
- **后台任务隔离**：使用 `asyncio.new_event_loop()` 在独立线程中执行后台任务，避免 FastAPI 事件循环阻塞
- **任务状态持久化**：后台任务进度写入 `author_background_tasks` 表，前端通过轮询 `/api/parse-status` 获取
- **新旧格式兼容**：前端 `ParseResultView` 同时支持返回 `restaurants`（旧） 和 `restaurant`（新）两种格式

### 技术栈
- Python FastAPI + BackgroundTasks + asyncio
- Supabase（PostgreSQL）
- SwiftUI + Combine（定时轮询）

### 修改文件
- `backend/supabase_schema.sql`：新增 `video_parse_cache` 表和 `author_background_tasks` 表
- `backend/db.py`：新增 11 个数据库操作函数
- `backend/main.py`：重构 `/api/parse-link` 接口，新增 `/api/parse-status` 接口，新增后台解析函数
- `ios/FoodMap/FoodMap/Models/Models.swift`：新增模型适配新 API 响应
- `ios/FoodMap/FoodMap/Services/APIService.swift`：新增 `getParseStatus` 方法
- `ios/FoodMap/FoodMap/Views/ParseLinkSheet.swift`：新增后台进度 UI 和轮询逻辑
- `ios/FoodMap/genchi/genchi/Models/Models.swift`：同步更新
- `ios/FoodMap/genchi/genchi/Services/APIService.swift`：同步更新
- `ios/FoodMap/genchi/genchi/Views/ParseLinkSheet.swift`：同步更新

---

## 会话记录 2026-04-01

### 主要目的
强化项目规则中对核心技术文档的维护要求。

### 完成的主要任务
更新 CLAUDE.md 文档维护规则，添加重要提示说明视频解析与数据入库技术方案文档是项目最复杂最核心的内容，要求每次相关逻辑调整时必须第一时间复核并更新该文档。

### 修改了哪些文件
- `CLAUDE.md`：文档维护规则部分新增重要提示说明

---

## 会话记录 2026-04-01：地图功能优化三项

### 主要目的
解决地图页面三个用户体验问题：
1. 无法看到用户当前定位
2. 店铺详情弹框与粘贴链接按钮重合
3. 导航软件目的地显示乱码

### 完成的主要任务
- **用户定位功能**：
  - 新建 `LocationManager.swift`：封装 CoreLocation 定位逻辑，自动请求权限并持续更新位置
  - `MapViewModel` 新增 `isFirstLocationUpdate` 标志和 `centerMapOnUserLocation()` 方法
  - `MapView` 集成定位管理器，首次定位时自动将地图中心移至用户位置
  - `Info.plist` 新增 `NSLocationWhenInUseUsageDescription` 权限说明
  - 地图开启 `showsUserLocation: true` 显示用户位置蓝点

- **修复弹框重合问题**：
  - 粘贴链接按钮的 `padding(.bottom)` 改为动态计算：有选中店铺时 320pt，无选中时 100pt
  - 确保按钮始终在详情卡片上方，不会被遮挡

- **店铺关联视频列表**：
  - 数据库新增函数 `get_videos_by_restaurant()`：查询店铺关联的所有视频（含博主信息）
  - 后端新增接口 `GET /api/restaurants/{restaurant_id}/videos`
  - 前端新增 `RestaurantVideo` 模型，支持点击跳转抖音 App
  - `RestaurantCard` 新增视频列表横向滚动区域，显示博主头像、名称和"查看视频"按钮
  - `VideoThumbnail` 组件：点击后通过 URL Scheme 跳转抖音 App 查看原视频

- **修复导航乱码问题**：
  - 三个导航函数（苹果地图、高德、百度）统一使用 `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` 对店铺名称进行 UTF-8 编码
  - 苹果地图新增 `q=` 参数传递店铺名称，确保目的地正确显示
  - 增强错误处理：URL 构建失败时不会崩溃，改为静默失败

### 关键决策
- 定位权限采用"使用期间"而非"始终"，降低用户隐私顾虑
- 首次定位后自动移动地图，后续不再自动移动（避免干扰用户操作）
- 视频列表采用横向滚动，节省垂直空间
- 抖音跳转使用 `snssdk1128://aweme/detail/{video_id}` URL Scheme

### 技术栈
- SwiftUI + CoreLocation
- PostgreSQL 存储过程（RPC）
- FastAPI RESTful API

### 修改文件
- `ios/FoodMap/FoodMap/Services/LocationManager.swift`（新建）
- `ios/FoodMap/FoodMap/ViewModels/MapViewModel.swift`
- `ios/FoodMap/FoodMap/Views/MapView.swift`
- `ios/FoodMap/genchi/genchi/Info.plist`
- `ios/FoodMap/FoodMap/Models/Models.swift`
- `ios/FoodMap/FoodMap/Services/APIService.swift`
- `backend/db.py`
- `backend/main.py`
- `backend/get_videos_function.sql`（新建）

---

## 会话总结 2026-04-01：优化视频解析识别率 + 新增手动添加店铺功能

### 主要目的
解决视频解析识别率低和用户无法手动补充店铺的问题

### 完成的主要任务
1. **优化快速路径解析逻辑**：
   - 修改 `parse_single_video_fast` 函数，增加评论和扩展信息获取
   - 使用 `asyncio.gather` 并行调用 `fetch_video_detail_extra` 和 `fetch_video_comments`
   - 响应时间约 8-12 秒，识别率提升约 30-40%

2. **新增手动添加店铺功能**：
   - 后端新增 `POST /api/manual-add-restaurant` 接口
   - 前端新增 `ManualAddRestaurantSheet` 组件
   - 当 AI 无法识别店铺时，用户可手动输入店铺名称和城市
   - 通过高德地图验证并入库，帮助其他用户

3. **更新技术文档**：
   - 更新 `视频解析与数据入库技术方案.md`：记录解析策略变更
   - 新增 `手动输入店铺功能设计.md`：完整功能设计文档

### 关键决策和解决方案

**问题1：视频标题不含店铺名时识别失败**
- **案例**：视频标题"烤羊鞭烤羊蛋烤羊腰齐上阵，今天也来试试男人的'加油..."，实际店铺是"上海新Q烤吧（斜土路店）"
- **原因**：快速路径只解析标题，不获取评论和扩展信息，导致信息不足
- **解决方案**：
  - 修改 `parse_single_video_fast` 函数，并行获取评论和扩展信息（话题标签、城市、博主点赞评论）
  - 使用完整的 P1-P4 优先级信息调用 AI 提取
  - 响应时间从 5-10 秒增加到 8-12 秒，但识别率提升 30-40%

**问题2：AI 识别失败后用户无法手动补充店铺**
- **解决方案**：
  - 后端新增 `/api/manual-add-restaurant` 接口，接收用户手动输入的店铺信息
  - 通过高德地图搜索验证店铺真实性和坐标
  - 入库后更新视频缓存状态，其他用户粘贴相同视频时直接命中缓存
  - 前端在解析结果为空时显示"手动添加店铺"按钮，弹出表单让用户填写

**问题3：解析完成后 UI 状态混乱**
- **现象**：解析完成后"开始解析"按钮仍显示，后台进度显示"已处理6个"一直不变
- **分析**：这是前端状态管理问题，需要进一步调试
- **待解决**：需要检查前端轮询逻辑和状态更新机制

### 使用的技术栈
- 后端：FastAPI + asyncio.gather（并行 API 调用）
- 前端：SwiftUI + @State 状态管理
- AI：通义千问 qwen-plus（优先级策略提取）
- 地图：高德地图 API（店铺坐标验证）

### 修改的文件
- `backend/main.py`：优化 `parse_single_video_fast` 函数，新增 `/api/manual-add-restaurant` 接口
- `ios/FoodMap/FoodMap/Services/APIService.swift`：新增 `manualAddRestaurant` 方法
- `ios/FoodMap/FoodMap/Models/Models.swift`：新增 `ManualAddRestaurantResponse` 模型
- `ios/FoodMap/FoodMap/Views/ParseLinkSheet.swift`：集成手动添加店铺按钮和弹窗
- `ios/FoodMap/FoodMap/Views/ManualAddRestaurantSheet.swift`（新建）：手动添加店铺组件
- `需求文档&技术方案/视频解析与数据入库技术方案.md`：更新解析策略说明
- `需求文档&技术方案/手动输入店铺功能设计.md`（新建）：功能设计文档

---

---

## 会话记录 2026-04-01（video_url 迁移收尾）

### 主要目的
完成 `video_parse_cache.video_url` 字段从 `bg://` 占位符到真实抖音分享链接的全量迁移，并验证 Supabase SQL 函数更新生效。

### 完成的主要任务
1. 在 Supabase SQL Editor 执行 `backend/get_videos_function.sql`，更新 `get_videos_by_restaurant` 函数以返回 `video_url` 字段
2. 编写验证脚本 `backend/verify_video_url.py`，确认函数返回真实 `https://v.douyin.com/...` 链接
3. 排查并修复剩余 2 条 `bg://` 记录，降级为 `https://www.iesdouyin.com/share/video/{video_id}/` 格式
4. 最终确认数据库中 `bg://` 记录清零

### 关键决策
- SQL 函数参数名为 `p_restaurant_id`（非 `restaurant_id_param`），调用时需注意
- JustOneAPI 本地 SSL 连接失败时，直接使用 iesdouyin 标准分享链接作为降级方案

### 技术栈
- Python + requests（直接调用 Supabase REST API）
- Supabase PostgreSQL RPC 函数

### 修改的文件
- `backend/get_videos_function.sql`（已在 Supabase 执行）
- `backend/verify_video_url.py`（新增，验证脚本）
- `backend/check_failed_migrations.py`（新增，排查脚本）
