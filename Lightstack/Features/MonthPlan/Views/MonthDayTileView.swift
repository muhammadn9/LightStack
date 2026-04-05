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
            VStack(spacing: 3) {
                Text("\(dayNumber)")
                    .font(AppTheme.plexMono(9, weight: .bold))
                    .foregroundStyle(textColor)

                if let session = session {
                    if session.isRestDay {
                        Text("R")
                            .font(AppTheme.caveat(7))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    } else if session.completed {
                        // Green dot for completed days
                        Circle()
                            .fill(AppTheme.success)
                            .frame(width: 5, height: 5)
                    } else if state == .today {
                        // Subtle pulse for today
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 4, height: 4)
                    } else {
                        Text(shortType(session.workoutType))
                            .font(AppTheme.caveat(7))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
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
        case .rest: return Color.clear
        case .planned: return AppTheme.surface
        case .today: return AppTheme.accent  // solid fill for today
        case .completed: return AppTheme.success.opacity(0.12)
        case .missed: return AppTheme.warning.opacity(0.08)
        case .empty: return Color.clear
        }
    }

    private var textColor: Color {
        switch state {
        case .today: return Color.white
        case .completed: return AppTheme.success
        case .missed: return AppTheme.warning.opacity(0.7)
        case .rest: return AppTheme.textSecondary.opacity(0.5)
        case .empty: return AppTheme.textSecondary.opacity(0.4)
        default: return AppTheme.textPrimary
        }
    }

    private var borderColor: Color {
        state == .today ? AppTheme.accent : Color.clear
    }

    private func shortType(_ type: String) -> String {
        let lower = type.lowercased()
        if lower.contains("push") { return "Push" }
        if lower.contains("pull") { return "Pull" }
        if lower.contains("leg") { return "Legs" }
        if lower.contains("upper") { return "Upr" }
        if lower.contains("lower") { return "Lwr" }
        if lower.contains("full") { return "Full" }
        return String(type.prefix(4))
    }
}
