// 地图订阅管理页面（v6.0 新增）
// 管理用户订阅的其他用户地图，支持开关控制和左滑删除

import SwiftUI

struct MapSubscriptionsView: View {
    let userId: String
    @StateObject private var viewModel = MapSubscriptionsViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirm = false
    @State private var deleteTargetId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.subscriptions.isEmpty && !viewModel.isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("还没有订阅任何地图")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                        Text("订阅其他用户的地图，在你的地图上看到他们推荐的店铺")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    List {
                        ForEach(viewModel.subscriptions) { subscription in
                            HStack(spacing: 12) {
                                // 头像
                                if let avatarUrl = subscription.avatar_url, let url = URL(string: avatarUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 46, height: 46)
                                            .clipShape(Circle())
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 46, height: 46)
                                    }
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 46, height: 46)
                                }

                                // 昵称
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subscription.nickname)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.black)
                                    if let createdAt = subscription.created_at {
                                        Text("订阅于 \(formatDate(createdAt))")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }

                                Spacer()

                                // 开关
                                Toggle("", isOn: Binding(
                                    get: { subscription.is_enabled },
                                    set: { newValue in
                                        Task {
                                            await viewModel.toggleSubscription(
                                                subscriberId: userId,
                                                targetUserId: subscription.target_user_id,
                                                isEnabled: newValue
                                            )
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            .contentShape(Rectangle())
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteTargetId = subscription.target_user_id
                                    showDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .background(Color(.systemBackground))
                }

                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .navigationTitle("订阅管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.black)
                    }
                }
            }
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    if let targetId = deleteTargetId {
                        Task {
                            await viewModel.unsubscribe(subscriberId: userId, targetUserId: targetId)
                        }
                    }
                }
            } message: {
                Text("取消订阅后，该用户推荐的店铺将从你的地图上消失")
            }
            .onAppear {
                Task {
                    await viewModel.loadSubscriptions(userId: userId)
                }
            }
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MM月dd日"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}


#Preview {
    MapSubscriptionsView(userId: "test-user-id")
}
