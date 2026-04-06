// 他人地图只读页面（v6.0 新增）
// 展示他人分享的美食地图，支持订阅、查看店铺列表、下拉刷新

import SwiftUI

struct UserMapView: View {
    let targetUserId: String
    @StateObject private var viewModel = UserMapViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var showSubscribeAlert = false
    @State private var isSubscribed = false
    @State private var selectedRestaurant: UserMapRestaurantItem?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 顶部用户信息区
                if let mapInfo = viewModel.mapInfo {
                    VStack(spacing: 12) {
                        // 头像 + 昵称 + 店铺数
                        VStack(spacing: 8) {
                            if let avatarUrl = mapInfo.avatar_url, let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 72, height: 72)
                                }
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 72, height: 72)
                            }

                            Text(mapInfo.nickname)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)

                            Text("共 \(mapInfo.restaurant_count) 家店铺")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }

                        // 订阅/已订阅按钮
                        Button(action: { handleSubscribeToggle() }) {
                            Text(isSubscribed ? "已订阅" : "订阅地图")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(isSubscribed ? Color.gray.opacity(0.2) : Color.orange)
                                .foregroundColor(isSubscribed ? .gray : .white)
                                .cornerRadius(18)
                        }
                        .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
                } else if viewModel.isPrivate {
                    // 私密地图提示
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                        Text("该地图已设为私密")
                            .font(.system(size: 16, weight: .semibold))
                        Text("用户已将此地图设为私密，您无法查看其内容")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(.systemBackground))
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                Divider()

                // 店铺列表
                if !viewModel.isPrivate {
                    if viewModel.restaurants.isEmpty && !viewModel.isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.gray)
                            Text("这张地图还没有店铺")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                    } else {
                        List {
                            ForEach(viewModel.restaurants) { restaurant in
                                NavigationLink(destination: RestaurantDetailView(restaurant: Restaurant(
                                    id: restaurant.id,
                                    name: restaurant.name,
                                    address: restaurant.address,
                                    city: restaurant.city,
                                    latitude: restaurant.latitude,
                                    longitude: restaurant.longitude,
                                    amap_id: nil,
                                    category: restaurant.category,
                                    verified: nil,
                                    avg_price: nil,
                                    photo_url: restaurant.photo_url,
                                    tel: nil
                                ), restaurantId: restaurant.id)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(restaurant.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.black)
                                        if let address = restaurant.address {
                                            Text(address)
                                                .font(.system(size: 13))
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                        if let category = restaurant.category {
                                            Text(category)
                                                .font(.system(size: 12))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await viewModel.loadMapInfo(targetUserId: targetUserId)
                        }
                    }
                }
            }

            // 加载失败提示
            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                        Text("加载失败")
                            .font(.system(size: 14, weight: .semibold))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Button(action: { Task { await viewModel.loadMapInfo(targetUserId: targetUserId) } }) {
                            Text("重试")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .padding(16)
                    Spacer()
                }
                .background(Color.black.opacity(0.3))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadMapInfo(targetUserId: targetUserId)
            }
        }
    }

    private func handleSubscribeToggle() {
        if isSubscribed {
            // 取消订阅
            showSubscribeAlert = true
        } else {
            // 订阅
            Task {
                do {
                    try await viewModel.subscribeMap(targetUserId: targetUserId)
                    isSubscribed = true
                } catch {
                    viewModel.errorMessage = "订阅失败：\(error.localizedDescription)"
                }
            }
        }
    }
}


#Preview {
    NavigationStack {
        UserMapView(targetUserId: "test-user-id")
    }
}
