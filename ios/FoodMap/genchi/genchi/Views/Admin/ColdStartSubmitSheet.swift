// 冷启动博主录入提交弹窗
// v14.0 新增：管理员粘贴博主示例视频链接 + 设置 max_count，提交冷启动任务

import SwiftUI

struct ColdStartSubmitSheet: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    let onSuccess: () -> Void

    @State private var linkText = ""
    @State private var maxCount = 50
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var normalizedLinkText: String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        // 顶部图标和说明
                        VStack(spacing: DS.Spacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(DS.Color.brand.opacity(0.12))
                                    .frame(width: 68, height: 68)
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(DS.Color.brand)
                            }

                            Text("录入博主视频")
                                .font(.title2.bold())
                            Text("粘贴博主的一条视频链接，系统会自动获取该博主的历史美食视频")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)

                        // 链接输入区域
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("贴上视频链接")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("粘贴该博主的任意一条抖音视频链接")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                TextField("把抖音链接粘贴到这里", text: $linkText, axis: .vertical)
                                    .lineLimit(4)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)

                                if !linkText.isEmpty {
                                    Button(action: { linkText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(14)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DS.Color.separator.opacity(0.14), lineWidth: 0.8)
                            }

                            Button(action: pasteFromClipboard) {
                                Label("从剪贴板带入", systemImage: "doc.on.clipboard")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(DS.Color.brand)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(DS.Color.brand.opacity(0.10), in: Capsule())
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)

                        // 获取数量设置
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("获取视频数量")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("设置获取该博主历史视频的最大数量")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("\(maxCount) 条")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(DS.Color.brand)
                                    .frame(width: 80)

                                Spacer()

                                Stepper("", value: $maxCount, in: 10...200, step: 10)
                                    .labelsHidden()
                            }
                            .padding(14)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DS.Color.separator.opacity(0.14), lineWidth: 0.8)
                            }

                            // 成本预估
                            let estimatedPages = max(1, Int(ceil(Double(maxCount) / 20.0)))
                            let estimatedCost = Double(estimatedPages) * 0.1
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("预估成本：约 \(estimatedPages) 次分页调用 ≈ ¥\(String(format: "%.1f", estimatedCost))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DS.Color.separator.opacity(0.10), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)

                        // 错误提示
                        if let error = errorMessage {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // 成功提示
                        if let success = successMessage {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DS.Color.success)
                                Text(success)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // 提交按钮
                        Button(action: submit) {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isSubmitting ? "提交中..." : "开始录入")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                normalizedLinkText.isEmpty || isSubmitting
                                    ? Color.gray.opacity(0.4)
                                    : DS.Color.brand,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .foregroundColor(.white)
                        }
                        .disabled(normalizedLinkText.isEmpty || isSubmitting)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("录入博主视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // 从剪贴板读取链接
    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            linkText = text
        }
    }

    // 提交冷启动任务
    private func submit() {
        guard !normalizedLinkText.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let resp = try await APIService.shared.coldStartSubmit(
                    videoUrl: normalizedLinkText,
                    maxCount: maxCount,
                    userId: authState.userId
                )
                if resp.status == "ok" {
                    successMessage = resp.message
                    // 短暂延迟后关闭弹窗
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    dismiss()
                    onSuccess()
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
    }
}
