// 我的页面
// 显示用户信息，支持登出

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authState: AuthState
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationView {
            List {
                // 用户信息区
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("美食探索者")
                                .font(.headline)
                            Text("ID: \(authState.userId.prefix(8))...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // 功能区
                Section("设置") {
                    Label("关于 App", systemImage: "info.circle")
                    Label("意见反馈", systemImage: "bubble.left")
                }

                // 登出
                Section {
                    Button(action: { showLogoutConfirm = true }) {
                        HStack {
                            Spacer()
                            Text("退出登录")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .confirmationDialog("确认退出登录？", isPresented: $showLogoutConfirm) {
                Button("退出登录", role: .destructive) {
                    authState.signOut()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
