// App 入口文件
// 管理整体导航结构：未登录显示登录页，已登录显示主界面

import SwiftUI

// Universal Link 导航用的 Identifiable 包装
struct UserMapDestination: Identifiable {
    let id: String  // user_id
}

@main
struct FoodMapApp: App {
    @StateObject private var authState = AuthState()
    @State private var openUserMapDestination: UserMapDestination? = nil  // v6.0：Universal Link 导航

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
                        .sheet(item: $openUserMapDestination) { dest in
                            NavigationStack {
                                UserMapView(targetUserId: dest.id)
                            }
                        }
                } else {
                    LoginView()
                        .environmentObject(authState)
                }
            }
            .preferredColorScheme(.light)
            .onOpenURL { url in  // v6.0 新增：处理 Universal Link
                if let userId = parseMapUserId(from: url) {
                    openUserMapDestination = UserMapDestination(id: userId)
                }
            }
        }
    }

    // v6.0 新增：解析 /map/{user_id} 路径
    private func parseMapUserId(from url: URL) -> String? {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }

        let pathComponents = url.pathComponents
        if pathComponents.count >= 2 && pathComponents[1] == "map" {
            return pathComponents.count > 2 ? pathComponents[2] : nil
        }

        return nil
    }
}
