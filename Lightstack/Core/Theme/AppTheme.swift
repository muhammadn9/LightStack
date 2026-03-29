import SwiftUI

/// Central design token system for the purple radiant dark theme.
enum AppTheme {

    // MARK: - Colors

    static let background = Color(hex: 0x0D0D12)
    static let surface = Color(hex: 0x1A1A24)
    static let surfaceElevated = Color(hex: 0x242432)

    static let accent = Color(hex: 0x8B5CF6)
    static let accentGradientStart = Color(hex: 0x7C3AED)
    static let accentGradientEnd = Color(hex: 0xC084FC)
    static let accentSecondary = Color(hex: 0xA78BFA)

    static let textPrimary = Color(hex: 0xF8F8FF)
    static let textSecondary = Color(hex: 0x9CA3AF)

    static let success = Color(hex: 0x22C55E)
    static let warning = Color(hex: 0xF59E0B)
    static let destructive = Color(hex: 0xEF4444)
    static let streakFlame = Color(hex: 0xF97316)

    // MARK: - Gradients

    static let accentGradient = LinearGradient(
        colors: [accentGradientStart, accentGradientEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [Color(hex: 0x0D0D12), Color(hex: 0x12121A)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let successGradient = LinearGradient(
        colors: [Color(hex: 0x16A34A), success],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: - Dimensions

    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.cardPadding)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: Color.purple.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}

struct GlowingCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.cardPadding)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color.purple.opacity(0.2), radius: 16, x: 0, y: 4)
    }
}

struct AccentGradientBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.accentGradient)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func glowingCard() -> some View {
        modifier(GlowingCardStyle())
    }

    func accentGradientBackground() -> some View {
        modifier(AccentGradientBackground())
    }

    func themedBackground() -> some View {
        self.background(AppTheme.backgroundGradient.ignoresSafeArea())
    }
}
