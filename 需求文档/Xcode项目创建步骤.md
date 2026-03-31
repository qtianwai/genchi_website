# Xcode 项目创建步骤

## 第一步：创建新 Xcode 项目

1. 打开 **Xcode**（没有的话从 App Store 安装，搜索"Xcode"）
2. 点击「**Create New Project**」
3. 选择平台：**iOS** → 模板选「**App**」→ 点击「Next」
4. 填写项目信息：
   - **Product Name**：`FoodMap`
   - **Team**：先选「None」（上架时再配置）
   - **Organization Identifier**：`com.yourname`（随便填，如 `com.qtianwai`）
   - **Bundle Identifier** 会自动生成为 `com.yourname.FoodMap`
   - **Interface**：`SwiftUI`
   - **Language**：`Swift`
5. 点击「Next」，保存位置选择：`/Users/xiangzy/我的坚果云/AIcoding/达人美食推荐/ios/FoodMap/`
6. 点击「**Create**」

---

## 第二步：替换默认文件

Xcode 会自动生成 `ContentView.swift` 和 `FoodMapApp.swift`，需要替换：

1. 在 Xcode 左侧文件树中，**右键点击** `ContentView.swift` → 「Delete」→ 「Move to Trash」
2. **右键点击** `FoodMapApp.swift` → 「Delete」→ 「Move to Trash」

---

## 第三步：导入我们写好的代码文件

1. 在 Finder 中打开：`/Users/xiangzy/我的坚果云/AIcoding/达人美食推荐/ios/FoodMap/FoodMap/`
2. 选中以下所有文件和文件夹：
   - `FoodMapApp.swift`
   - `Models/` 文件夹
   - `Services/` 文件夹
   - `ViewModels/` 文件夹
   - `Views/` 文件夹
3. 将它们**拖入** Xcode 左侧的 `FoodMap` 项目文件夹中
4. 弹出对话框时，勾选「**Copy items if needed**」→ 点击「Finish」

---

## 第四步：配置 Info.plist

在 Xcode 中，点击左侧的 `Info.plist`，添加以下配置：

### 添加地图定位权限说明

| Key | Value |
|-----|-------|
| `NSLocationWhenInUseUsageDescription` | `用于在地图上显示您附近的推荐店铺` |

### 添加导航 App 跳转白名单

添加一个 Array 类型的 key：`LSApplicationQueriesSchemes`，添加以下 String 值：
- `iosamap`（高德地图）
- `baidumap`（百度地图）
- `maps`（苹果地图）

### 允许 HTTP 请求（本地开发用）

添加 `App Transport Security Settings` → `Allow Arbitrary Loads` → `YES`

> 部署到 Railway 后会自动使用 HTTPS，上架前可以删除这条

---

## 第五步：更新后端地址

部署 Railway 后，打开 [APIService.swift](../ios/FoodMap/FoodMap/Services/APIService.swift) 第 10 行：

```swift
// 将这行
let BASE_URL = "https://your-app.railway.app"
// 替换为你的 Railway 域名，例如：
let BASE_URL = "https://claude-test-production-xxxx.railway.app"
```

---

## 第六步：连接手机运行

1. 用 USB 线连接 iPhone
2. Xcode 顶部选择你的手机作为运行目标
3. 点击 ▶ 运行按钮
4. 第一次运行需要在手机「设置」→「通用」→「VPN与设备管理」中信任开发者证书

---

## 常见问题

**Q：运行报错 "Signing & Capabilities"**
A：点击 Xcode 顶部项目名 → 「Signing & Capabilities」→ 勾选「Automatically manage signing」→ 选择你的 Apple ID

**Q：没有 Apple ID**
A：用你的 Apple ID 登录 Xcode（Xcode → Settings → Accounts → 点击 + 添加）

**Q：手机系统版本太低**
A：代码要求 iOS 16+，iPhone 8 及以上均支持
