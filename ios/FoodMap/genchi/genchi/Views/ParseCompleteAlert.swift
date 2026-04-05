// v10.0 新增：解析完成弹框
// 异步解析完成后弹出，展示结果并提供操作入口
// 成功时可一键定位到店铺或反馈错误；失败时友好提示后台会人工复核

import SwiftUI
import CoreLocation

struct ParseCompleteAlert: View {
    // 解析结果
    let result: ParseResultResponse
    // 关闭弹框
    let onDismiss: () -> Void
    // 定位到店铺（传入坐标）
    let onLocateRestaurant: ((CLLocationCoordinate2D) -> Void)?
    // 打开勘误表单
    let onReportError: (() -> Void)?

    var body: some View {
        ZStack {
            // 半透明遮罩
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // 弹框卡片
            VStack(spacing: DS.Spacing.lg) {
                if result.status == "completed", let restaurant = result.restaurant {
                    // ── 成功：识别到店铺 ──
                    successContent(restaurant: restaurant)
                } else {
                    // ── 失败：未识别到店铺 ──
                    failedContent()
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // 成功内容
    @ViewBuilder
    private func successContent(restaurant: RestaurantResult) -> some View {
        // 标题
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
            Text("店铺识别成功")
                .font(.headline)
        }

        // 店铺信息卡片
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "storefront")
                    .foregroundColor(DS.Color.brand)
                Text(restaurant.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            if let address = restaurant.address, !address.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "mappin")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: DS.Radius.sm))

        // 操作按钮
        HStack(spacing: DS.Spacing.md) {
            // 定位到店铺
            Button {
                if let coord = restaurant.coordinate {
                    onLocateRestaurant?(coord)
                }
                onDismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                    Text("定位到店铺")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DS.Color.brand, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.white)
            }

            // 信息有误
            Button {
                onDismiss()
                // 延迟一下再弹勘误，避免动画冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onReportError?()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble")
                    Text("信息有误")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.secondary)
            }
        }
    }

    // 失败内容
    @ViewBuilder
    private func failedContent() -> some View {
        // 图标
        Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 36))
            .foregroundColor(DS.Color.brand.opacity(0.7))

        // 标题
        Text("视频已收录")
            .font(.headline)

        // 说明文案
        Text("暂时没有识别到店铺，不用担心~\n后台会尽快人工复核，复核后店铺会自动出现在你的地图上")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)

        // 知道了按钮
        Button {
            onDismiss()
        } label: {
            Text("知道了")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DS.Color.brand, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.white)
        }
    }
}
