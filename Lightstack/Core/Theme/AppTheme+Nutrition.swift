import SwiftUI

/// Colours for the nutrition side of the app. Macro colours follow the Journal design:
/// protein pink, carbs blue, fat green, calories orange. Text variants meet AA on cards in both modes.
extension AppTheme {
    // Accent of the nutrition side (switch reveal, tab tint).
    static let nutritionAccent = Color(adaptiveDark: 0xFFA14A, light: 0xB45309)

    // Solid colours for numbers and ring strokes.
    static let macroProtein  = Color(adaptiveDark: 0xFF6B9A, light: 0xC2255C)
    static let macroCarbs    = Color(adaptiveDark: 0x5AB0FF, light: 0x1C6DC2)
    static let macroFat      = Color(adaptiveDark: 0x5FD38A, light: 0x2B8A4B)
    static let macroKcal     = Color(adaptiveDark: 0xFFA14A, light: 0xB45309)

    /// Soft fills behind chips and ring tracks.
    static func macroTint(_ color: Color) -> Color { color.opacity(0.16) }

    // Tracker bar colours.
    static let trackerWater  = Color(adaptiveDark: 0xC084FC, light: 0x7E22CE)
    static let trackerFiber  = Color(adaptiveDark: 0x5AB0FF, light: 0x1C6DC2)
    static let trackerSodium = Color(adaptiveDark: 0x4FD1B5, light: 0x0F766E)
    static let trackerOther  = Color(adaptiveDark: 0xFBBF24, light: 0x92600A)

    static let waterBlue = Color(adaptiveDark: 0x4AB3FF, light: 0x0A7AD6)
    static let quickTrackGreen = Color(adaptiveDark: 0x3DDC4A, light: 0x1A7F2E)
}
