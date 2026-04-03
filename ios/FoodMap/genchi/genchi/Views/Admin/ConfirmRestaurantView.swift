// 确认店铺视图
// 管理员从候选列表选定店铺后，确认店铺信息并可编辑分类，然后提交入库
// 支持待复核和已复核（二次调整）两种场景

import SwiftUI

struct ConfirmRestaurantView: View {
    let item: ReviewItem
    let candidate: RestaurantCandidate
    @ObservedObject var viewModel: ReviewViewModel
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    // 分类字段可编辑，默认值来自高德映射
    @State private var editableCategory: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(item: ReviewItem, candidate: RestaurantCandidate, viewModel: ReviewViewModel) {
        self.item = item
        self.candidate = candidate
        self.viewModel = viewModel
        _editableCategory = State(initialValue: candidate.category_mapped)
    }

    var body: some View {
        NavigationView {
            Form {
                // ── 店铺信息（只读，来自高德）──
                Section("店铺信息（来自高德）") {
                    LabeledContent("名称", value: candidate.name)
                    LabeledContent("地址", value: candidate.address)
                    LabeledContent("城市", value: candidate.city)
                    LabeledContent("高德分类", value: candidate.category_raw)
                }

                // ── 美食分类（可编辑）──
                Section {
                    TextField("分类（如：火锅、烤肉）", text: $editableCategory)
                        .autocorrectionDisabled()
                } header: {
                    Text("美食分类")
                } footer: {
                    Text("默认来自高德分类映射，可手动修改")
                        .font(.caption)
                }

                // ── 提交按钮 ──
                Section {
                    Button(action: { Task { await submit() } }) {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("确认入库")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.blue)
                    .disabled(isSubmitting || editableCategory.isEmpty)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("确认店铺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await APIService.shared.adminCorrect(
                cacheId: item.id,
                candidate: candidate,
                category: editableCategory,
                userId: authState.userId
            )
            // 二次调整场景：刷新已复核列表
            if viewModel.selectedTab == .reviewed {
                Task { await viewModel.refreshReviewed(userId: authState.userId) }
            } else {
                viewModel.removeFromPending(id: item.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}
