// 我的页面
// 显示用户信息，支持自定义昵称和头像，支持登出

import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var authState: AuthState
    @State private var showLogoutConfirm = false
    @State private var showEditNickname = false
    @State private var editingNickname = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isUploadingAvatar = false
    @State private var uploadError: String? = nil

    var body: some View {
        NavigationView {
            List {
                // 用户信息区
                Section {
                    HStack(spacing: 14) {
                        // 头像区域：点击触发图片选择
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                avatarView
                                // 编辑角标
                                Image(systemName: isUploadingAvatar ? "arrow.triangle.2.circlepath" : "pencil.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.orange)
                                    .background(Color.white.clipShape(Circle()))
                            }
                        }
                        .disabled(isUploadingAvatar)
                        .onChange(of: selectedPhotoItem) { _, item in
                            guard let item else { return }
                            Task {
                                isUploadingAvatar = true
                                uploadError = nil
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    do {
                                        try await authState.uploadAvatar(data)
                                    } catch {
                                        uploadError = "头像上传失败，请重试"
                                    }
                                }
                                isUploadingAvatar = false
                                selectedPhotoItem = nil
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            // 昵称：点击弹出编辑框
                            Button(action: {
                                editingNickname = authState.nickname
                                showEditNickname = true
                            }) {
                                HStack(spacing: 4) {
                                    Text(authState.nickname)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Text("ID: \(authState.userId.prefix(8))...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)

                    // 上传失败提示
                    if let err = uploadError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
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
            // 昵称编辑弹窗
            .alert("修改昵称", isPresented: $showEditNickname) {
                TextField("昵称（1-20字）", text: $editingNickname)
                Button("确定") {
                    let trimmed = editingNickname.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, trimmed.count <= 20 else { return }
                    Task { try? await authState.updateNickname(trimmed) }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // 头像视图：有头像用 AsyncImage，无头像用橙色占位符
    @ViewBuilder
    var avatarView: some View {
        if let urlStr = authState.avatarURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                defaultAvatarPlaceholder
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        } else {
            defaultAvatarPlaceholder
        }
    }

    // 默认头像占位符：橙色圆形 + person 图标
    var defaultAvatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.15))
                .frame(width: 56, height: 56)
            Image(systemName: "person.fill")
                .font(.title2)
                .foregroundColor(.orange)
        }
    }
}
