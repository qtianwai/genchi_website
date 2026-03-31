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
| 抖音解析 | 非官方接口 | 后期可替换为付费 API |

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
