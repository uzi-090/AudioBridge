import SwiftUI

enum AppTheme {
    static let background = Color(red: 15 / 255, green: 15 / 255, blue: 35 / 255)
    static let elevatedBackground = Color(red: 23 / 255, green: 23 / 255, blue: 50 / 255)
    static let surface = Color(red: 39 / 255, green: 39 / 255, blue: 59 / 255)
    static let surfaceHighlight = Color(red: 49 / 255, green: 46 / 255, blue: 129 / 255)
    static let accent = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    static let accentPressed = Color(red: 234 / 255, green: 88 / 255, blue: 12 / 255)
    static let onAccent = Color(red: 22 / 255, green: 11 / 255, blue: 3 / 255)
    static let success = Color(red: 45 / 255, green: 212 / 255, blue: 191 / 255)
    static let warning = Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
    static let danger = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
    static let primaryText = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
    static let secondaryText = Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255)
    static let tertiaryText = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    static let border = Color(red: 67 / 255, green: 56 / 255, blue: 202 / 255).opacity(0.55)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let horizontalPadding: CGFloat = 20
}

struct SurfaceCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(AppTheme.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func surfaceCard() -> some View {
        modifier(SurfaceCardModifier())
    }
}
