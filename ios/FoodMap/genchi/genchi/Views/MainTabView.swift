// 主 Tab 导航
// App 底部 Tab 栏：地图、博主、收藏、我的（管理员额外显示「复核」Tab）
// v4.0：底部居中新增「+」按钮，统一入口（解析抖音链接 / 手动添加店铺）

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

                // Tab 2：关注的博主
                AuthorsView()
                    .tabItem {
                        Label("博主", systemImage: "person.2.fill")
                    }

                // Tab 3：占位（居中「+」按钮用）
                Color.clear
                    .tabItem {
                        Label("", systemImage: "plus")
                    }
                    .disabled(true)

                // Tab 4：收藏的店铺
                FavoritesView()
                    .tabItem {
                        Label("收藏", systemImage: "heart.fill")
                    }

                // Tab 5：我的
                ProfileView()
                    .tabItem {
                        Label("我的", systemImage: "person.circle.fill")
                    }

                // Tab 6：复核（仅管理员可见，v3.0 新增）
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
                    // 外圈白色背景（与 Tab Bar 融合）
                    Circle()
                        .fill(DS.Color.surface)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    // 内圈品牌色
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
            .offset(y: -16)  // 向上偏移，突出于 Tab Bar
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
