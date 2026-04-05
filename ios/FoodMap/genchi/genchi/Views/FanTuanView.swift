// 饭团浮动组件（v8.0 新增）
// 固定在地图页右下角，带微动画和冒泡文案引导
// MVP 阶段用 SF Symbol + Emoji 代替 AI 生成形象

import SwiftUI

struct FanTuanView: View {
    @ObservedObject var viewModel: FanTuanViewModel

    // 持续微动画：轻微上下浮动
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
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
                // 背景光晕（稀有度视觉反馈用，默认不显示）
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
                    // 底色圆
                    Circle()
                        .fill(.white)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                    // 饭团表情
                    Text(viewModel.mood.emoji)
                        .font(.system(size: 32))
                }
                .scaleEffect(viewModel.bounceAnimation ? 1.2 : 1.0)
                .offset(y: floatOffset)
            }
            .onTapGesture {
                viewModel.onTap()
            }
        }
        .onAppear {
            startFloatAnimation()
        }
    }

    // MARK: - 浮动动画

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
    var onSelectGacha: () -> Void
    var onSelectQA: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Text("🍙")
                    .font(.title)
                Text("饭团能帮你做什么？")
                    .font(.headline)
                Spacer()
            }
            .padding(.top, 8)

            // 能力卡片
            Button(action: {
                dismiss()
                onSelectGacha()
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.orange.opacity(0.1))
                            .frame(width: 48, height: 48)
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("干饭抽卡")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text("摇一摇，随机抽出今天的美食命运")
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

            Button(action: {
                dismiss()
                onSelectQA()
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue.opacity(0.1))
                            .frame(width: 48, height: 48)
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("智能问答")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text("回答几个问题，精准匹配你的口味")
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

            Spacer()
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}
