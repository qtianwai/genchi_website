// 抽卡主页面（v8.0 新增）
// 6 张卡背面朝上 → 用户选 1 张翻开 → 其余被饭团吃掉 → 展示抽中卡详情

import SwiftUI

struct GachaView: View {
    @StateObject private var viewModel = GachaViewModel()
    @EnvironmentObject var authState: AuthState
    @ObservedObject var fanTuanVM: FanTuanViewModel

    let latitude: Double
    let longitude: Double
    var onNavigate: ((GachaCard) -> Void)?    // 导航到店铺（传完整卡片，含坐标）
    var onFavorite: ((String) -> Void)?     // 收藏店铺
    var onViewVideos: ((String) -> Void)?   // 查看探店视频
    var onCheckin: ((String) -> Void)?      // 打卡

    @Environment(\.dismiss) private var dismiss

    // 10.2 收藏留言 AI 摘要
    @State private var reviewsSummary: String? = nil

    var body: some View {
        ZStack {
            // 背景
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部栏
                headerBar

                // 主内容区
                switch viewModel.phase {
                case .loading:
                    loadingView
                case .cardsFaceDown:
                    cardSelectionView
                case .revealing, .eaten:
                    cardSelectionView  // 动画过程中仍显示卡片
                case .result:
                    if let card = viewModel.selectedCard {
                        resultView(card: card)
                            .task {
                                // 10.2 加载收藏留言 AI 摘要
                                do {
                                    let resp = try await APIService.shared.getReviewsSummary(restaurantId: card.restaurant_id)
                                    if resp.note_count > 0 {
                                        reviewsSummary = resp.summary
                                    }
                                } catch {
                                    print("[抽卡] 加载摘要失败: \(error)")
                                }
                            }
                    }
                }
            }

            // 成就解锁 Toast
            if viewModel.showAchievementToast, let ach = viewModel.newlyUnlockedAchievements.first {
                VStack {
                    achievementToast(achievement: ach)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { viewModel.showAchievementToast = false }
                    }
                }
            }
        }
        .task {
            guard !authState.userId.isEmpty else { return }
            await viewModel.fetchRemaining(userId: authState.userId)
            await viewModel.draw(userId: authState.userId, lat: latitude, lng: longitude)
        }
        // 连续换一批后插入提问
        .sheet(isPresented: $viewModel.showInsertedQuestion) {
            InsertedQuestionSheet { answers in
                viewModel.insertedQuestionAnswers = answers
                viewModel.showInsertedQuestion = false
                Task {
                    guard !authState.userId.isEmpty else { return }
                    await viewModel.draw(userId: authState.userId, lat: latitude, lng: longitude)
                }
            }
        }
    }

    // MARK: - 顶部栏

    private var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
            }

            Spacer()

            // 今日剩余次数
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("今日剩余 \(viewModel.remaining) 次")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - 加载中

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            // 饭团加载动画
            Text("🍙")
                .font(.system(size: 60))
                .rotationEffect(.degrees(viewModel.isLoading ? 10 : -10))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: viewModel.isLoading)

            Text("饭团正在挑选美食...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 8)

                Button("重试") {
                    Task {
                        guard !authState.userId.isEmpty else { return }
                        await viewModel.draw(userId: authState.userId, lat: latitude, lng: longitude)
                    }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    // MARK: - 卡片选择（6 张背面朝上）

    private var cardSelectionView: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("选一张，看看今天的美食命运！")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // 6 张卡片 2x3 网格
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(Array(viewModel.cards.enumerated()), id: \.offset) { index, card in
                    GachaCardView(
                        card: card,
                        isSelected: viewModel.selectedCardIndex == index,
                        isRevealed: viewModel.selectedCardIndex == index && viewModel.phase != .cardsFaceDown,
                        isEaten: viewModel.eatenCardIndices.contains(index)
                    )
                    .onTapGesture {
                        guard viewModel.phase == .cardsFaceDown else { return }
                        Task {
                            guard !authState.userId.isEmpty else { return }
                            await viewModel.selectCard(at: index, userId: authState.userId)
                            fanTuanVM.startEating()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    // MARK: - 抽中卡片结果

    private func resultView(card: GachaCard) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // 稀有度标签
                rarityBadge(rarity: card.rarity)

                // 店铺信息卡片
                VStack(spacing: 12) {
                    // 店铺封面图
                    if let photoUrl = card.photo_url, !photoUrl.isEmpty {
                        AsyncImage(url: URL(string: photoUrl)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.1))
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // 店铺名称
                    Text(card.name)
                        .font(.title3.weight(.semibold))

                    // 推荐理由
                    Text("「\(card.recommend_reason)」")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .italic()

                    // 关联博主（10.1）
                    if let authors = card.authors, !authors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("推荐达人")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(authors) { author in
                                    HStack(spacing: 4) {
                                        if let avatarUrl = author.avatar_url, !avatarUrl.isEmpty {
                                            AsyncImage(url: URL(string: avatarUrl)) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Circle().fill(Color.gray.opacity(0.2))
                                            }
                                            .frame(width: 20, height: 20)
                                            .clipShape(Circle())
                                        }
                                        Text(author.name)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 收藏留言 AI 摘要（10.2）
                    if let summary = reviewsSummary, !summary.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "quote.opening")
                                .font(.caption2)
                                .foregroundColor(.orange.opacity(0.6))
                            Text(summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 信息标签
                    HStack(spacing: 12) {
                        if let category = card.category, !category.isEmpty {
                            Label(category, systemImage: "fork.knife")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let distance = card.distanceText {
                            Label(distance, systemImage: "location")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let price = card.avg_price {
                            Label("¥\(price)/人", systemImage: "yensign.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 来源标签
                    Text(card.sourceText)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.orange.opacity(0.8)))
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 20)

                // 操作按钮
                VStack(spacing: 12) {
                    // 主操作行
                    HStack(spacing: 12) {
                        actionButton(icon: "location.fill", title: "导航", color: .blue) {
                            onNavigate?(card)
                        }
                        actionButton(icon: "heart.fill", title: "收藏", color: .pink) {
                            onFavorite?(card.restaurant_id)
                        }
                        actionButton(icon: "checkmark.circle.fill", title: "打卡", color: .green) {
                            onCheckin?(card.restaurant_id)
                        }
                        actionButton(icon: "play.rectangle.fill", title: "视频", color: .purple) {
                            onViewVideos?(card.restaurant_id)
                        }
                    }

                    // 再抽一次
                    Button(action: {
                        Task {
                            guard !authState.userId.isEmpty else { return }
                            await viewModel.drawAgain(userId: authState.userId, lat: latitude, lng: longitude)
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("再抽一次")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.orange)
                        )
                    }
                    .disabled(viewModel.remaining <= 0)
                    .opacity(viewModel.remaining <= 0 ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - 辅助组件

    private func rarityBadge(rarity: CardRarity) -> some View {
        HStack(spacing: 6) {
            switch rarity {
            case .normal:
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
            case .quality:
                Image(systemName: "star.fill")
                    .foregroundColor(.purple)
            case .rare:
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
            case .limited:
                Image(systemName: "sparkle")
                    .foregroundColor(.red)
            }
            Text(rarity.displayName)
                .font(.caption.weight(.semibold))
                .foregroundColor(rarityColor(rarity))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(rarityColor(rarity).opacity(0.1))
                .overlay(Capsule().stroke(rarityColor(rarity).opacity(0.3), lineWidth: 1))
        )
    }

    private func rarityColor(_ rarity: CardRarity) -> Color {
        switch rarity {
        case .normal: return .gray
        case .quality: return .purple
        case .rare: return .orange
        case .limited: return .red
        }
    }

    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
            )
        }
    }

    private func achievementToast(achievement: Achievement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon_name ?? "trophy")
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("成就解锁！")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                Text(achievement.name)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .orange.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
}

// MARK: - 单张卡片组件

struct GachaCardView: View {
    let card: GachaCard
    let isSelected: Bool
    let isRevealed: Bool
    let isEaten: Bool

    var body: some View {
        ZStack {
            if isEaten {
                // 被饭团吃掉的动画：缩小 + 旋转 + 透明
                cardBack
                    .scaleEffect(0.1)
                    .rotationEffect(.degrees(45))
                    .opacity(0)
            } else if isRevealed {
                // 翻开的卡片（正面）
                cardFront
                    .rotation3DEffect(.degrees(0), axis: (x: 0, y: 1, z: 0))
            } else {
                // 背面朝上
                cardBack
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isEaten)
        .animation(.easeInOut(duration: 0.6), value: isRevealed)
    }

    // 卡片背面
    private var cardBack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.8), .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 4) {
                Text("🍙")
                    .font(.title)
                Text("?")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
            }
        }
        .frame(height: 140)
        .shadow(color: .orange.opacity(0.2), radius: 4, x: 0, y: 2)
    }

    // 卡片正面
    private var cardFront: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(rarityBorderColor, lineWidth: 2)
                )

            VStack(spacing: 6) {
                // 稀有度小标签
                HStack {
                    Spacer()
                    Text(card.rarity.displayName)
                        .font(.system(size: 9).weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(rarityBorderColor))
                }

                // 店铺名
                Text(card.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // 品类
                if let category = card.category, !category.isEmpty {
                    Text(category)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // 距离
                if let dist = card.distanceText {
                    Text(dist)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
            .padding(8)
        }
        .frame(height: 140)
        .shadow(color: rarityBorderColor.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    private var rarityBorderColor: Color {
        switch card.rarity {
        case .normal: return .gray.opacity(0.5)
        case .quality: return .purple
        case .rare: return .orange
        case .limited: return .red
        }
    }
}

// MARK: - 连续换一批后插入的提问

struct InsertedQuestionSheet: View {
    var onComplete: ([[String: String]]) -> Void

    @State private var answers: [[String: String]] = []
    @State private var currentQuestion = 0
    @Environment(\.dismiss) private var dismiss

    // 预设的快速问题（连续换一批时用，不调 AI）
    private let questions: [(String, [String])] = [
        ("想吃什么口味？", ["清淡", "重口", "辣", "甜"]),
        ("预算大概多少？", ["随便", "30以内", "30-80", "不限"]),
    ]

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("🍙")
                    .font(.title)
                Text("饭团想更了解你～")
                    .font(.headline)
                Spacer()
            }
            .padding(.top, 8)

            if currentQuestion < questions.count {
                let (question, options) = questions[currentQuestion]

                Text(question)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(options, id: \.self) { option in
                        Button(action: {
                            answers.append(["question": question, "answer": option])
                            if currentQuestion + 1 < questions.count {
                                withAnimation { currentQuestion += 1 }
                            } else {
                                onComplete(answers)
                            }
                        }) {
                            Text(option)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                                )
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 抽卡探店视频列表（10.1）

struct GachaVideoListSheet: View {
    let restaurantId: String
    @State private var videos: [RestaurantVideo] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                } else if videos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "play.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无探店视频")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(videos) { video in
                        Button(action: {
                            if let url = video.douyinURL {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 12) {
                                // 博主头像
                                if let avatarUrl = video.author_avatar_url, !avatarUrl.isEmpty {
                                    AsyncImage(url: URL(string: avatarUrl)) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Circle().fill(Color.gray.opacity(0.2))
                                    }
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 36, height: 36)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.author_name)
                                        .font(.subheadline.weight(.medium))
                                    Text("点击查看探店视频")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("探店视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                do {
                    videos = try await APIService.shared.getRestaurantVideos(restaurantId: restaurantId)
                } catch {
                    print("[视频列表] 加载失败: \(error)")
                }
                isLoading = false
            }
        }
    }
}
