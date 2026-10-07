import SwiftUI

/// Coach's Notebook design system for LightStack V2.
/// Colors adapt automatically to light / dark mode.
enum AppTheme {

    // MARK: - Adaptive Colors

    /// Variant A "Dark Gym": near-black canvas with lifted cards in dark mode,
    /// system grouped look in light mode.
    static let background = Color(adaptiveDark: 0x0B0D0E, light: 0xF2F2F7)
    static let surface     = Color(adaptiveDark: 0x1C1E20, light: 0xFFFFFF)
    static let surfaceElevated = Color(adaptiveDark: 0x26292B, light: 0xE9E9EE)

    /// Lime (dark) / AA-contrast green on white (light).
    static let accent              = Color(adaptiveDark: 0x3DDC4A, light: 0x1A7F2E)
    static let accentGradientStart = accent
    static let accentGradientEnd   = accent
    static let accentSecondary     = Color(adaptiveDark: 0x7BE585, light: 0x2E9A44)
    /// Text / icons drawn ON an accent fill.
    static let onAccent            = Color(adaptiveDark: 0x0B0D0E, light: 0xFFFFFF)

    /// System label colors.
    static let textPrimary   = Color(.label)
    /// Darker in light mode than system secondaryLabel to meet WCAG AA (4.5:1) on system grouped backgrounds.
    static let textSecondary = Color(adaptiveDark: 0x8D9296, light: 0x555555)

    /// Hairline separator.
    static let border = Color(adaptiveDark: 0x2A2D30, light: 0xD8D8DE)

    // Semantic
    static let success      = Color(.systemGreen)
    static let warning      = Color(.systemOrange)
    static let destructive  = Color(.systemRed)
    static let streakFlame  = Color(.systemOrange)

    // MARK: - Gradients

    /// Effectively solid — the design uses flat lime pills.
    static let accentGradient = LinearGradient(
        colors: [accentGradientStart, accentGradientEnd],
        startPoint: .leading, endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [background, surface],
        startPoint: .top, endPoint: .bottom
    )

    static let successGradient = accentGradient

    /// Success-action buttons (e.g. "Analyse Form") — same solid accent.
    static let successActionGradient = accentGradient

    // MARK: - Notebook-specific Colors

    static let bindingStrip    = AppTheme.surface
    static let bindingHole     = Color(.tertiaryLabel)
    static let cornerFold      = Color.clear
    static let timerTrack      = AppTheme.surfaceElevated
    static let textHand        = AppTheme.textSecondary
    static let prStamp         = Color(hex: 0xB91C1C)

    // MARK: - Dimensions

    static let cornerRadius: CGFloat = 20
    static let cardPadding: CGFloat  = 16
    static let sectionSpacing: CGFloat = 24
    static let minTouchSize: CGFloat = 50

    // MARK: - Dynamic Type

    /// Maps a legacy point size to the nearest semantic text style.
    ///
    /// The font helpers below keep their `(size:weight:)` signatures for source
    /// compatibility, but resolve through this table so every call site scales with
    /// the user's text-size setting.
    ///
    /// Sizes below 11pt all resolve to `.caption2`. That is deliberate: 11pt is
    /// Apple's minimum legible size, so the handful of 7-9pt labels in the app
    /// render slightly larger than before. This is the intended correction.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5:  return .caption2
        case ..<12.5:  return .caption
        case ..<13.5:  return .footnote
        case ..<14.5:  return .subheadline
        case ..<16.5:  return .callout
        case ..<17.5:  return .body
        case ..<20.5:  return .title3
        case ..<26.5:  return .title2
        default:       return .title
        }
    }

    // MARK: - Font Helpers

    /// Page headers, section labels, buttons.
    static func playfair(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let resolved: Font.Weight
        switch weight {
        case .bold, .semibold, .heavy, .black: resolved = .heavy
        default:                               resolved = .bold
        }
        return .system(textStyle(for: size), design: .default, weight: resolved)
    }

    /// Elegant headings, wax-seal labels (no italic — matches previous behaviour).
    static func playfairItalic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        playfair(size, weight: weight)
    }

    /// Handwritten subtitles, labels, notes, tab text.
    static func caveat(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size),
                design: .default,
                weight: weight == .bold ? .medium : .regular)
    }

    /// Data display, stats, calendar numbers — rounded design.
    static func plexMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size), design: .rounded, weight: weight)
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

// MARK: - Scaled Symbol

/// Scales a large decorative SF Symbol with Dynamic Type while preserving its
/// design size.
///
/// Semantic text styles top out at `.largeTitle` (34pt), so routing a 48-60pt
/// hero icon through one would shrink it by a third. This scales by metric
/// instead: the symbol keeps its intended size at the default text setting and
/// grows proportionally from there.
///
/// Use this only for decorative symbols that are *not* inside a hardcoded
/// frame — symbols in fixed frames must keep a fixed size or they clip.
struct ScaledSymbol: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight = .regular) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
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
            .background(AppTheme.background.ignoresSafeArea())
    }
}

// MARK: - Notebook Section Header

/// Section label style — secondary subheadline.
struct NotebookSectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(value) out of \(max)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < max { onChange(value + 1) }
            case .decrement: if value > 1   { onChange(value - 1) }
            @unknown default: break
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
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : AppTheme.surfaceElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityIdentifier("chip.\(label)")
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Button Styles

/// Primary action button — modern filled rounded-rect style.
struct WaxSealButtonStyle: ButtonStyle {
    var isSecondary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isSecondary ? AppTheme.accent : AppTheme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSecondary ? AppTheme.accent.opacity(0.12) : AppTheme.accent,
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    /// Deprecated shim — prefer `.lsCard()` with `.lsCardStyle(_:)`.
    func cardStyle() -> some View {
        lsCard(PlainCardStyle())
    }

    /// Deprecated shim — prefer `.lsCard()` with `.lsCardStyle(AccentedCardStyle())`.
    func glowingCard() -> some View {
        lsCard(AccentedCardStyle())
    }

    /// Sizes a large decorative SF Symbol so it scales with Dynamic Type
    /// without losing its design size.
    func scaledSymbol(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledSymbol(size: size, weight: weight))
    }

    func accentGradientBackground() -> some View {
        modifier(AccentGradientBackground())
    }

    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }

    /// Solid strip behind the status bar for scroll screens without a navigation
    /// bar, so scrolled content doesn't run under the clock.
    func statusBarBackdrop() -> some View {
        overlay(alignment: .top) {
            // The reader starts at the top of the safe area, so shifting the strip up
            // by the inset lands it exactly behind the status bar.
            GeometryReader { proxy in
                AppTheme.background
                    .frame(height: proxy.safeAreaInsets.top)
                    .offset(y: -proxy.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
        }
    }

    func notebookSectionHeader() -> some View {
        modifier(NotebookSectionHeader())
    }
}
