// 饭团浮动组件（v8.0 新增，v10.10 养成体系扩展）
// 固定在地图页右下角，带微动画和冒泡文案引导
// v10.10：新增长按摸摸手势 + 浮动数字动画

import SwiftUI

struct FanTuanView: View {
    @ObservedObject var viewModel: FanTuanViewModel
    // 摸摸需要 userId
    var userId: String = ""

    // 持续微动画：轻微上下浮动
    @State private var floatOffset: CGFloat = 0
    // 浮动数字动画偏移
    @State private var feedbackOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // v10.10 摸摸浮动数字反馈
            if viewModel.showPetFeedback {
                Text(viewModel.petFeedbackText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white).shadow(color: .black.opacity(0.1), radius: 3))
                    .offset(y: feedbackOffset)
                    .opacity(viewModel.showPetFeedback ? 1 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        feedbackOffset = 0
                        withAnimation(.easeOut(duration: 1.2)) {
                            feedbackOffset = -30
                        }
                    }
                    .onDisappear {
                        feedbackOffset = 0
                    }
            }

            // 冒泡文案
            if viewModel.showBubble, let text = viewModel.bubbleText {
                BubbleView(text: text)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .onTapGesture {
                        viewModel.onTap()
                    }
            }

            // 饭团本体
            ZStack {
                // 背景光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.orange.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
                    .frame(width: 70, height: 70)

                // 饭团主体
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.96))
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                    LottieView(
                        animation: viewModel.currentAnimation,
                        playbackID: viewModel.animationPlaybackID
                    )
                    .frame(width: 52, height: 52)
                    .clipped()
                    .id("\(viewModel.currentAnimation.name)-\(viewModel.animationPlaybackID)")
                    .transition(.opacity)
                }
                .scaleEffect(viewModel.bounceAnimation ? 1.2 : 1.0)
                .offset(y: floatOffset)
            }
            // v10.10：短按打开菜单，长按摸摸饭团
            .onTapGesture {
                viewModel.onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                // 长按触发摸摸
                Task {
                    await viewModel.petFanTuan(userId: userId)
                }
            }
        }
        .onAppear {
            startFloatAnimation()
        }
    }

    private func startFloatAnimation() {
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            floatOffset = -6
        }
    }
}

// MARK: - 冒泡文案视图

struct BubbleView: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )

            // 小三角箭头
            Triangle()
                .fill(.white)
                .frame(width: 12, height: 6)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .padding(.bottom, 4)
    }
}

// 小三角形状
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 饭团能力菜单

struct FanTuanMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FanTuanViewModel
    var userId: String
    var onSelectGacha: () -> Void
    var onSelectQA: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                FanTuanStickerView(asset: .happy)
                    .frame(width: 28, height: 28)
                Text("饭团能帮你做什么？")
                    .font(.headline)
                Spacer()
            }
            .padding(.top, 8)

            // 干饭抽卡
            Button(action: {
                dismiss()
                onSelectGacha()
            }) {
                menuCard(icon: "sparkles", color: .orange, title: "干饭抽卡", subtitle: "摇一摇，随机抽出今天的美食命运")
            }

            // 智能问答
            Button(action: {
                dismiss()
                onSelectQA()
            }) {
                menuCard(icon: "bubble.left.and.bubble.right", color: .blue, title: "智能问答", subtitle: "回答几个问题，精准匹配你的口味")
            }

            // v10.10 饭团状态
            Button(action: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    viewModel.showStatusPanel = true
                }
            }) {
                menuCard(
                    icon: "heart.fill", color: .pink,
                    title: "饭团状态",
                    subtitle: "饱食度 \(viewModel.satiety)  亲密度 Lv.\(viewModel.intimacyLevel)"
                )
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    // 菜单卡片通用组件
    private func menuCard(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
    }
}
