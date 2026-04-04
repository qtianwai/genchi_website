// App 入口文件
// 管理整体导航结构：未登录显示登录页，已登录显示主界面

import SwiftUI

@main
struct FoodMapApp: App {
    @StateObject private var authState = AuthState()
    @State private var openUserMapId: String? = nil  // v6.0 新增：Universal Link 导航

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
                        .sheet(item: Binding(
                            get: { openUserMapId.map { NSString(string: $0) as NSString } },
                            set: { openUserMapId = $0 as String? }
                        )) { userId in
                            NavigationStack {
                                UserMapView(targetUserId: userId as String)
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
                    openUserMapId = userId
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
