// 问答推荐 ViewModel（v8.0 新增）
// 管理问答推荐流程：获取问题 → 用户回答 → 生成推荐

import Foundation
import SwiftUI

enum QAPhase {
    case loadingQuestions    // 加载问题中
    case answering           // 用户回答问题中
    case loadingResult       // 生成推荐中
    case result              // 展示推荐结果
}

@MainActor
class QARecommendViewModel: ObservableObject {
    @Published var phase: QAPhase = .loadingQuestions
    @Published var questions: [QAQuestion] = []
    @Published var currentQuestionIndex: Int = 0
    @Published var answers: [[String: String]] = []     // [{question, answer}]
    @Published var recommendations: [QARecommendation] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false

    // MARK: - 获取问题

    func fetchQuestions(userId: String, lat: Double, lng: Double) async {
        isLoading = true
        errorMessage = nil
        phase = .loadingQuestions

        do {
            let response = try await APIService.shared.getRecommendQuestions(
                userId: userId, lat: lat, lng: lng
            )
            questions = response.questions
            currentQuestionIndex = 0
            answers = []
            withAnimation { phase = .answering }
        } catch {
            errorMessage = "获取问题失败，请稍后重试"
        }
        isLoading = false
    }

    // MARK: - 回答问题

    func answerQuestion(option: String, userId: String, lat: Double, lng: Double) async {
        guard currentQuestionIndex < questions.count else { return }
        let q = questions[currentQuestionIndex]
        answers.append(["question": q.text, "answer": option])

        if currentQuestionIndex + 1 < questions.count {
            withAnimation { currentQuestionIndex += 1 }
        } else {
            // 所有问题回答完毕，生成推荐
            await fetchResult(userId: userId, lat: lat, lng: lng)
        }
    }

    // MARK: - 生成推荐

    private func fetchResult(userId: String, lat: Double, lng: Double) async {
        isLoading = true
        phase = .loadingResult

        do {
            let response = try await APIService.shared.getRecommendResult(
                userId: userId, lat: lat, lng: lng, answers: answers
            )
            recommendations = response.recommendations
            withAnimation { phase = .result }
        } catch {
            errorMessage = "生成推荐失败，请稍后重试"
        }
        isLoading = false
    }

    func reset() {
        phase = .loadingQuestions
        questions = []
        currentQuestionIndex = 0
        answers = []
        recommendations = []
        errorMessage = nil
    }
}
