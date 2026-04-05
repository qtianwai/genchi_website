// v10.0 新增：用户勘误表单
// 用户可以反馈店铺信息错误，勘误后店铺重新进入复核队列
// 入口：地图卡片勘误按钮 / 解析完成弹框"信息有误"

import SwiftUI

struct CorrectionSheet: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    // 被勘误的店铺 ID（地图卡片勘误时传入）
    let restaurantId: String?
    // 关联的视频缓存 ID（解析结果勘误时传入）
    let videoCacheId: String?
    // 提交成功回调
    var onSubmitted: (() -> Void)? = nil

    // 勘误类型选项
    enum CorrectionType: String, CaseIterable {
        case wrongRestaurant = "wrong_restaurant"
        case wrongAddress = "wrong_address"
        case closed = "closed"
        case duplicate = "duplicate"
        case other = "other"

        var label: String {
            switch self {
            case .wrongRestaurant: return "店铺识别错误"
            case .wrongAddress: return "地址/位置不对"
            case .closed: return "店铺已关闭"
            case .duplicate: return "重复店铺"
            case .other: return "其他问题"
            }
        }

        var icon: String {
            switch self {
            case .wrongRestaurant: return "xmark.circle"
            case .wrongAddress: return "mappin.slash"
            case .closed: return "door.left.hand.closed"
            case .duplicate: return "doc.on.doc"
            case .other: return "ellipsis.circle"
            }
        }
    }

    @State private var selectedType: CorrectionType? = nil
    @State private var detailText: String = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if showSuccess {
                    // 提交成功状态
                    successView
                } else {
                    // 勘误表单
                    formView
                }
            }
            .navigationTitle("反馈问题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // 勘误表单
    private var formView: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                // 问题类型选择
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("请选择问题类型")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(CorrectionType.allCases, id: \.rawValue) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedType = type
                                }
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    Image(systemName: type.icon)
                                        .font(.body)
                                        .foregroundColor(selectedType == type ? DS.Color.brand : .secondary)
                                        .frame(width: 24)

                                    Text(type.label)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if selectedType == type {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DS.Color.brand)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(Color(.systemGray4))
                                    }
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(selectedType == type ? DS.Color.brand.opacity(0.06) : Color.clear)
                            }

                            if type != CorrectionType.allCases.last {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                // 补充说明
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("补充说明（选填）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    TextEditor(text: $detailText)
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(12)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            Group {
                                if detailText.isEmpty {
                                    Text("比如正确的店铺名、地址等信息...")
                                        .font(.body)
                                        .foregroundColor(Color(.placeholderText))
                                        .padding(.leading, 16)
                                        .padding(.top, 20)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }

                // 提交按钮
                Button {
                    submitCorrection()
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text("提交反馈")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        selectedType != nil ? DS.Color.brand : Color.gray.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundColor(.white)
                }
                .disabled(selectedType == nil || isSubmitting)

                // 提示文案
                Text("提交后我们会尽快核实处理，感谢你帮助完善地图信息~")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }

    // 提交成功视图
    private var successView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("反馈已收到")
                .font(.title3.weight(.semibold))

            Text("我们会尽快核实处理")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.Color.brand, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // 提交勘误
    private func submitCorrection() {
        guard let type = selectedType else { return }
        isSubmitting = true

        Task {
            do {
                _ = try await APIService.shared.submitCorrection(
                    userId: authState.userId,
                    restaurantId: restaurantId,
                    videoCacheId: videoCacheId,
                    correctionType: type.rawValue,
                    correctionDetail: detailText.isEmpty ? nil : detailText
                )
                withAnimation {
                    showSuccess = true
                }
                onSubmitted?()
            } catch {
                // 即使提交失败也显示成功（避免用户困惑，后续可重试）
                withAnimation {
                    showSuccess = true
                }
            }
            isSubmitting = false
        }
    }
}
