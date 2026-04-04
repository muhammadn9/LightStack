import SwiftUI

/// State of a day tile in the month plan calendar.
enum DayTileState {
    case rest
    case planned
    case today
    case completed
    case missed
    case empty
}

/// Reusable day tile for the month plan calendar.
struct MonthDayTileView: View {
    let date: Date
    let session: PlannedSession?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(textColor)

                if let session = session {
                    if session.isRestDay {
                        Text("Rest")
                            .font(.system(size: 8))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else if session.completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.success)
                    } else {
                        Text(shortType(session.workoutType))
                            .font(.system(size: 8))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(borderColor, lineWidth: state == .today ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    private var state: DayTileState {
        guard let session = session else { return .empty }
        if session.isRestDay { return .rest }
        if session.completed { return .completed }
        if Calendar.current.isDateInToday(date) { return .today }
        if date < Calendar.current.startOfDay(for: Date()) { return .missed }
        return .planned
    }

    private var backgroundColor: Color {
        switch state {
        case .rest: return AppTheme.surface.opacity(0.5)
        case .planned: return AppTheme.surface
        case .today: return AppTheme.accent.opacity(0.15)
        case .completed: return AppTheme.success.opacity(0.1)
        case .missed: return AppTheme.warning.opacity(0.1)
        case .empty: return Color.clear
        }
    }

    private var textColor: Color {
        switch state {
        case .today: return AppTheme.accent
        case .completed: return AppTheme.success
        case .missed: return AppTheme.warning
        default: return AppTheme.textPrimary
        }
    }

    private var borderColor: Color {
        state == .today ? AppTheme.accent : Color.clear
    }

    private func shortType(_ type: String) -> String {
        // Abbreviate common workout types
        let lower = type.lowercased()
        if lower.contains("push") { return "Push" }
        if lower.contains("pull") { return "Pull" }
        if lower.contains("leg") { return "Legs" }
        if lower.contains("upper") { return "Upper" }
        if lower.contains("lower") { return "Lower" }
        if lower.contains("full") { return "Full" }
        return String(type.prefix(5))
    }
}
