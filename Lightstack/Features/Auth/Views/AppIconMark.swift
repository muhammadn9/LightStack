import SwiftUI

/// The app icon drawn in SwiftUI: a near-black rounded square with three left-aligned bars stepping up.
struct AppIconMark: View {
    var size: CGFloat = 96

    var body: some View {
        // Geometry follows the 180-point design grid.
        let unit = size / 180
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 40 * unit, style: .continuous)
                .fill(AppTheme.markBackground)
            bar(width: 104, y: 112, color: AppTheme.markBarLong, unit: unit)
            bar(width: 76, y: 83, color: AppTheme.markBarMid, unit: unit)
            bar(width: 48, y: 54, color: AppTheme.markBarShort, unit: unit)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, y: CGFloat, color: Color, unit: CGFloat) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width * unit, height: 18 * unit)
            .offset(x: 38 * unit, y: y * unit)
    }
}
