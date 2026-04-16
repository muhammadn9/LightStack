import SwiftUI

/// Coach's Notebook design system for LightStack V2.
/// Colors adapt automatically to light / dark mode.
enum AppTheme {

    // MARK: - Adaptive Colors

    /// Deep leather (dark) / warm parchment (light)
    static let background = Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1)
    static let surface     = Color(adaptiveDark: 0x221810, light: 0xF0E8D8)
    static let surfaceElevated = Color(adaptiveDark: 0x2A2015, light: 0xF4EDD8)

    /// Amber gold (dark) / fountain-pen blue (light)
    static let accent              = Color(adaptiveDark: 0xC8860A, light: 0x1B3A6B)
    static let accentGradientStart = Color(adaptiveDark: 0xA06808, light: 0x1B3A6B)
    static let accentGradientEnd   = Color(adaptiveDark: 0xE09818, light: 0x3A6AB0)
    static let accentSecondary     = Color(adaptiveDark: 0xD4A040, light: 0x3A6AB0)

    /// Warm cream (dark) / deep navy (light)
    static let textPrimary   = Color(adaptiveDark: 0xEDE0C4, light: 0x1B2A40)
    static let textSecondary = Color(adaptiveDark: 0xA09070, light: 0x6A5840)

    /// Ruled-line / card border
    static let border = Color(adaptiveDark: 0x3A2A1A, light: 0xC8B898)

    // Semantic
    static let success      = Color(adaptiveDark: 0x6AB040, light: 0x2A6A2A)
    static let warning      = Color(adaptiveDark: 0xD4920A, light: 0xC8860A)
    static let destructive  = Color(hex: 0xC04030)
    static let streakFlame  = Color(adaptiveDark: 0xD4920A, light: 0xC8860A)

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

    static let bindingStrip    = Color(adaptiveDark: 0x2A1F14, light: 0xE8E0D0)
    static let bindingHole     = Color(adaptiveDark: 0x5A4020, light: 0xB8A880)
    static let cornerFold      = Color(adaptiveDark: 0x2A2015, light: 0xE8E0CC)
    static let timerTrack      = Color(adaptiveDark: 0x3A2A1A, light: 0xE8E0CC)
    static let textHand        = Color(adaptiveDark: 0xC4A878, light: 0x3A5080)
    static let prStamp         = Color(hex: 0xB91C1C)

    // MARK: - Dimensions

    /// Small radius — paper / journal feel
    static let cornerRadius: CGFloat = 10
    static let cardPadding: CGFloat  = 18
    static let sectionSpacing: CGFloat = 20
    static let minTouchSize: CGFloat = 66

    // MARK: - Custom Fonts

    /// Playfair Display — page headers, section labels, buttons
    static func playfair(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return Font.custom("PlayfairDisplay-Bold", size: size)
        default:
            return Font.custom("PlayfairDisplay-Regular", size: size)
        }
    }

    /// Playfair Display Italic — elegant headings, wax-seal labels
    static func playfairItalic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return Font.custom("PlayfairDisplay-BoldItalic", size: size)
        default:
            return Font.custom("PlayfairDisplay-Italic", size: size)
        }
    }

    /// Caveat — handwritten subtitles, labels, notes, tab text
    static func caveat(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        weight == .bold
            ? Font.custom("Caveat-Bold", size: size)
            : Font.custom("Caveat-Regular", size: size)
    }

    /// IBM Plex Mono — data display, stats, calendar numbers
    static func plexMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return Font.custom("IBMPlexMono-Bold", size: size)
        case .medium:
            return Font.custom("IBMPlexMono-Medium", size: size)
        default:
            return Font.custom("IBMPlexMono-Regular", size: size)
        }
    }

    // MARK: - UIFont versions (for UIKit appearance APIs)

    static func uiPlayfairBoldItalic(_ size: CGFloat) -> UIFont {
        UIFont(name: "PlayfairDisplay-BoldItalic", size: size)
            ?? UIFont(name: "PlayfairDisplay-Italic", size: size)
            ?? .italicSystemFont(ofSize: size)
    }

    static func uiCaveat(_ size: CGFloat) -> UIFont {
        UIFont(name: "Caveat-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    static func uiPlexMono(_ size: CGFloat) -> UIFont {
        UIFont(name: "IBMPlexMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
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

/// Plain notebook page card: warm fill + hairline border + small radius.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.cardPadding)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}

/// Accented card: amber/blue left strip + warm fill + hairline border.
struct GlowingCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.cardPadding)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.8))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 4, x: 0, y: 2)
    }
}

struct AccentGradientBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppTheme.accentGradient)
    }
}

/// Full-screen background with very subtle ruled-line texture.
struct ThemedBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    AppTheme.background
                    RuledLinesView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            )
    }
}

// MARK: - Ruled Lines

/// Draws faint horizontal lines over a full-screen background,
/// like a premium training-log notebook.
struct RuledLinesView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let lineColor: Color = scheme == .dark
                    ? Color.white.opacity(0.035)
                    : Color.black.opacity(0.055)
                let spacing: CGFloat = 38
                var y: CGFloat = spacing
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 20, y: y))
                    path.addLine(to: CGPoint(x: size.width - 20, y: y))
                    ctx.stroke(path, with: .color(lineColor), lineWidth: 0.5)
                    y += spacing
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Notebook Section Header

/// Notebook section label style — serif italic + amber underline rule.
struct NotebookSectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            content
                .font(AppTheme.playfairItalic(11))
                .foregroundStyle(AppTheme.textSecondary)
            InkDivider()
        }
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

/// Rectangular journal-tab chip (replaces capsule pills).
struct JournalChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTheme.caveat(13, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1) : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? AppTheme.accent.opacity(0.5) : AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Button Styles

/// Primary action button: wax-seal style with offset ink shadow.
struct WaxSealButtonStyle: ButtonStyle {
    var isSecondary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.playfairItalic(12, weight: .bold))
            .foregroundStyle(isSecondary ? AppTheme.accent : Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSecondary
                    ? AppTheme.accent.opacity(0.12)
                    : AppTheme.accent
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.accent.opacity(isSecondary ? 0.5 : 0.3), lineWidth: 1)
            )
            .shadow(
                color: AppTheme.accent.opacity(isSecondary ? 0 : 0.35),
                radius: 2, x: 2, y: 3
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
