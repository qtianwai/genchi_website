// 主 Tab 导航
// App 底部 Tab 栏：地图、博主、收藏、我的（管理员额外显示「复核」Tab）

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authState: AuthState

    var body: some View {
        TabView {
            // Tab 1：地图（核心功能）
            MapView()
                .tabItem {
                    Label("地图", systemImage: "map.fill")
                }

            // Tab 2：关注的博主
            AuthorsView()
                .tabItem {
                    Label("博主", systemImage: "person.2.fill")
                }

            // Tab 3：收藏的店铺
            FavoritesView()
                .tabItem {
                    Label("收藏", systemImage: "heart.fill")
                }

            // Tab 4：我的
            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.circle.fill")
                }

            // Tab 5：复核（仅管理员可见，v3.0 新增）
            if authState.isAdmin {
                ReviewListView()
                    .tabItem {
                        Label("复核", systemImage: "checkmark.shield.fill")
                    }
            }
        }
        .accentColor(.orange)
    }
}
