import SwiftUI

/// The state a dated, completable item can be in.
enum BadgeStatus: CaseIterable {
    case done
    case today
    case missed

    /// Derives status from completion plus date. Returns `nil` for future
    /// incomplete items, which intentionally carry no badge.
    init?(completed: Bool, date: Date) {
        if completed {
            self = .done
        } else if Calendar.current.isDateInToday(date) {
            self = .today
        } else if date < Calendar.current.startOfDay(for: Date()) {
            self = .missed
        } else {
            return nil
        }
    }

    var label: String {
        switch self {
        case .done:   return "Done"
        case .today:  return "Today"
        case .missed: return "Missed"
        }
    }

    var tint: Color {
        switch self {
        case .done:   return AppTheme.success
        case .today:  return AppTheme.accent
        case .missed: return AppTheme.warning
        }
    }
}

/// Capsule badge conveying a `BadgeStatus`.
struct StatusBadge: View {
    let status: BadgeStatus

    var body: some View {
        Text(status.label)
            .font(AppTheme.caveat(11, weight: .bold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.label)")
    }
}
