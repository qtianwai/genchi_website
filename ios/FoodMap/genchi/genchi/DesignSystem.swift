// 轻量设计系统
// 统一管理移动端 UI 的间距、圆角、阴影、颜色等视觉 token，避免样式参数散落硬编码

import SwiftUI

// Design System 缩写 DS
// 所有页面直接通过 DS.Spacing / DS.Radius / DS.Shadow / DS.Color 使用统一样式
// 仅负责视觉层，不承载任何业务逻辑

enum DS {
    // 统一间距 token
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // 统一圆角 token
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // 统一阴影 token
    enum Shadow {
        static let cardColor = SwiftUI.Color.black.opacity(0.12)
        static let cardRadius: CGFloat = 8
        static let cardY: CGFloat = 2

        static let chipColor = SwiftUI.Color.black.opacity(0.10)
        static let chipRadius: CGFloat = 2
        static let chipY: CGFloat = 1

        static let pinSelectedRadius: CGFloat = 6
        static let pinNormalRadius: CGFloat = 3
    }

    // 统一颜色 token
    enum Color {
        static let brand = SwiftUI.Color.orange
        static let surface = SwiftUI.Color(.systemBackground)
        static let surfaceAlt = SwiftUI.Color(.systemGray6)
        static let separator = SwiftUI.Color(.separator)
        static let success = SwiftUI.Color.green
        static let danger = SwiftUI.Color.red
        static let info = SwiftUI.Color.blue
    }
}
