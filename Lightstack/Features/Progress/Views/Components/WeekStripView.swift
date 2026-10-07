import SwiftUI

/// Mon-Sun bubbles for the current week: today filled with the accent, a dot under trained days.
struct WeekStripView: View {
    /// Weekday indices (0 = Monday) with a workout.
    let trainedDays: Set<Int>
    var now: Date = Date()

    private let letters = ["M", "T", "W", "T", "F", "S", "S"]

    private var calendar: Calendar { ProgressStats.weekCalendar() }

    private var days: [Date] {
        let start = ProgressStats.weekStart(of: now, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, date in
                let isToday = calendar.isDate(date, inSameDayAs: now)
                VStack(spacing: 7) {
                    Text(letters[index])
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isToday ? AppTheme.textPrimary : AppTheme.textSecondary)
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(isToday ? ProgressStyle.onAccent : AppTheme.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(isToday ? AppTheme.accent : AppTheme.surface, in: Circle())
                    Circle()
                        .fill(trainedDays.contains(index) ? AppTheme.accent : .clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day()))
                .accessibilityValue(trainedDays.contains(index) ? "Trained" : "")
            }
        }
        .accessibilityIdentifier("weekStrip")
    }
}

/// Shared look values for the Progress / Today components.
enum ProgressStyle {
    /// Text on accent fills. Fixed dark so it reads on the lime accent.
    static let onAccent = Color(hex: 0x0B0D0E)
    static let cardRadius: CGFloat = 22
    static var dim: Color { AppTheme.textSecondary.opacity(0.5) }
}

/// Rounded surface card used across Progress and Today.
struct ProgressCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: ProgressStyle.cardRadius, style: .continuous))
    }
}
