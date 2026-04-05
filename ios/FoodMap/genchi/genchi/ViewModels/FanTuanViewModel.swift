// 饭团 ViewModel（v8.0 新增，v10.10 养成体系扩展）
// 管理饭团卡通形象的状态：时间/天气联动、冒泡文案、动画状态、养成数值

import Foundation
import SwiftUI
import Combine

// 饭团的情绪/动作状态
enum FanTuanMood: String, CaseIterable {
    case idle = "idle"              // 默认闲逛
    case hungry = "hungry"          // 饿了（饭点 或 饱食度 20-49）
    case sleepy = "sleepy"          // 犯困（下午）
    case excited = "excited"        // 兴奋（晚饭时间）
    case rainy = "rainy"            // 下雨打伞
    case eating = "eating"          // 吃卡动画
    case happy = "happy"            // 开心（被摸后/奖励反馈）
    case starving = "starving"      // 饿瘪（饱食度 < 20）
    case yawning = "yawning"        // 打哈欠（早上）

    var animation: FanTuanAnimationDescriptor {
        switch self {
        case .idle:
            return .looping(.idle)
        case .hungry:
            return .looping(.hungry)
        case .sleepy, .yawning:
            return .looping(.sleepy)
        case .excited:
            return .looping(.excited)
        case .rainy:
            return .looping(.rainy)
        case .eating:
            return .oneShot(.eating)
        case .happy:
            return .oneShot(.happy)
        case .starving:
            return .looping(.starving)
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
    @Published private var transientAnimation: FanTuanAnimationDescriptor? = nil
    @Published private(set) var animationPlaybackID: Int = 0

    // 天气信息（从后端获取）
    @Published var weather: WeatherInfo?

    // v10.10 养成体系
    @Published var fanTuanStatus: FanTuanStatus?     // 养成数值（饱食度/亲密度等）
    @Published var showPetFeedback: Bool = false      // 摸摸浮动数字动画
    @Published var petFeedbackText: String = ""       // 浮动文字内容
    @Published var showStatusPanel: Bool = false       // 状态面板开关

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

    var currentAnimation: FanTuanAnimationDescriptor {
        transientAnimation ?? mood.animation
    }

    /// 当前饱食度（便捷访问，默认 80）
    var satiety: Int { fanTuanStatus?.satiety ?? 80 }
    /// 当前亲密度等级（便捷访问，默认 1）
    var intimacyLevel: Int { fanTuanStatus?.intimacy_level ?? 1 }
    /// 今日是否已摸摸
    var todayPetted: Bool {
        guard let lastPet = fanTuanStatus?.last_pet_date else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return lastPet == formatter.string(from: Date())
    }

    // MARK: - 时间/天气/养成联动

    /// 根据饱食度、时间和天气更新饭团状态
    func updateMoodForCurrentTime() {
        let hour = Calendar.current.component(.hour, from: Date())

        // v10.10：饱食度优先级最高
        if satiety < 20 {
            mood = .starving
            triggerMealTimeBubble(hour: hour)
            return
        }
        if satiety < 50 {
            mood = .hungry
            triggerMealTimeBubble(hour: hour)
            return
        }

        // 天气优先级次之
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
        }
    }

    /// 饭点冒泡引导（v10.10：根据亲密度等级选择文案语气）
    private func triggerMealTimeBubble(hour: Int) {
        guard bubbleStage == 0 else { return }

        let firstBubble: String
        let level = intimacyLevel

        switch hour {
        case 7...9:
            firstBubble = level >= 3 ? "主人早安～今天想吃什么早餐呀？" : "早安～来杯咖啡配早餐？"
        case 11...13:
            if satiety < 20 {
                firstBubble = level >= 3 ? "主人主人！我快饿扁了，快来喂我！" : "好饿好饿...快点我！"
            } else {
                firstBubble = level >= 3 ? "主人～该吃午饭啦，我帮你选！" : "好饿好饿，快点我！"
            }
        case 14...16:
            firstBubble = level >= 3 ? "主人～下午茶时间到，要不要来点甜的？" : "下午茶时间，来杯奶茶？"
        case 17...19:
            firstBubble = level >= 3 ? "主人主人！晚饭我已经想好了！快来看！" : "晚饭吃什么！我已经想好了！"
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
                let secondBubble = self.intimacyLevel >= 3
                    ? "哼～不理我吗？点我就知道吃什么啦！"
                    : "难道我猜错了？哼～点我就能算出你吃啥！"
                self.showBubbleText(secondBubble)

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.bubbleText = nil
        }
    }

    // MARK: - 定时更新

    private func startMoodTimer() {
        moodTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMoodForCurrentTime()
            }
        }
    }

    // MARK: - 用户交互

    /// 用户短按饭团 → 打开菜单
    func onTap() {
        hideBubble()
        bubbleStage = 0
        bubbleTimer?.invalidate()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
            bounceAnimation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.bounceAnimation = false
        }

        playTransientAnimation(.oneShot(.tap))
        isMenuOpen = true
    }

    /// 切换到吃卡状态（抽卡时未选中的卡被吃掉）
    func startEating() {
        mood = .eating
        playTransientAnimation(.oneShot(.eating))
        restoreMoodAfterTransient()
    }

    /// 触发开心反馈
    func startHappyReaction() {
        mood = .happy
        playTransientAnimation(.oneShot(.happy))
        restoreMoodAfterTransient()
    }

    // MARK: - v10.10 养成体系

    /// 每日登录签到（APP 启动时调用）
    func dailyLogin(userId: String) async {
        guard !userId.isEmpty else { return }
        do {
            let resp = try await APIService.shared.fanTuanLogin(userId: userId)
            fanTuanStatus = resp.fantuan_status
            updateMoodForCurrentTime()
        } catch {
            print("[饭团] 登录签到失败: \(error)")
            // 降级：尝试直接获取状态
            await loadStatus(userId: userId)
        }
    }

    /// 加载养成状态
    func loadStatus(userId: String) async {
        guard !userId.isEmpty else { return }
        do {
            fanTuanStatus = try await APIService.shared.getFanTuanStatus(userId: userId)
            updateMoodForCurrentTime()
        } catch {
            print("[饭团] 加载状态失败: \(error)")
        }
    }

    /// 摸摸饭团（长按触发）
    func petFanTuan(userId: String) async {
        guard !userId.isEmpty else { return }
        do {
            let resp = try await APIService.shared.fanTuanPet(userId: userId)
            fanTuanStatus = resp.fantuan_status

            if resp.already_pet {
                // 今天已摸过，显示冒泡提示
                showBubbleText("今天已经被摸过啦~明天再来嘛")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.hideBubble()
                }
            } else {
                // 播放开心动画 + 浮动数字
                startHappyReaction()
                petFeedbackText = "+\(resp.satiety_change) 饱食度  +\(resp.intimacy_change) 亲密度"
                withAnimation(.easeOut(duration: 0.3)) {
                    showPetFeedback = true
                }
                // 1.5 秒后隐藏浮动数字
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        self.showPetFeedback = false
                    }
                }
            }
            updateMoodForCurrentTime()
        } catch {
            print("[饭团] 摸摸失败: \(error)")
        }
    }

    /// 从其他 API 响应中更新养成状态（抽卡/打卡/收藏后调用）
    func updateStatusFromResponse(_ status: FanTuanStatus) {
        fanTuanStatus = status
        updateMoodForCurrentTime()
    }

    // MARK: - 天气获取

    func fetchWeather(lat: Double, lng: Double) async {
        do {
            let w = try await APIService.shared.getWeather(lat: lat, lng: lng)
            self.weather = w
            updateMoodForCurrentTime()
        } catch {
            print("[饭团] 获取天气失败: \(error)")
        }
    }

    // MARK: - 动画内部

    private func playTransientAnimation(_ animation: FanTuanAnimationDescriptor) {
        transientAnimation = animation
        animationPlaybackID += 1

        guard animation.playback == .playOnce else { return }

        let expectedAnimation = animation
        DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration) {
            guard self.transientAnimation == expectedAnimation else { return }
            self.transientAnimation = nil
            self.animationPlaybackID += 1
        }
    }

    private func restoreMoodAfterTransient() {
        let delay = currentAnimation.duration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.updateMoodForCurrentTime()
        }
    }
}
