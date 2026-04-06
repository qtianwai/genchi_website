// 冷启动博主录入模块 ViewModel
// v14.0 新增：管理员批量录入博主历史美食视频，跳过完整解析，由人工复核添加店铺

import SwiftUI

@MainActor
class ColdStartViewModel: ObservableObject {
    @Published var authors: [ColdStartAuthor] = []
    @Published var total = 0
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private var currentPage = 1
    private var hasMore = true
    // 正在轮询进度的任务 ID 集合
    private var pollingTaskIds: Set<String> = []
    private var pollingTimers: [String: Timer] = [:]

    // MARK: - 加载博主列表

    func loadAuthors(userId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let resp = try await APIService.shared.getColdStartAuthors(page: 1, userId: userId)
            authors = resp.authors
            total = resp.total
            hasMore = resp.authors.count >= resp.page_size
            currentPage = 1
            // 对进行中的任务启动轮询
            startPollingForRunningTasks(userId: userId)
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadMore(userId: String) async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let nextPage = currentPage + 1

        do {
            let resp = try await APIService.shared.getColdStartAuthors(page: nextPage, userId: userId)
            authors.append(contentsOf: resp.authors)
            total = resp.total
            hasMore = resp.authors.count >= resp.page_size
            currentPage = nextPage
        } catch {
            print("[冷启动] 加载更多失败: \(error)")
        }
        isLoading = false
    }

    // MARK: - 提交冷启动任务

    func submit(videoUrl: String, maxCount: Int, userId: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil

        do {
            let resp = try await APIService.shared.coldStartSubmit(
                videoUrl: videoUrl, maxCount: maxCount, userId: userId
            )
            if resp.status == "ok" {
                successMessage = resp.message
                // 刷新列表
                await loadAuthors(userId: userId)
            } else {
                errorMessage = resp.message
            }
        } catch let error as APIError {
            switch error {
            case .serverError(let msg):
                errorMessage = msg
            }
        } catch {
            errorMessage = "提交失败：\(error.localizedDescription)"
        }
        isSubmitting = false
    }

    // MARK: - 轮询进行中的任务

    private func startPollingForRunningTasks(userId: String) {
        // 停止所有旧的轮询
        stopAllPolling()

        for author in authors {
            guard let task = author.task,
                  task.status == "pending" || task.status == "running" else { continue }
            startPolling(taskId: task.task_id, authorId: author.id, userId: userId)
        }
    }

    private func startPolling(taskId: String, authorId: String, userId: String) {
        guard !pollingTaskIds.contains(taskId) else { return }
        pollingTaskIds.insert(taskId)

        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try await APIService.shared.getColdStartTaskStatus(
                        taskId: taskId, userId: userId
                    )
                    // 更新列表中对应博主的任务状态
                    if let idx = self.authors.firstIndex(where: { $0.id == authorId }) {
                        let old = self.authors[idx]
                        let updatedTask = ColdStartTask(
                            task_id: taskId,
                            status: status.status,
                            total_videos: status.total_videos,
                            food_videos_found: status.food_videos_found,
                            new_records_created: status.new_records_created,
                            api_cost: status.api_cost,
                            created_at: old.task?.created_at,
                            completed_at: nil,
                            error_message: status.status == "failed" ? status.message : nil
                        )
                        self.authors[idx] = ColdStartAuthor(
                            id: old.id, name: old.name,
                            avatar_url: old.avatar_url, douyin_uid: old.douyin_uid,
                            task: updatedTask
                        )
                    }
                    // 任务完成或失败时停止轮询
                    if status.status == "completed" || status.status == "failed" {
                        self.stopPolling(taskId: taskId)
                    }
                } catch {
                    print("[冷启动] 轮询任务 \(taskId) 失败: \(error)")
                }
            }
        }
        pollingTimers[taskId] = timer
    }

    private func stopPolling(taskId: String) {
        pollingTimers[taskId]?.invalidate()
        pollingTimers.removeValue(forKey: taskId)
        pollingTaskIds.remove(taskId)
    }

    func stopAllPolling() {
        for (_, timer) in pollingTimers {
            timer.invalidate()
        }
        pollingTimers.removeAll()
        pollingTaskIds.removeAll()
    }

    deinit {
        for (_, timer) in pollingTimers {
            timer.invalidate()
        }
    }
}
