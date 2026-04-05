// 饭团状态面板（v10.10 新增）
// 展示饱食度、亲密度、连续登录天数，提供摸摸按钮

import SwiftUI

struct FanTuanStatusView: View {
    @ObservedObject var viewModel: FanTuanViewModel
    var userId: String

    var body: some View {
        VStack(spacing: 20) {
            // 顶部饭团大号动画
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.orange.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                LottieView(
                    animation: viewModel.currentAnimation,
                    playbackID: viewModel.animationPlaybackID
                )
                .frame(width: 120, height: 120)
                .clipped()
            }
            .padding(.top, 8)

            // 亲密度等级称号
            Text(intimacyTitle)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            // 饱食度
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "fork.knife")
                        .foregroundColor(satietyColor)
                    Text("饱食度")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(viewModel.satiety)/100")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(satietyColor)
                            .frame(width: geo.size.width * CGFloat(viewModel.satiety) / 100.0, height: 10)
                    }
                }
                .frame(height: 10)
            }
            .padding(.horizontal, 24)

            // 亲密度
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                    Text("亲密度")
                        .font(.subheadline.weight(.medium))
                    Text("Lv.\(viewModel.intimacyLevel)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.pink))
                    Spacer()
                    Text("\(viewModel.fanTuanStatus?.intimacy ?? 0)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                // 亲密度进度条（到下一等级）
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.pink.opacity(0.7))
                            .frame(width: geo.size.width * intimacyProgress, height: 10)
                    }
                }
                .frame(height: 10)

                // 下一等级提示
                Text(nextLevelHint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)

            // 连续登录
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("\(viewModel.fanTuanStatus?.consecutive_login_days ?? 0)")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.orange)
                    Text("连续登录")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.08)))

                // 连续登录加成提示
                VStack(spacing: 4) {
                    Text(loginBonusText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                    Text("亲密度加成")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.08)))
            }
            .padding(.horizontal, 24)

            // 摸摸按钮
            Button {
                Task { await viewModel.petFanTuan(userId: userId) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.todayPetted ? "checkmark.circle.fill" : "hand.wave.fill")
                    Text(viewModel.todayPetted ? "今日已摸摸" : "摸摸饭团")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(viewModel.todayPetted ? Color(.systemGray5) : .orange)
                )
                .foregroundColor(viewModel.todayPetted ? .secondary : .white)
            }
            .disabled(viewModel.todayPetted)
            .padding(.horizontal, 24)

            Spacer()
        }
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 计算属性

    // 饱食度颜色：绿(≥50) / 黄(20-49) / 红(<20)
    private var satietyColor: Color {
        let s = viewModel.satiety
        if s >= 50 { return .green }
        if s >= 20 { return .yellow }
        return .red
    }

    // 亲密度等级称号
    private var intimacyTitle: String {
        switch viewModel.intimacyLevel {
        case 1: return "Lv.1 初识 — \"你好呀~\""
        case 2: return "Lv.2 熟悉 — \"主人~\""
        case 3: return "Lv.3 好友 — \"主人主人！\""
        case 4: return "Lv.4 挚友 — \"最爱的主人~\""
        case 5: return "Lv.5 灵魂伴侣 — \"只属于你的饭团！\""
        default: return "Lv.1 初识"
        }
    }

    // 亲密度进度（到下一等级的百分比）
    private var intimacyProgress: CGFloat {
        let intimacy = viewModel.fanTuanStatus?.intimacy ?? 0
        let thresholds = [0, 50, 150, 300, 500]
        let level = viewModel.intimacyLevel
        if level >= 5 { return 1.0 }
        let current = thresholds[level - 1]
        let next = thresholds[level]
        let progress = CGFloat(intimacy - current) / CGFloat(next - current)
        return min(1.0, max(0, progress))
    }

    // 下一等级提示
    private var nextLevelHint: String {
        let intimacy = viewModel.fanTuanStatus?.intimacy ?? 0
        let thresholds = [50, 150, 300, 500]
        let level = viewModel.intimacyLevel
        if level >= 5 { return "已达最高等级" }
        let next = thresholds[level - 1]
        return "距离下一等级还需 \(next - intimacy) 亲密度"
    }

    // 连续登录加成文字
    private var loginBonusText: String {
        let days = viewModel.fanTuanStatus?.consecutive_login_days ?? 0
        return days >= 3 ? "x1.5" : "x1.0"
    }
}
