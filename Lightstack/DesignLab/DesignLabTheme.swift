#if DEBUG
import SwiftUI

// MARK: - Config

enum DesignVariant: String { case a = "A", b = "B" }
enum DesignScreen: String { case today, stats, workout }

enum DesignLabConfig {
    static var isEnabled: Bool { CommandLine.arguments.contains("-designLab") }

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var variant: DesignVariant {
        DesignVariant(rawValue: (value(after: "-designVariant") ?? "A").uppercased()) ?? .a
    }
    static var screen: DesignScreen {
        DesignScreen(rawValue: (value(after: "-designScreen") ?? "today").lowercased()) ?? .today
    }
}

// MARK: - Theme

/// Colors and fonts for one design variant. Mock-only; independent of AppTheme.
struct DLTheme {
    let variant: DesignVariant
    var isNotebook: Bool { variant == .b }

    var bg: Color { isNotebook ? Color(hex: 0x14120F) : Color(hex: 0x0B0D0E) }
    var card: Color { isNotebook ? Color(hex: 0x201D19) : Color(hex: 0x1C1E20) }
    var field: Color { isNotebook ? Color(hex: 0x2A2621) : Color(hex: 0x2A2D30) }
    var accent: Color { isNotebook ? Color(hex: 0xE0A030) : Color(hex: 0x3DDC4A) }
    var onAccent: Color { Color(hex: 0x0B0D0E) }
    var text: Color { isNotebook ? Color(hex: 0xF1E9DA) : .white }
    var subtext: Color { isNotebook ? Color(hex: 0xA39A89) : Color(hex: 0x8D9296) }
    var hairline: Color { Color.white.opacity(0.08) }
    var dim: Color { isNotebook ? Color(hex: 0xF1E9DA).opacity(0.28) : Color.white.opacity(0.2) }
    var danger: Color { Color(hex: 0xE5484D) }
    var stamp: Color { Color(hex: 0xD2453B) }
    var barBg: Color { isNotebook ? Color(hex: 0x1A1814) : Color(hex: 0x111314) }

    /// Headings and large titles.
    func heading(_ size: CGFloat) -> Font {
        isNotebook ? .system(size: size, weight: .bold, design: .serif)
                   : .system(size: size, weight: .bold, design: .default)
    }
    /// Big stat numbers.
    func number(_ size: CGFloat) -> Font {
        isNotebook ? .system(size: size, weight: .bold, design: .serif)
                   : .system(size: size, weight: .bold, design: .rounded)
    }
    /// Set values (lbs / reps / RIR).
    func mono(_ size: CGFloat) -> Font {
        isNotebook ? .system(size: size, weight: .medium, design: .monospaced)
                   : .system(size: size, weight: .semibold, design: .rounded)
    }
    /// Small captions. Handwritten in the notebook variant.
    func note(_ size: CGFloat) -> Font {
        isNotebook ? .custom("BradleyHandITCTT-Bold", size: size + 3)
                   : .system(size: size, weight: .medium)
    }
    func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}

private struct DLThemeKey: EnvironmentKey {
    static let defaultValue = DLTheme(variant: .a)
}

extension EnvironmentValues {
    var dlTheme: DLTheme {
        get { self[DLThemeKey.self] }
        set { self[DLThemeKey.self] = newValue }
    }
}
#endif
