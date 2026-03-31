// 博主列表页面
// 显示用户关注的所有博主，支持取消关注

import SwiftUI

struct AuthorsView: View {
    @EnvironmentObject var authState: AuthState
    @State private var authors: [Author] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if authors.isEmpty {
                    // 空状态
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("还没有关注任何博主")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("粘贴抖音链接后会自动关注对应博主")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(authors) { author in
                            AuthorRow(author: author) {
                                unfollowAuthor(author)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("关注的博主")
            .task { await loadAuthors() }
            .refreshable { await loadAuthors() }
        }
    }

    func loadAuthors() async {
        isLoading = true
        do {
            authors = try await APIService.shared.getFollowingAuthors(userId: authState.userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func unfollowAuthor(_ author: Author) {
        Task {
            try? await APIService.shared.unfollowAuthor(userId: authState.userId, authorId: author.id)
            authors.removeAll { $0.id == author.id }
        }
    }
}

struct AuthorRow: View {
    let author: Author
    let onUnfollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: author.avatar_url ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(author.name)
                    .font(.subheadline).fontWeight(.semibold)
                Text("抖音达人")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onUnfollow) {
                Text("取消关注")
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
