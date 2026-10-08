import SwiftUI

/// Mon-Sun bubbles for one week (this week by default; arrows page back).
/// Today is filled with the accent, a dot sits under workout days, a moon under rest days.
/// Past days and today are tappable; future days are dimmed.
struct WeekStripView: View {
    /// Start-of-day dates with a workout.
    let workoutDays: Set<Date>
    /// Start-of-day dates marked as rest days.
    let restDays: Set<Date>
    var now: Date = Date()
    /// How many weeks back the strip can page (matches the 13-week heatmap window).
    var maxWeeksBack = 12
    var onSelect: ((Date) -> Void)?

    @State private var weekOffset = 0

    private let letters = ["M", "T", "W", "T", "F", "S", "S"]
    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var calendar: Calendar { ProgressStats.weekCalendar() }

    private var weekStart: Date {
        let current = ProgressStats.weekStart(of: now, calendar: calendar)
        return calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: current) ?? current
    }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var title: String {
        guard weekOffset > 0, let end = days.last, let start = days.first else { return "This week" }
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(f)) - \(end.formatted(f))"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                arrow("chevron.left", id: "weekStrip.previous", enabled: weekOffset < maxWeeksBack, label: "Previous week") {
                    weekOffset += 1
                }
                Spacer()
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("weekStrip.title")
                Spacer()
                arrow("chevron.right", id: "weekStrip.next", enabled: weekOffset > 0, label: "Next week") {
                    weekOffset -= 1
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, date in
                    dayView(index: index, date: date)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekStrip")
    }

    private func arrow(_ symbol: String, id: String, enabled: Bool, label: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? AppTheme.textSecondary : ProgressStyle.dim.opacity(0.4))
                .frame(width: 44, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func dayView(index: Int, date: Date) -> some View {
        let start = calendar.startOfDay(for: date)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isFuture = start > calendar.startOfDay(for: now)
        let trained = workoutDays.contains(start)
        let rest = restDays.contains(start)
        return Button {
            onSelect?(start)
        } label: {
            VStack(spacing: 7) {
                Text(letters[index])
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isToday ? AppTheme.textPrimary : AppTheme.textSecondary)
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(isToday ? ProgressStyle.onAccent : AppTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(isToday ? AppTheme.accent : AppTheme.surface, in: Circle())
                ZStack {
                    Circle()
                        .fill(trained ? AppTheme.accent : .clear)
                        .frame(width: 5, height: 5)
                    if rest && !trained {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.accentSecondary)
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .opacity(isFuture ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day()))
        .accessibilityValue(trained ? "Trained" : (rest ? "Rest day" : ""))
        .accessibilityIdentifier("weekDay.\(Self.idFormatter.string(from: date))")
    }
}

/// Shared look values for the Progress / Today components.
enum ProgressStyle {
    /// Text on accent fills (dark on lime, white on light-mode green).
    static var onAccent: Color { AppTheme.onAccent }
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
