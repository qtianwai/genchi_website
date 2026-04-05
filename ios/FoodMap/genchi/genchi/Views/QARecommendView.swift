// 问答推荐页面（v8.0 新增）
// 动态问题展示 + 用户回答 + 推荐结果列表

import SwiftUI

struct QARecommendView: View {
    @StateObject private var viewModel = QARecommendViewModel()
    @EnvironmentObject var authState: AuthState

    let latitude: Double
    let longitude: Double
    var onNavigate: ((String) -> Void)?
    var onFavorite: ((String) -> Void)?
    var onCheckin: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部栏
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
                    Text("🍙 智能问答")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 主内容
                switch viewModel.phase {
                case .loadingQuestions, .loadingResult:
                    loadingView
                case .answering:
                    answeringView
                case .result:
                    resultListView
                }
            }
        }
        .task {
            guard !authState.userId.isEmpty else { return }
            await viewModel.fetchQuestions(userId: authState.userId, lat: latitude, lng: longitude)
        }
    }

    // MARK: - 加载中

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🍙")
                .font(.system(size: 50))
            Text(viewModel.phase == .loadingQuestions ? "饭团正在想问题..." : "饭团正在挑选美食...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
                Button("重试") {
                    Task {
                        guard !authState.userId.isEmpty else { return }
                        await viewModel.fetchQuestions(userId: authState.userId, lat: latitude, lng: longitude)
                    }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    // MARK: - 回答问题

    private var answeringView: some View {
        VStack(spacing: 24) {
            Spacer()

            // 进度指示
            HStack(spacing: 6) {
                ForEach(0..<viewModel.questions.count, id: \.self) { i in
                    Circle()
                        .fill(i <= viewModel.currentQuestionIndex ? Color.orange : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            // 当前问题
            if viewModel.currentQuestionIndex < viewModel.questions.count {
                let question = viewModel.questions[viewModel.currentQuestionIndex]

                Text(question.text)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    .id(viewModel.currentQuestionIndex)

                // 选项
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(question.options, id: \.self) { option in
                        Button(action: {
                            Task {
                                guard !authState.userId.isEmpty else { return }
                                await viewModel.answerQuestion(option: option, userId: authState.userId, lat: latitude, lng: longitude)
                            }
                        }) {
                            Text(option)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    // MARK: - 推荐结果列表

    private var resultListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("饭团为你精选了这些！")
                    .font(.headline)
                    .padding(.top, 16)

                ForEach(viewModel.recommendations) { rec in
                    recommendationCard(rec)
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func recommendationCard(_ rec: QARecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 店铺封面
            if let photoUrl = rec.photo_url, !photoUrl.isEmpty {
                AsyncImage(url: URL(string: photoUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.1))
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // 店铺信息
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.name)
                        .font(.subheadline.weight(.semibold))
                    Text("「\(rec.recommend_reason)」")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .italic()
                }
                Spacer()
                if let dist = rec.distanceText {
                    Text(dist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 标签
            HStack(spacing: 8) {
                if let category = rec.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.gray.opacity(0.1)))
                }
                if let price = rec.avg_price {
                    Text("¥\(price)/人")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.orange.opacity(0.1)))
                }
            }

            // 操作按钮
            HStack(spacing: 12) {
                Button(action: { onNavigate?(rec.restaurant_id) }) {
                    Label("导航", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                Button(action: { onFavorite?(rec.restaurant_id) }) {
                    Label("收藏", systemImage: "heart")
                        .font(.caption)
                        .foregroundColor(.pink)
                }
                Button(action: { onCheckin?(rec.restaurant_id) }) {
                    Label("打卡", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 20)
    }
}
