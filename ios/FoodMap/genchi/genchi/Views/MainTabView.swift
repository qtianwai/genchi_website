// 主 Tab 导航
// v6.0：移除底部居中「+」入口，地图页右上角作为唯一添加入口

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authState: AuthState

    @State private var mapRefreshTrigger = 0

    var body: some View {
        TabView {
            // Tab 1：地图
            MapView(refreshTrigger: $mapRefreshTrigger)
                .tabItem {
                    Label("地图", systemImage: "map.fill")
                }

            // Tab 2：收藏
            FavoritesView()
                .tabItem {
                    Label("收藏", systemImage: "bookmark.fill")
                }

            // Tab 3：我的
            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.circle.fill")
                }

            // Tab 4：复核（仅管理员可见）
            if authState.isAdmin {
                ReviewListView()
                    .tabItem {
                        Label("复核", systemImage: "checkmark.shield.fill")
                    }
            }
        }
        .accentColor(DS.Color.brand)
    }
}
