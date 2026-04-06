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

    // v6.0 新增：地图隐私设置
    @State private var isMapPublic = true
    @State private var isUpdatingMapPrivacy = false
    @State private var showMapPrivacyError: String? = nil
    @State private var showShareSheet = false

    // v8.0 成就展示（10.5）
    @State private var recentAchievements: [Achievement] = []
    @State private var unlockedCount: Int = 0
    @State private var totalCount: Int = 0

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

                    // v8.0 成就徽章展示（10.5）
                    if !recentAchievements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("成就")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(unlockedCount)/\(totalCount)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            HStack(spacing: 8) {
                                ForEach(recentAchievements.prefix(4), id: \.id) { ach in
                                    VStack(spacing: 2) {
                                        Image(systemName: ach.icon_name ?? "trophy")
                                            .font(.body)
                                            .foregroundColor(.orange)
                                        Text(ach.name)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }

                // v6.0 新增：我的地图设置
                Section("我的地图") {
                    HStack {
                        Label("公开地图", systemImage: "globe")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { isMapPublic },
                            set: { newValue in
                                Task {
                                    await updateMapPrivacy(isPublic: newValue)
                                }
                            }
                        ))
                        .labelsHidden()
                        .disabled(isUpdatingMapPrivacy)
                    }

                    if let error = showMapPrivacyError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    ShareLink(
                        item: URL(string: "https://claudetest-production-c925.up.railway.app/map/\(authState.userId)")!,
                        subject: Text("\(authState.nickname)的美食地图"),
                        message: Text("来看看我推荐的美食地图吧！")
                    ) {
                        Label("分享我的地图", systemImage: "square.and.arrow.up")
                            .foregroundColor(.orange)
                    }

                    NavigationLink(destination: MapSubscriptionsView(userId: authState.userId)) {
                        Label("订阅管理", systemImage: "bookmark.fill")
                            .foregroundColor(.orange)
                    }
                }

                // 功能区
                Section("设置") {
                    // v8.0 成就入口
                    NavigationLink(destination: AchievementsView().environmentObject(authState)) {
                        Label("我的成就", systemImage: "trophy")
                            .foregroundColor(.orange)
                    }
                    Label("关于 App", systemImage: "info.circle")
                    NavigationLink(destination: FeedbackListView().environmentObject(authState)) {
                        Label("意见反馈", systemImage: "bubble.left")
                            .foregroundColor(.orange)
                    }
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
            .onAppear {
                Task {
                    await loadMapPrivacy()
                    await loadAchievements()
                }
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

    // v6.0 新增：加载地图隐私设置
    private func loadMapPrivacy() async {
        do {
            let info = try await APIService.shared.getUserMapInfo(targetUserId: authState.userId)
            await MainActor.run {
                isMapPublic = info.is_public
            }
        } catch {
            print("[地图隐私] 加载失败: \(error)")
        }
    }

    // v6.0 新增：更新地图隐私设置
    private func updateMapPrivacy(isPublic: Bool) async {
        isUpdatingMapPrivacy = true
        showMapPrivacyError = nil
        defer { isUpdatingMapPrivacy = false }

        do {
            try await APIService.shared.updateMapPrivacy(userId: authState.userId, isPublic: isPublic)
            await MainActor.run {
                isMapPublic = isPublic
            }
        } catch {
            showMapPrivacyError = "更新失败，请重试"
            print("[地图隐私] 更新失败: \(error)")
        }
    }

    // v8.0 加载成就数据（10.5）
    private func loadAchievements() async {
        guard !authState.userId.isEmpty else { return }
        do {
            async let allTask = APIService.shared.getAllAchievements()
            async let userTask = APIService.shared.getUserAchievements(userId: authState.userId)
            let (all, user) = try await (allTask, userTask)
            let unlockedIds = Set(user.map { $0.achievement_id })
            // 取最近解锁的成就详情
            let unlocked = all.filter { unlockedIds.contains($0.id) }
            await MainActor.run {
                totalCount = all.count
                unlockedCount = unlocked.count
                recentAchievements = Array(unlocked.prefix(4))
            }
        } catch {
            print("[成就] 加载失败: \(error)")
        }
    }
}
