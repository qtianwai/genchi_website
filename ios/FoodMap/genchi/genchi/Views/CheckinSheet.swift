// 打卡弹窗（v8.0 新增）
// 用户打卡：评分 + 评价文字 + 照片上传

import SwiftUI
import PhotosUI

struct CheckinSheet: View {
    let restaurantId: String
    let restaurantName: String
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int = 0              // 0 = 未评分
    @State private var comment: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var newAchievements: [Achievement] = []
    @State private var showSuccess = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 店铺名
                    Text(restaurantName)
                        .font(.headline)
                        .padding(.top, 8)

                    // 评分（星星）
                    VStack(spacing: 8) {
                        Text("给这家店打个分")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(star <= rating ? .orange : .gray.opacity(0.3))
                                    .onTapGesture { rating = star }
                            }
                        }
                    }

                    // 评价文字
                    VStack(alignment: .leading, spacing: 8) {
                        Text("说点什么（可选）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextEditor(text: $comment)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                            )
                    }

                    // 照片选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("拍张照片（可选）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // 已选照片预览
                                ForEach(photoImages.indices, id: \.self) { index in
                                    Image(uiImage: photoImages[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button(action: {
                                                photoImages.remove(at: index)
                                                if index < selectedPhotos.count {
                                                    selectedPhotos.remove(at: index)
                                                }
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
                                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 3 - photoImages.count, matching: .images) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
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

                    // 成功提示
                    if showSuccess {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.green)
                            Text("打卡成功！")
                                .font(.subheadline.weight(.medium))
                            if !newAchievements.isEmpty {
                                ForEach(newAchievements, id: \.id) { ach in
                                    HStack {
                                        Image(systemName: ach.icon_name ?? "trophy")
                                            .foregroundColor(.orange)
                                        Text("解锁成就：\(ach.name)")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: submitCheckin) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("提交")
                                .fontWeight(.medium)
                        }
                    }
                    .disabled(isSubmitting || showSuccess)
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
        .presentationDetents([.medium, .large])
    }

    // MARK: - 提交打卡

    private func submitCheckin() {
        guard let userId = authState.userId else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                // TODO: 照片上传到 Supabase Storage，获取 URL
                // MVP 阶段先不上传照片，只提交文字
                let response = try await APIService.shared.createCheckin(
                    userId: userId,
                    restaurantId: restaurantId,
                    rating: rating > 0 ? rating : nil,
                    comment: comment.isEmpty ? nil : comment,
                    photoUrls: nil
                )

                newAchievements = response.newly_unlocked_achievements ?? []
                withAnimation { showSuccess = true }

                // 1.5 秒后自动关闭
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                errorMessage = "打卡失败：\(error.localizedDescription)"
            }
            isSubmitting = false
        }
    }
}
