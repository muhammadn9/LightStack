import SwiftUI

/// 13-week training heatmap: one column per week (oldest left), Monday at the top.
/// Tap a day to see exactly which date it is, what was trained and how many sets.
struct HeatmapView: View {
    /// Weeks x 7 days of set counts; -1 marks days still ahead.
    let cells: [[Int]]
    /// Date of the first cell (Monday of the oldest week).
    var start: Date?
    var summaries: [Date: DaySummary] = [:]

    @State private var selected: Date?
    @State private var width: CGFloat = 300

    private static let gap: CGFloat = 4
    private static let labelWidth: CGFloat = 12
    private static let labelSpacing: CGFloat = 6
    private static let monthRowHeight: CGFloat = 14
    private static let restColor = Color(.systemBlue)
    private static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    private var calendar: Calendar { ProgressStats.weekCalendar() }

    private var cellSize: CGFloat {
        let columns = CGFloat(max(cells.count, 1))
        let usable = width - Self.labelWidth - Self.labelSpacing - Self.gap * (columns - 1)
        return max(8, (usable / columns).rounded(.down))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            grid
            detail
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in if new > 0 { width = new } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.heatmap")
    }

    // MARK: - Grid

    private var grid: some View {
        let size = cellSize
        return HStack(alignment: .top, spacing: Self.labelSpacing) {
            VStack(spacing: Self.gap) {
                Color.clear.frame(width: Self.labelWidth, height: Self.monthRowHeight - Self.gap)
                ForEach(0..<7, id: \.self) { day in
                    Text(Self.weekdayLetters[day])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: Self.labelWidth, height: size)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Self.gap) {
                monthLabels(size: size)
                HStack(spacing: Self.gap) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { weekIndex, week in
                        VStack(spacing: Self.gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, count in
                                cell(week: weekIndex, day: dayIndex, count: count, size: size)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthLabels(size: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: Self.monthRowHeight - Self.gap)
            ForEach(monthLabelColumns, id: \.column) { item in
                Text(item.text)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize()
                    .offset(x: CGFloat(item.column) * (size + Self.gap))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Columns where a new month begins (the first column only when it has room).
    private var monthLabelColumns: [(column: Int, text: String)] {
        guard let start else { return [] }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        var result: [(column: Int, text: String)] = []
        for week in 0..<cells.count {
            guard let monday = calendar.date(byAdding: .day, value: week * 7, to: start) else { continue }
            let previous = calendar.date(byAdding: .day, value: -7, to: monday)
            let month = calendar.component(.month, from: monday)
            if week == 0 || previous.map({ calendar.component(.month, from: $0) }) != month {
                result.append((week, formatter.string(from: monday)))
            }
        }
        if result.count > 1, result[1].column - result[0].column < 3 { result.removeFirst() }
        return result
    }

    private func date(week: Int, day: Int) -> Date? {
        guard let start else { return nil }
        return calendar.date(byAdding: .day, value: week * 7 + day, to: start)
    }

    private func cell(week: Int, day: Int, count: Int, size: CGFloat) -> some View {
        let date = date(week: week, day: day)
        let isFuture = count < 0
        let isSelected = date != nil && date == selected
        return Button {
            guard let date else { return }
            withAnimation(.easeOut(duration: 0.12)) { selected = (selected == date) ? nil : date }
        } label: {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(fill(count: count, date: date))
                .overlay {
                    if isFuture {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(AppTheme.textPrimary, lineWidth: 2)
                    }
                }
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(isFuture || date == nil)
        .accessibilityLabel(date.map { Self.detailText(for: $0, summary: summaries[$0], calendar: calendar) } ?? "")
        .accessibilityIdentifier(date.map { "heatmap.\(Self.idFormatter.string(from: $0))" } ?? "heatmap.none")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func fill(count: Int, date: Date?) -> Color {
        let level = ProgressStats.heatLevel(count)
        if level == 0, let date, summaries[date]?.isRest == true {
            return Self.restColor.opacity(0.5)
        }
        return color(level)
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case ..<0: return .clear
        case 0: return AppTheme.textSecondary.opacity(0.14)
        default: return AppTheme.accent.opacity([0, 0.3, 0.5, 0.75, 1.0][min(level, 4)])
        }
    }

    // MARK: - Detail + legend

    private var detail: some View {
        let text: String = {
            guard let selected else { return "Tap a day for details" }
            return Self.detailText(for: selected, summary: summaries[selected], calendar: calendar)
        }()
        return Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(selected == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.horizontal, 12)
            .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { selected = nil }
            .accessibilityIdentifier("heatmap.detail")
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.caption2).foregroundStyle(AppTheme.textSecondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5).fill(color(level)).frame(width: 11, height: 11)
            }
            Text("More").font(.caption2).foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 8)
            RoundedRectangle(cornerRadius: 2.5).fill(Self.restColor.opacity(0.5)).frame(width: 11, height: 11)
            Text("Rest").font(.caption2).foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Text

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "Tue, Sep 23 · Push · 18 sets", "Sat, Oct 4 · Rest day" or "Mon, Sep 1 · No workout".
    static func detailText(for date: Date, summary: DaySummary?, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        var parts = [formatter.string(from: date)]
        if let summary, !summary.workoutNames.isEmpty || summary.setCount > 0 {
            if !summary.workoutNames.isEmpty { parts.append(summary.workoutNames.joined(separator: ", ")) }
            parts.append("\(summary.setCount) \(summary.setCount == 1 ? "set" : "sets")")
        } else if summary?.isRest == true {
            parts.append("Rest day")
        } else {
            parts.append("No workout")
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
