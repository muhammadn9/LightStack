import SwiftUI

/// Clean iOS-native design system used by the V3 mockup screens.
///
/// Goals: feel like a first-party iOS 17+ app. Use system colors and
/// materials so dark/light mode are free; SF Pro for everything; cards
/// with translucent materials and subtle separators instead of bordered
/// parchment surfaces.
///
/// Lives under Features/_Mockups/ so the existing AppTheme keeps working
/// for production screens until the cutover is approved.
enum ModernTheme {

    // MARK: - Brand accent

    /// Single brand accent kept from the prior identity:
    /// amber gold in dark mode, fountain-pen blue in light mode.
    static var accent: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.78, green: 0.52, blue: 0.04, alpha: 1)
                : UIColor(red: 0.11, green: 0.23, blue: 0.42, alpha: 1)
        })
    }

    // MARK: - Spacing scale

    static let spacingXS: CGFloat = 4
    static let spacingS:  CGFloat = 8
    static let spacingM:  CGFloat = 16
    static let spacingL:  CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: - Corner radii

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 20
}

// MARK: - View modifiers

extension View {

    /// Translucent material card with hairline border. Use for primary
    /// content surfaces (workout cards, stats panels).
    func modernCard(padding: CGFloat = ModernTheme.spacingM) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ModernTheme.radiusM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ModernTheme.radiusM, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
    }

    /// Filled secondary surface — for data-dense rows and grouped lists.
    func modernCardFilled(padding: CGFloat = ModernTheme.spacingM) -> some View {
        self
            .padding(padding)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: ModernTheme.radiusM, style: .continuous))
    }

    /// Standard screen background — system grouped background.
    func modernScreenBackground() -> some View {
        self.background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Modern primary button

struct ModernPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ModernTheme.accent, in: RoundedRectangle(cornerRadius: ModernTheme.radiusM, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(ModernTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ModernTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: ModernTheme.radiusM, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Common atoms

/// Pill-shaped status chip. Used for muscle group tags, workout type, etc.
struct ModernChip: View {
    let label: String
    var icon: String? = nil
    var tint: Color = ModernTheme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.caption2)
            }
            Text(label).font(.caption).fontWeight(.medium)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Big numeric stat (e.g. streak count, total volume). Label below.
struct ModernStatTile: View {
    let value: String
    let label: String
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(ModernTheme.accent)
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modernCardFilled()
    }
}
