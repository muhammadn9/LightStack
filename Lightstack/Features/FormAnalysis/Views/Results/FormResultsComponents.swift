import SwiftUI

// Small building blocks shared by the results sections.

extension View {
    /// The standard rounded card used across the app.
    func formCard(padding: CGFloat = AppTheme.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

struct FormSectionHeader: View {
    let title: String
    var systemImage: String?
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(AppTheme.accent)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A rep number as a small pill, e.g. "Rep 4".
struct RepChip: View {
    let number: Int

    var body: some View {
        Text("Rep \(number)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppTheme.surfaceElevated, in: Capsule())
    }
}
