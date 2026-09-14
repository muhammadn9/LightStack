import SwiftUI

/// Coach's Notebook design system for LightStack V2.
/// Colors adapt automatically to light / dark mode.
enum AppTheme {

    // MARK: - Adaptive Colors

    /// System grouped backgrounds — adapt automatically to light/dark mode.
    static let background = Color(.systemGroupedBackground)
    static let surface     = Color(.secondarySystemGroupedBackground)
    static let surfaceElevated = Color(.tertiarySystemGroupedBackground)

    /// Amber gold (dark) / fountain-pen blue (light)
    static let accent              = Color(adaptiveDark: 0xC8860A, light: 0x1B3A6B)
    static let accentGradientStart = Color(adaptiveDark: 0xA06808, light: 0x1B3A6B)
    static let accentGradientEnd   = Color(adaptiveDark: 0xE09818, light: 0x3A6AB0)
    static let accentSecondary     = Color(adaptiveDark: 0xD4A040, light: 0x3A6AB0)

    /// System label colors.
    static let textPrimary   = Color(.label)
    static let textSecondary = Color(.secondaryLabel)

    /// Hairline separator.
    static let border = Color(.separator)

    // Semantic
    static let success      = Color(.systemGreen)
    static let warning      = Color(.systemOrange)
    static let destructive  = Color(.systemRed)
    static let streakFlame  = Color(.systemOrange)

    // MARK: - Gradients

    static let accentGradient = LinearGradient(
        colors: [accentGradientStart, accentGradientEnd],
        startPoint: .leading, endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [background, surface],
        startPoint: .top, endPoint: .bottom
    )

    static let successGradient = LinearGradient(
        colors: [Color(hex: 0x2A6A2A), Color(hex: 0x6AB040)],
        startPoint: .leading, endPoint: .trailing
    )

    // MARK: - Notebook-specific Colors

    static let bindingStrip    = Color(.secondarySystemGroupedBackground)
    static let bindingHole     = Color(.tertiaryLabel)
    static let cornerFold      = Color.clear
    static let timerTrack      = Color(.systemFill)
    static let textHand        = Color(.secondaryLabel)
    static let prStamp         = Color(hex: 0xB91C1C)

    // MARK: - Dimensions

    static let cornerRadius: CGFloat = 14
    static let cardPadding: CGFloat  = 16
    static let sectionSpacing: CGFloat = 24
    static let minTouchSize: CGFloat = 50

    // MARK: - Custom Fonts

    /// Page headers, section labels, buttons — system font.
    static func playfair(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return Font.system(size: size, weight: .bold)
        default:
            return Font.system(size: size, weight: .semibold)
        }
    }

    /// Elegant headings, wax-seal labels — system font (no italic).
    static func playfairItalic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        playfair(size, weight: weight)
    }

    /// Handwritten subtitles, labels, notes, tab text — system font.
    static func caveat(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight == .bold ? .medium : .regular)
    }

    /// Data display, stats, calendar numbers — rounded system font.
    static func plexMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - UIFont versions (for UIKit appearance APIs)

    static func uiPlayfairBoldItalic(_ size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .bold)
    }

    static func uiCaveat(_ size: CGFloat) -> UIFont {
        .systemFont(ofSize: size)
    }

    static func uiPlexMono(_ size: CGFloat) -> UIFont {
        .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - Color Hex Extensions

extension Color {
    /// Fixed hex colour (no dark/light adaptation).
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex & 0xFF)          / 255,
            opacity: opacity
        )
    }

    /// Adaptive colour: one value in dark mode, another in light mode.
    init(adaptiveDark dark: UInt, light: UInt) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(netHex: dark)
                : UIColor(netHex: light)
        })
    }
}

extension UIColor {
    convenience init(netHex hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8)  & 0xFF) / 255,
            blue:  CGFloat(hex & 0xFF)          / 255,
            alpha: alpha
        )
    }
}

// MARK: - View Modifiers

/// Translucent material card with hairline border.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.cardPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
    }
}

/// Accented card: material card + amber/blue leading accent strip.
struct GlowingCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.cardPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.8))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
    }
}

struct AccentGradientBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppTheme.accentGradient)
    }
}

/// Full-screen background — system grouped background.
struct ThemedBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Notebook Section Header

/// Section label style — secondary subheadline.
struct NotebookSectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Ink Dot Rating

/// Filled ink-dot rating control (replaces slider for energy level).
struct InkDotRating: View {
    let value: Int
    let max: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...max, id: \.self) { i in
                Button(action: { onChange(i) }) {
                    Circle()
                        .fill(i <= value ? AppTheme.accent : Color.clear)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(AppTheme.accent.opacity(0.6), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Journal Chip

/// Modern capsule chip.
struct JournalChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : Color(.secondarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Button Styles

/// Primary action button — modern filled rounded-rect style.
struct WaxSealButtonStyle: ButtonStyle {
    var isSecondary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isSecondary ? AppTheme.accent : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSecondary ? AppTheme.accent.opacity(0.12) : AppTheme.accent,
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

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
        modifier(ThemedBackground())
    }

    func notebookSectionHeader() -> some View {
        modifier(NotebookSectionHeader())
    }
}
