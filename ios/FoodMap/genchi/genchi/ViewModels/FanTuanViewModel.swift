// 饭团 ViewModel（v8.0 新增）
// 管理饭团卡通形象的状态：时间/天气联动、冒泡文案、动画状态

import Foundation
import SwiftUI
import Combine

// 饭团的情绪/动作状态
enum FanTuanMood: String, CaseIterable {
    case idle = "idle"              // 默认闲逛
    case hungry = "hungry"          // 饿了（饭点）
    case sleepy = "sleepy"          // 犯困（下午）
    case excited = "excited"        // 兴奋（晚饭时间）
    case rainy = "rainy"            // 下雨打伞
    case eating = "eating"          // 吃卡动画
    case yawning = "yawning"        // 打哈欠（早上）

    // 对应的 SF Symbol 图标（MVP 阶段用 SF Symbol 代替 AI 生成形象）
    var sfSymbol: String {
        switch self {
        case .idle: return "face.smiling"
        case .hungry: return "fork.knife"
        case .sleepy: return "moon.zzz"
        case .excited: return "star.fill"
        case .rainy: return "umbrella.fill"
        case .eating: return "mouth.fill"
        case .yawning: return "sun.haze"
        }
    }

    // 饭团表情 Emoji（序列帧动画的简化替代）
    var emoji: String {
        switch self {
        case .idle: return "🍙"
        case .hungry: return "🤤"
        case .sleepy: return "😴"
        case .excited: return "🤩"
        case .rainy: return "☔"
        case .eating: return "😋"
        case .yawning: return "🥱"
        }
    }
}

@MainActor
class FanTuanViewModel: ObservableObject {
    // 当前状态
    @Published var mood: FanTuanMood = .idle
    @Published var bubbleText: String? = nil        // 冒泡文案（nil 时不显示）
    @Published var showBubble: Bool = false          // 是否显示冒泡
    @Published var isMenuOpen: Bool = false          // 是否打开能力菜单
    @Published var bounceAnimation: Bool = false     // 弹跳动画触发

    // 天气信息（从后端获取）
    @Published var weather: WeatherInfo?

    // 冒泡引导阶段
    private var bubbleStage: Int = 0  // 0=未触发, 1=第一轮, 2=第二轮
    private var bubbleTimer: Timer?
    private var moodTimer: Timer?

    init() {
        updateMoodForCurrentTime()
        startMoodTimer()
    }

    deinit {
        bubbleTimer?.invalidate()
        moodTimer?.invalidate()
    }

    // MARK: - 时间/天气联动

    /// 根据当前时间和天气更新饭团状态
    func updateMoodForCurrentTime() {
        let hour = Calendar.current.component(.hour, from: Date())

        // 天气优先级最高
        if let w = weather, w.category == "rainy" {
            mood = .rainy
            triggerMealTimeBubble(hour: hour)
            return
        }

        // 时间段联动
        switch hour {
        case 7...9:
            mood = .yawning
            triggerMealTimeBubble(hour: hour)
        case 11...13:
            mood = .hungry
            triggerMealTimeBubble(hour: hour)
        case 14...16:
            mood = .sleepy
            triggerMealTimeBubble(hour: hour)
        case 17...19:
            mood = .excited
            triggerMealTimeBubble(hour: hour)
        default:
            mood = .idle
            // 非饭点不主动冒泡
        }
    }

    /// 饭点冒泡引导
    private func triggerMealTimeBubble(hour: Int) {
        guard bubbleStage == 0 else { return }

        // 第一轮：精准预测风格
        let firstBubble: String
        switch hour {
        case 7...9:
            firstBubble = "早安～来杯咖啡配早餐？"
        case 11...13:
            firstBubble = "好饿好饿，快点我！"
        case 14...16:
            firstBubble = "下午茶时间，来杯奶茶？"
        case 17...19:
            firstBubble = "晚饭吃什么！我已经想好了！"
        default:
            return
        }

        bubbleStage = 1
        showBubbleText(firstBubble)

        // 10 秒后如果用户没点击，显示第二轮
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.bubbleStage == 1 else { return }
                self.bubbleStage = 2
                self.showBubbleText("难道我猜错了？哼～点我就能算出你吃啥！")

                // 再过 8 秒自动隐藏
                self.bubbleTimer?.invalidate()
                self.bubbleTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
                    Task { @MainActor in
                        self.hideBubble()
                    }
                }
            }
        }
    }

    /// 显示冒泡文案
    private func showBubbleText(_ text: String) {
        bubbleText = text
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            showBubble = true
        }
    }

    /// 隐藏冒泡
    func hideBubble() {
        withAnimation(.easeOut(duration: 0.3)) {
            showBubble = false
        }
        // 延迟清空文案（等动画结束）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.bubbleText = nil
        }
    }

    // MARK: - 定时更新

    /// 每 5 分钟检查一次时间，更新饭团状态
    private func startMoodTimer() {
        moodTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMoodForCurrentTime()
            }
        }
    }

    // MARK: - 用户交互

    /// 用户点击饭团
    func onTap() {
        // 隐藏冒泡
        hideBubble()
        bubbleStage = 0
        bubbleTimer?.invalidate()

        // 触发弹跳动画
        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
            bounceAnimation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.bounceAnimation = false
        }

        // 打开能力菜单
        isMenuOpen = true
    }

    /// 切换到吃卡状态（抽卡时未选中的卡被吃掉）
    func startEating() {
        mood = .eating
        // 1.5 秒后恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.updateMoodForCurrentTime()
        }
    }

    // MARK: - 天气获取

    /// 获取天气信息
    func fetchWeather(lat: Double, lng: Double) async {
        do {
            let w = try await APIService.shared.getWeather(lat: lat, lng: lng)
            self.weather = w
            updateMoodForCurrentTime()
        } catch {
            print("[饭团] 获取天气失败: \(error)")
        }
    }
}
