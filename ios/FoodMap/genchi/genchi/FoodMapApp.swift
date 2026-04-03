// App 入口文件
// 管理整体导航结构：未登录显示登录页，已登录显示主界面

import SwiftUI

@main
struct FoodMapApp: App {
    @StateObject private var authState = AuthState()

    // TODO: 微信开放平台审核通过后取消注释
    // init() {
    //     WechatAuthManager.shared.registerApp()
    // }

    var body: some Scene {
        WindowGroup {
            Group {
                if authState.isLoading {
                    // 启动时检查登录状态，显示 loading
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(1.5)
                } else if authState.isLoggedIn {
                    MainTabView()
                        .environmentObject(authState)
                } else {
                    LoginView()
                        .environmentObject(authState)
                }
            }
        }
    }
}
