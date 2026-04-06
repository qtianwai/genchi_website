// 提交反馈弹窗（v15.0 新增）
// 用户选择分类、输入文字、上传截图，自动采集设备上下文

import SwiftUI
import PhotosUI

struct FeedbackSubmitSheet: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    let onSuccess: () -> Void

    // 分类选项
    @State private var selectedCategory = "bug_report"
    // 反馈内容
    @State private var content = ""
    // 截图
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    // 状态
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    // 分类列表
    private let categories: [(String, String)] = [
        ("bug_report", "Bug报告"),
        ("feature_request", "功能建议"),
        ("other", "其他"),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if showSuccess {
                    // 提交成功视图
                    VStack(spacing: DS.Spacing.lg) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(DS.Color.success)
                        Text("反馈已提交")
                            .font(.headline)
                        Text("我们会尽快处理，感谢你的反馈")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: DS.Spacing.xl) {
                            // 分类选择
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                Text("反馈类型")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Picker("反馈类型", selection: $selectedCategory) {
                                    ForEach(categories, id: \.0) { cat in
                                        Text(cat.1).tag(cat.0)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            // 反馈内容
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                HStack {
                                    Text("问题描述")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(content.count)/1000")
                                        .font(.caption2)
                                        .foregroundColor(content.count > 1000 ? .red : .secondary)
                                }
                                TextEditor(text: $content)
                                    .frame(minHeight: 120)
                                    .padding(DS.Spacing.sm)
                                    .background(
                                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                                            .fill(Color(.systemGray6))
                                    )
                            }

                            // 截图选择（复用 CheckinSheet 的照片选择 UI）
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                Text("截图（可选，最多3张）")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: DS.Spacing.sm) {
                                        // 已选照片预览
                                        ForEach(photoImages.indices, id: \.self) { index in
                                            Image(uiImage: photoImages[index])
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 80, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                                                .overlay(alignment: .topTrailing) {
                                                    Button(action: {
                                                        photoImages.remove(at: index)
                                                    }) {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .font(.caption)
                                                            .foregroundColor(.white)
                                                            .background(Circle().fill(.black.opacity(0.5)))
                                                    }
                                                    .offset(x: 4, y: -4)
                                                }
                                        }

                                        // 添加照片按钮
                                        if photoImages.count < 3 {
                                            PhotosPicker(
                                                selection: $selectedPhotos,
                                                maxSelectionCount: 3 - photoImages.count,
                                                matching: .images
                                            ) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                                                        .fill(Color(.systemGray6))
                                                        .frame(width: 80, height: 80)
                                                    Image(systemName: "plus")
                                                        .font(.title3)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 错误信息
                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            // 提交按钮
                            Button(action: submitFeedback) {
                                HStack {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(isSubmitting ? "提交中..." : "提交反馈")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.md)
                                .background(canSubmit ? DS.Color.brand : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(DS.Radius.md)
                            }
                            .disabled(!canSubmit || isSubmitting)
                        }
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.lg)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("提交反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .onChange(of: selectedPhotos) { newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photoImages.append(image)
                    }
                }
                selectedPhotos = []
            }
        }
    }

    // 是否可以提交
    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.count <= 1000
    }

    // MARK: - 提交反馈

    private func submitFeedback() {
        guard canSubmit, !authState.userId.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                // 将 UIImage 转为 JPEG Data
                let imageDataList = photoImages.compactMap { $0.jpegData(compressionQuality: 0.8) }

                try await APIService.shared.submitFeedback(
                    userId: authState.userId,
                    category: selectedCategory,
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    images: imageDataList,
                    deviceModel: DeviceContext.deviceModel,
                    iosVersion: DeviceContext.iosVersion,
                    appVersion: DeviceContext.appVersion
                )

                withAnimation { showSuccess = true }
                // 1.5 秒后自动关闭
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                onSuccess()
                dismiss()
            } catch {
                errorMessage = "提交失败：\(error.localizedDescription)"
            }
            isSubmitting = false
        }
    }
}
