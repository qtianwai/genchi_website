# 饭团 Lottie 素材接入说明

## 当前方案

项目里已经补齐了第一版饭团动画资源，路径在：

`ios/FoodMap/genchi/genchi/Resources/Animations/`

包含 9 个状态文件：

- `fantuan_idle.json`
- `fantuan_hungry.json`
- `fantuan_sleepy.json`
- `fantuan_excited.json`
- `fantuan_rainy.json`
- `fantuan_eating.json`
- `fantuan_happy.json`
- `fantuan_starving.json`
- `fantuan_tap.json`

这些文件现在已经和代码状态映射对齐，`FanTuanViewModel` 会按状态切换对应动画名。

## 为什么这样做

你现在最大的阻碍不是“不会画”，而是“没有一套能立刻接进项目的动画资产和命名规范”。

所以这次方案分成两层：

1. 先在项目里提供一套原创简化版 Lottie JSON，解决资源缺口。
2. 同时在 `Views/LottieView.swift` 里做双通道支持：
   - 已引入 `lottie-ios` 时，优先播放 JSON
   - 未引入 `lottie-ios` 时，自动回退到原生 SwiftUI 动画

这样你不会被第三方依赖或设计软件卡住，饭团功能可以继续开发。

## 现在怎么用

主入口已经接入：

- `Views/FanTuanView.swift`
- `ViewModels/FanTuanViewModel.swift`
- `Views/GachaView.swift`

你后续在其他页面如果想复用：

- 动画版：`LottieView(animation: .looping(.idle))`
- 单次反馈：`LottieView(animation: .oneShot(.tap), playbackID: someCounter)`
- 静态贴纸：`FanTuanStickerView(asset: .happy)`

## 后续升级正式素材的最稳流程

1. 先让设计师或 AI 出静态参考图，统一为同一只饭团角色。
2. 在 Figma / LottieFiles Creator / After Effects 中做正式动画。
3. 导出后直接覆盖同名文件，例如替换 `fantuan_idle.json`。
4. 保持文件名不变，业务代码基本不用改。

## 建议的正式制作规范

- 画板尺寸：`200 x 200`
- 背景：透明
- 风格：白色饭团主体 + 深绿海苔 + 粉色腮红
- 尺寸安全区：主要角色尽量控制在画板的 `80%` 内
- 循环类动画：建议 2 到 3 秒
- 单次反馈类动画：建议 0.8 到 1.5 秒

## 如果你准备接入官方 Lottie 库

建议用 Xcode 的 Swift Package Manager 添加：

- 仓库：`https://github.com/airbnb/lottie-ios`

接入完成后，当前 `LottieView.swift` 会自动优先使用库来播放这些 JSON，不需要再改调用层。
