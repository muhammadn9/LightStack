import SwiftUI

// MARK: - Plan Switcher Chips

/// Horizontal scrolling chip row for switching between multiple active plans.
struct PlanSwitcherChipsView: View {
    let plans: [MonthPlan]
    let activePlanId: UUID?
    let onSelect: (MonthPlan) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(plans) { plan in
                    Button {
                        onSelect(plan)
                    } label: {
                        Text(plan.title ?? "Plan")
                            .font(AppTheme.caveat(11))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(activePlanId == plan.id ? AppTheme.accent : AppTheme.surfaceElevated)
                            .foregroundStyle(activePlanId == plan.id ? Color.white : AppTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Calendar Grid

/// Mon–Sun calendar grid showing tiles for every day in the plan month.
struct MonthCalendarGridView: View {
    /// Weeks pre-computed as rows of optional dates (nil = empty cell).
    let weeks: [[Date?]]
    /// Returns the planned session for a given date, or nil.
    let sessionForDate: (Date) -> PlannedSession?
    /// Called when the user taps a day tile that has a session.
    let onTapDate: (Date) -> Void

    var body: some View {
        VStack(spacing: 3) {
            // Day-of-week headers: Mon → Sun
            HStack(spacing: 3) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(AppTheme.caveat(9))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Week rows
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, dateOpt in
                        if let date = dateOpt {
                            MonthDayTileView(
                                date: date,
                                session: sessionForDate(date),
                                onTap: {
                                    onTapDate(date)
                                }
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - This Week's Plan

/// Vertical list of the current ISO week's planned sessions.
struct ThisWeekSectionView: View {
    let sessions: [PlannedSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Week's Plan")
                .notebookSectionHeader()

            if sessions.isEmpty {
                Text("No sessions planned this week")
                    .font(AppTheme.caveat(13))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(sessions, id: \.id) { session in
                    WeekSessionRowView(session: session)
                }
            }
        }
    }
}

/// Single row inside the "This Week's Plan" section.
struct WeekSessionRowView: View {
    let session: PlannedSession

    var body: some View {
        HStack(spacing: 8) {
            // Status square
            let isToday = Calendar.current.isDateInToday(session.plannedDate)
            let isDone = session.completed

            RoundedRectangle(cornerRadius: 2)
                .fill(isDone ? AppTheme.success : isToday ? AppTheme.accent : AppTheme.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isDone ? AppTheme.success : isToday ? AppTheme.accent : AppTheme.border, lineWidth: 1)
                )
                .frame(width: 10, height: 10)

            // Day label + workout type
            let dayStr: String = DateFormatter.dayAbbreviation.string(from: session.plannedDate)

            if session.isRestDay {
                Text("\(dayStr) · Rest")
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text("\(dayStr) · \(session.workoutType)")
                    .font(AppTheme.caveat(12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? AppTheme.accent : AppTheme.textSecondary)
            }

            Spacer()

            // Status label (right-aligned)
            if isDone {
                Text("Done ✓")
                    .font(AppTheme.caveat(10))
                    .foregroundStyle(AppTheme.success)
            } else if isToday && !session.isRestDay {
                Text("▶ Now")
                    .font(AppTheme.plexMono(9))
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }
}
