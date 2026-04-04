import SwiftUI

enum FavoritesTheme {
    static let background = Color(.systemGroupedBackground)
    static let surface = DS.Color.surface
    static let surfaceElevated = DS.Color.surfaceAlt
    static let border = DS.Color.separator.opacity(0.10)
    static let separator = DS.Color.separator.opacity(0.12)
    static let title = Color.primary
    static let body = Color.primary
    static let secondary = Color.secondary
    static let tertiary = Color.secondary.opacity(0.75)
    static let accent = DS.Color.brand
    static let accentSoft = accent.opacity(0.14)
    static let note = DS.Color.brand
    static let nav = DS.Color.info
    static let avoid = DS.Color.danger
    static let purple = Color(red: 0.82, green: 0.32, blue: 0.98)
    static let overlay = LinearGradient(
        colors: [
            Color.white.opacity(0.65),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct RestaurantDestination: Identifiable, Hashable {
    let restaurant: Restaurant
    let restaurantId: String

    var id: String { restaurantId }
}

extension Notification.Name {
    static let restaurantStateDidChange = Notification.Name("restaurantStateDidChange")
}

struct RestaurantStateChange {
    let restaurantId: String
    let isFavorited: Bool?
    let isAvoided: Bool?
    let favoriteNote: String?
    let isDeleted: Bool

    private static let restaurantIdKey = "restaurantId"
    private static let isFavoritedKey = "isFavorited"
    private static let isAvoidedKey = "isAvoided"
    private static let favoriteNoteKey = "favoriteNote"
    private static let isDeletedKey = "isDeleted"

    init(
        restaurantId: String,
        isFavorited: Bool?,
        isAvoided: Bool?,
        favoriteNote: String?,
        isDeleted: Bool
    ) {
        self.restaurantId = restaurantId
        self.isFavorited = isFavorited
        self.isAvoided = isAvoided
        self.favoriteNote = favoriteNote
        self.isDeleted = isDeleted
    }

    func post() {
        var userInfo: [String: Any] = [
            Self.restaurantIdKey: restaurantId,
            Self.isDeletedKey: isDeleted
        ]
        if let isFavorited {
            userInfo[Self.isFavoritedKey] = isFavorited
        }
        if let isAvoided {
            userInfo[Self.isAvoidedKey] = isAvoided
        }
        if let favoriteNote {
            userInfo[Self.favoriteNoteKey] = favoriteNote
        }
        NotificationCenter.default.post(
            name: .restaurantStateDidChange,
            object: nil,
            userInfo: userInfo
        )
    }

    init?(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let restaurantId = userInfo[Self.restaurantIdKey] as? String
        else {
            return nil
        }
        self.restaurantId = restaurantId
        self.isFavorited = userInfo[Self.isFavoritedKey] as? Bool
        self.isAvoided = userInfo[Self.isAvoidedKey] as? Bool
        self.favoriteNote = userInfo[Self.favoriteNoteKey] as? String
        self.isDeleted = userInfo[Self.isDeletedKey] as? Bool ?? false
    }
}

struct FavoritesPageModifier: ViewModifier {
    let includeTabBar: Bool

    func body(content: Content) -> some View {
        let base = content
            .scrollContentBackground(.hidden)
            .background(FavoritesTheme.background.ignoresSafeArea())
            .toolbarBackground(FavoritesTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(FavoritesTheme.accent)

        if includeTabBar {
            base
                .toolbarBackground(FavoritesTheme.surface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.light, for: .tabBar)
        } else {
            base
        }
    }
}

struct FavoritesMinimalBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(FavoritesTheme.body)
                    }
                }
            }
    }
}

extension View {
    func favoritesPageChrome(includeTabBar: Bool = false) -> some View {
        modifier(FavoritesPageModifier(includeTabBar: includeTabBar))
    }

    func favoritesMinimalBackButton() -> some View {
        modifier(FavoritesMinimalBackButtonModifier())
    }
}

struct FavoritesSectionHeader: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FavoritesTheme.secondary)
                .textCase(nil)
            Spacer()
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FavoritesTheme.tertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct FavoritesCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(FavoritesTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FavoritesTheme.border, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FavoritesTheme.overlay)
                    .opacity(0.55)
                    .allowsHitTesting(false) // 让触摸事件穿透装饰层，避免拦截点击
            }
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

struct FavoritesAuthorRow: View {
    let author: Author
    let subtitle: String

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AsyncImage(url: URL(string: author.avatar_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle()
                    .fill(FavoritesTheme.surfaceElevated)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(FavoritesTheme.secondary)
                    )
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(FavoritesTheme.border, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(author.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FavoritesTheme.title)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FavoritesTheme.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FavoritesTheme.tertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct FavoritesRestaurantRowAction: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let action: () -> Void
}

struct FavoritesRestaurantRowConfiguration {
    enum Trailing {
        case chevron
        case actions([FavoritesRestaurantRowAction])
        case none
    }

    let noteText: String?
    let addressText: String?
    let badgeText: String?
    let badgeTint: Color
    let trailing: Trailing

    init(
        noteText: String? = nil,
        addressText: String? = nil,
        badgeText: String? = nil,
        badgeTint: Color = FavoritesTheme.accent,
        trailing: Trailing = .chevron
    ) {
        self.noteText = noteText
        self.addressText = addressText
        self.badgeText = badgeText
        self.badgeTint = badgeTint
        self.trailing = trailing
    }
}

struct FavoritesRestaurantRow: View {
    let restaurant: Restaurant
    let configuration: FavoritesRestaurantRowConfiguration

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AsyncImage(url: URL(string: restaurant.photo_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FavoritesTheme.surfaceElevated)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .foregroundStyle(FavoritesTheme.secondary)
                    )
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FavoritesTheme.border, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(restaurant.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FavoritesTheme.title)
                    .lineLimit(1)

                if let noteText = configuration.noteText, !noteText.isEmpty {
                    Text(noteText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FavoritesTheme.secondary)
                        .lineLimit(1)
                }

                if let addressText = configuration.addressText, !addressText.isEmpty {
                    Text(addressText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FavoritesTheme.tertiary)
                        .lineLimit(1)
                }

                if let badgeText = configuration.badgeText, !badgeText.isEmpty {
                    FavoritesPill(text: badgeText, color: configuration.badgeTint)
                }
            }

            Spacer(minLength: DS.Spacing.sm)

            trailingView
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingView: some View {
        switch configuration.trailing {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FavoritesTheme.tertiary)
        case .actions(let actions):
            VStack(spacing: 18) {
                ForEach(actions) { item in
                    Button(action: item.action) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .none:
            EmptyView()
        }
    }
}

struct FavoritesPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct FavoritesEmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        FavoritesCard {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(FavoritesTheme.tertiary)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FavoritesTheme.body)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FavoritesTheme.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xxl)
        }
    }
}
