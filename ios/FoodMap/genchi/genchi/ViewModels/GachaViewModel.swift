// 抽卡 ViewModel（v8.0 新增）
// 管理抽卡流程：API 调用、次数管理、连续换一批计数、插入提问

import Foundation
import SwiftUI

// 抽卡流程状态
enum GachaPhase {
    case loading            // 加载中（调用 AI）
    case cardsFaceDown      // 6 张卡背面朝上，等待用户选择
    case revealing          // 翻牌动画中
    case result             // 展示抽中的卡片详情
    case eaten              // 未选中的卡被饭团吃掉
}

@MainActor
class GachaViewModel: ObservableObject {
    // 抽卡状态
    @Published var phase: GachaPhase = .loading
    @Published var cards: [GachaCard] = []
    @Published var selectedCardIndex: Int? = nil     // 用户选中的卡片索引
    @Published var sessionId: String = ""
    @Published var remaining: Int = 0                // 今日剩余次数

    // 连续换一批计数（达到阈值后插入提问）
    @Published var consecutiveDrawCount: Int = 0
    @Published var showInsertedQuestion: Bool = false
    @Published var insertedQuestionAnswers: [[String: String]] = []

    // 错误和加载状态
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false

    // 新解锁的成就（选卡后返回）
    @Published var newlyUnlockedAchievements: [Achievement] = []
    @Published var showAchievementToast: Bool = false

    // 饭团吃卡动画状态
    @Published var eatenCardIndices: Set<Int> = []

    // 配置
    private let insertQAThreshold = 3  // 连续换一批 N 次后插入提问

    // MARK: - 抽卡流程

    /// 执行一次抽卡
    func draw(userId: String, lat: Double, lng: Double) async {
        isLoading = true
        errorMessage = nil
        phase = .loading
        selectedCardIndex = nil
        eatenCardIndices = []

        do {
            let response = try await APIService.shared.gachaDraw(
                userId: userId,
                lat: lat,
                lng: lng,
                qaAnswers: insertedQuestionAnswers.isEmpty ? nil : insertedQuestionAnswers
            )
            cards = response.cards
            sessionId = response.session_id
            remaining = response.remaining
            consecutiveDrawCount += 1
            insertedQuestionAnswers = []

            // 切换到卡片展示
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                phase = .cardsFaceDown
            }
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "抽卡失败，请稍后重试"
        }

        isLoading = false
    }

    /// 用户选中某张卡片
    func selectCard(at index: Int, userId: String) async {
        guard index < cards.count else { return }
        selectedCardIndex = index

        // 翻牌动画
        withAnimation(.easeInOut(duration: 0.6)) {
            phase = .revealing
        }

        // 0.8 秒后，未选中的卡被饭团吃掉
        try? await Task.sleep(nanoseconds: 800_000_000)

        // 逐张吃掉动画
        for i in 0..<cards.count where i != index {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(Double(eatenCardIndices.count) * 0.1)) {
                eatenCardIndices.insert(i)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // 吃完后切换到结果页
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            phase = .result
        }

        // 后台记录选择
        let card = cards[index]
        do {
            let response = try await APIService.shared.gachaSelect(
                userId: userId,
                sessionId: sessionId,
                restaurantId: card.restaurant_id
            )
            if let achievements = response.newly_unlocked_achievements, !achievements.isEmpty {
                newlyUnlockedAchievements = achievements
                showAchievementToast = true
            }
        } catch {
            print("[抽卡] 记录选择失败: \(error)")
        }
    }

    /// 再抽一次（换一批）
    func drawAgain(userId: String, lat: Double, lng: Double) async {
        // 检查是否需要插入提问
        if consecutiveDrawCount >= insertQAThreshold && !showInsertedQuestion {
            showInsertedQuestion = true
            return
        }

        showInsertedQuestion = false
        await draw(userId: userId, lat: lat, lng: lng)
    }

    /// 获取今日剩余次数
    func fetchRemaining(userId: String) async {
        do {
            let response = try await APIService.shared.getGachaRemaining(userId: userId)
            remaining = response.remaining
        } catch {
            print("[抽卡] 获取剩余次数失败: \(error)")
        }
    }

    /// 重置状态（关闭抽卡页时）
    func reset() {
        phase = .loading
        cards = []
        selectedCardIndex = nil
        sessionId = ""
        consecutiveDrawCount = 0
        showInsertedQuestion = false
        insertedQuestionAnswers = []
        eatenCardIndices = []
        errorMessage = nil
        newlyUnlockedAchievements = []
        showAchievementToast = false
    }

    // MARK: - 辅助

    /// 选中的卡片
    var selectedCard: GachaCard? {
        guard let index = selectedCardIndex, index < cards.count else { return nil }
        return cards[index]
    }
}
