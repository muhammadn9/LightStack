import SwiftUI

/// Small stat tile: icon, big value, caption.
struct StatCard: View {
    let symbol: String
    let value: String
    let caption: String
    var identifier: String = ""

    var body: some View {
        ProgressCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier(identifier)
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}
