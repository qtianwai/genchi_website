// 带内存缓存的异步图片组件
// 解决 AsyncImage 在地图缩放时反复重新加载导致闪烁的问题

import SwiftUI

/// 全局图片内存缓存（NSCache 自动管理内存，无需手动清理）
private final class ImageCacheStore {
    static let shared = ImageCacheStore()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // 最多缓存 200 张图片
        cache.countLimit = 200
    }

    func image(for url: String) -> UIImage? {
        cache.object(forKey: url as NSString)
    }

    func store(_ image: UIImage, for url: String) {
        cache.setObject(image, forKey: url as NSString)
    }
}

/// 带缓存的异步图片视图，避免地图缩放时头像闪烁
/// 使用 .id(url) 确保 URL 变化时视图重建，防止复用残留旧图片
struct CachedAsyncImage: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        // 用 .id(url) 保证 URL 变化时 SwiftUI 销毁旧视图、创建新视图，
        // 内部 @State 随之重置，不会残留上一个店铺的头像
        CachedAsyncImageInner(url: url, size: size)
            .id(url ?? "")
    }
}

/// 内部实现：持有 @State 的真正加载逻辑
private struct CachedAsyncImageInner: View {
    let url: String?
    let size: CGFloat

    @State private var loadedImage: UIImage? = nil
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed || url == nil || url!.isEmpty {
                // 加载失败或无 URL 时不显示任何内容（由调用方提供 placeholder）
                Color.clear
            } else {
                // 加载中：显示透明占位，避免闪烁
                Color.clear
                    .onAppear { loadImage() }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func loadImage() {
        guard let urlString = url, !urlString.isEmpty else {
            loadFailed = true
            return
        }

        // 先查缓存（命中时同步显示，无闪烁）
        if let cached = ImageCacheStore.shared.image(for: urlString) {
            loadedImage = cached
            return
        }

        // 后台下载
        guard let imageURL = URL(string: urlString) else {
            loadFailed = true
            return
        }

        Task.detached(priority: .utility) {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                if let uiImage = UIImage(data: data) {
                    ImageCacheStore.shared.store(uiImage, for: urlString)
                    await MainActor.run {
                        loadedImage = uiImage
                    }
                } else {
                    await MainActor.run {
                        loadFailed = true
                    }
                }
            } catch {
                await MainActor.run {
                    loadFailed = true
                }
            }
        }
    }
}
