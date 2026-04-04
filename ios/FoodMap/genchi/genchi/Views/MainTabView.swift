// 主 Tab 导航
// App 底部 Tab 栏：地图、+占位、收藏、我的（管理员额外显示「复核」Tab）
// v5.0：删除博主 Tab，合并到收藏页；收藏 Tab 图标改为 bookmark

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authState: AuthState

    // 控制「+」按钮弹出的选择面板
    @State private var showAddMenu = false
    // 控制解析链接弹窗
    @State private var showParseSheet = false
    // 控制手动添加店铺弹窗
    @State private var showUserAddSheet = false
    // 地图刷新触发器（添加成功后通知地图刷新）
    @State private var mapRefreshTrigger = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                // Tab 1：地图（核心功能）
                MapView(refreshTrigger: $mapRefreshTrigger)
                    .tabItem {
                        Label("地图", systemImage: "map.fill")
                    }

                // Tab 2：占位（居中「+」按钮用）
                Color.clear
                    .tabItem {
                        Label("", systemImage: "plus")
                    }
                    .disabled(true)

                // Tab 3：收藏（合并原博主+收藏功能）
                FavoritesView()
                    .tabItem {
                        Label("收藏", systemImage: "bookmark.fill")
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
            .accentColor(DS.Color.brand)

            // ── 居中「+」按钮（仿抖音风格）──
            Button(action: { showAddMenu = true }) {
                ZStack {
                    Circle()
                        .fill(DS.Color.surface)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [DS.Color.brand, DS.Color.brand.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -16)
            .confirmationDialog("添加店铺", isPresented: $showAddMenu, titleVisibility: .visible) {
                Button("解析抖音链接") { showParseSheet = true }
                Button("手动添加店铺") { showUserAddSheet = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text("选择添加方式")
            }
        }
        .sheet(isPresented: $showParseSheet) {
            ParseLinkSheet(onSuccess: {
                mapRefreshTrigger += 1
            })
            .environmentObject(authState)
        }
        .sheet(isPresented: $showUserAddSheet) {
            UserAddRestaurantSheet(onSuccess: {
                mapRefreshTrigger += 1
            })
            .environmentObject(authState)
        }
    }
}
