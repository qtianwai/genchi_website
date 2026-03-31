// 解析抖音链接的底部弹窗
// 用户粘贴抖音链接后，调用后端解析并展示结果

import SwiftUI

struct ParseLinkSheet: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    let onSuccess: () -> Void

    @State private var linkText = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var result: ParseLinkResponse? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // ── 说明文字 ──
                VStack(spacing: 6) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("粘贴抖音链接")
                        .font(.title2).fontWeight(.bold)
                    Text("从抖音复制博主视频链接，粘贴到下方\nAI 将自动识别推荐的店铺")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // ── 链接输入框 ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("粘贴抖音链接...", text: $linkText, axis: .vertical)
                            .lineLimit(3)
                            .padding(12)
                        if !linkText.isEmpty {
                            Button(action: { linkText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .padding(.trailing, 12)
                        }
                    }
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // 快速粘贴按钮（从剪贴板读取）
                    Button(action: pasteFromClipboard) {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                            .font(.caption)
                            .foregroundColor(.orange)
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

                // ── 解析结果 ──
                if let result = result {
                    ParseResultView(result: result)
                        .padding(.horizontal, 20)
                }

                Spacer()

                // ── 解析按钮 ──
                Button(action: parseLink) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "正在解析..." : "开始解析")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(linkText.isEmpty || isLoading ? Color.gray.opacity(0.4) : Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(linkText.isEmpty || isLoading)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // 从剪贴板读取链接
    func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            linkText = text
        }
    }

    // 调用后端解析链接
    func parseLink() {
        guard !linkText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        result = nil

        Task {
            do {
                let response = try await APIService.shared.parseDouyinLink(
                    url: linkText.trimmingCharacters(in: .whitespaces),
                    userId: authState.userId
                )
                result = response
                onSuccess()  // 通知地图刷新
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// ─────────────────────────────────────────
// 解析结果展示
// ─────────────────────────────────────────
struct ParseResultView: View {
    let result: ParseLinkResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 博主信息
            HStack(spacing: 10) {
                AsyncImage(url: URL(string: result.author.avatar_url ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.author.name)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(result.status == "cached" ? "已有数据，直接加载" : "新解析完成")
                        .font(.caption)
                        .foregroundColor(result.status == "cached" ? .blue : .green)
                }
                Spacer()
                // 店铺数量徽章
                Text("\(result.restaurants.count) 家店铺")
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 店铺列表（最多显示 5 条）
            if !result.restaurants.isEmpty {
                Text("识别到的店铺")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(result.restaurants.prefix(5)) { restaurant in
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(restaurant.name)
                                .font(.caption).fontWeight(.medium)
                            if let address = restaurant.address {
                                Text(address)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let category = restaurant.category {
                            Text(category)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if result.restaurants.count > 5 {
                    Text("还有 \(result.restaurants.count - 5) 家店铺已添加到地图")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
