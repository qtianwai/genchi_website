# 饭团动画资源

本目录包含饭团第一版 Lottie JSON 资源：
- fantuan_idle.json
- fantuan_hungry.json
- fantuan_sleepy.json
- fantuan_excited.json
- fantuan_rainy.json
- fantuan_eating.json
- fantuan_happy.json
- fantuan_starving.json
- fantuan_tap.json

说明：
1. 这批资源是为当前项目定制的原创简化版，优先解决“饭团状态切换与接入”问题。
2. 资源命名已和 `FanTuanViewModel` 的状态映射对齐，后续可直接同名替换为更精致的正式稿。
3. 如果项目引入 `lottie-ios`，`Views/LottieView.swift` 会优先播放这些 JSON；未引入时会自动回退到原生 SwiftUI 动画。
4. 建议保持画板 200x200 与透明背景，替换资源时尽量沿用同名文件，避免改动业务代码。
