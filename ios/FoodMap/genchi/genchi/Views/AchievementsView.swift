// 成就列表页（v8.0 新增）
// 展示所有成就定义和用户已解锁的成就

import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject var authState: AuthState
    @State private var allAchievements: [Achievement] = []
    @State private var unlockedIds: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 统计
                HStack(spacing: 20) {
                    VStack {
                        Text("\(unlockedIds.count)")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.orange)
                        Text("已解锁")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    VStack {
                        Text("\(allAchievements.count)")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.secondary)
                        Text("全部")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)

                // 成就列表
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    // 按分类分组
                    let grouped = Dictionary(grouping: allAchievements) { $0.category }
                    let categories = ["collection", "streak", "limited"]

                    ForEach(categories, id: \.self) { cat in
                        if let items = grouped[cat], !items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(categoryTitle(cat))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 20)

                                ForEach(items, id: \.id) { ach in
                                    AchievementBadgeView(
                                        achievement: ach,
                                        isUnlocked: unlockedIds.contains(ach.id)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("成就")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
    }

    private func categoryTitle(_ cat: String) -> String {
        switch cat {
        case "collection": return "收集成就"
        case "streak": return "连续成就"
        case "limited": return "限定成就"
        default: return "其他"
        }
    }

    private func loadData() async {
        guard !authState.userId.isEmpty else { return }
        do {
            async let achTask = APIService.shared.getAllAchievements()
            async let userTask = APIService.shared.getUserAchievements(userId: authState.userId)
            let (all, user) = try await (achTask, userTask)
            allAchievements = all
            unlockedIds = Set(user.map { $0.achievement_id })
        } catch {
            print("[成就] 加载失败: \(error)")
        }
        isLoading = false
    }
}

// MARK: - 单个成就徽章

struct AchievementBadgeView: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(isUnlocked ? .orange.opacity(0.15) : .gray.opacity(0.08))
                    .frame(width: 48, height: 48)
                Image(systemName: achievement.icon_name ?? "trophy")
                    .font(.title3)
                    .foregroundColor(isUnlocked ? .orange : .gray.opacity(0.4))
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(isUnlocked ? .primary : .secondary)
                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 状态
            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isUnlocked ? .white : Color(.systemGray6))
                .shadow(color: isUnlocked ? .black.opacity(0.04) : .clear, radius: 2, x: 0, y: 1)
        )
        .padding(.horizontal, 20)
        .opacity(isUnlocked ? 1 : 0.7)
    }
}
