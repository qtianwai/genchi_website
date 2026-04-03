// 手动添加店铺弹窗
// 当 AI 无法识别店铺时，允许用户手动输入店铺名称和城市

import SwiftUI

struct ManualAddRestaurantSheet: View {
    let videoUrl: String
    let authorName: String
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    let onSuccess: () -> Void

    @State private var restaurantName = ""
    @State private var selectedCity = "上海"
    @State private var category = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    let cities = ["上海", "北京", "广州", "深圳", "杭州", "成都", "重庆", "西安", "武汉", "南京", "苏州", "厦门"]
    let categories = ["火锅", "烤肉", "川菜", "粤菜", "日料", "西餐", "咖啡", "甜品", "小吃", "其他"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // ── 说明文字 ──
                    VStack(spacing: 6) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("手动添加店铺")
                            .font(.title2).fontWeight(.bold)
                        Text("AI 未能识别到店铺，请手动输入店铺信息\n您的贡献将帮助其他用户")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // ── 博主信息提示 ──
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.gray)
                        Text("博主：\(authorName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)

                    // ── 表单 ──
                    VStack(alignment: .leading, spacing: 16) {
                        // 店铺名称
                        VStack(alignment: .leading, spacing: 6) {
                            Text("店铺名称 *")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            TextField("请输入店铺名称", text: $restaurantName)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // 所在城市
                        VStack(alignment: .leading, spacing: 6) {
                            Text("所在城市 *")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Picker("城市", selection: $selectedCity) {
                                ForEach(cities, id: \.self) { city in
                                    Text(city).tag(city)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // 美食分类（可选）
                        VStack(alignment: .leading, spacing: 6) {
                            Text("美食分类（可选）")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Picker("分类", selection: $category) {
                                Text("请选择").tag("")
                                ForEach(categories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 20)

                    // ── 错误提示 ──
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 20)
                    }

                    // ── 成功提示 ──
                    if let success = successMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(success)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 30)

                    // ── 提交按钮 ──
                    Button(action: submitRestaurant) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isLoading ? "正在添加..." : "提交")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? Color.orange : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canSubmit || isLoading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    var canSubmit: Bool {
        !restaurantName.trimmingCharacters(in: .whitespaces).isEmpty &&
        restaurantName.count >= 2
    }

    func submitRestaurant() {
        guard canSubmit else { return }

        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let response = try await APIService.shared.manualAddRestaurant(
                    videoUrl: videoUrl,
                    userId: authState.userId,
                    restaurantName: restaurantName.trimmingCharacters(in: .whitespaces),
                    city: selectedCity,
                    category: category
                )

                successMessage = response.message
                onSuccess()

                // 延迟 1.5 秒后自动关闭
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
