import SwiftUI

struct MockPlanView: View {

    @State private var displayedMonth: Date = {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: Date())
        ) ?? Date()
    }()

    private let today = Calendar.current.startOfDay(for: Date())
    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ModernTheme.spacingM) {
                    monthHeaderBar
                    calendarCard
                    thisWeekSection
                    editSplitButton
                }
                .padding(.horizontal, ModernTheme.spacingM)
                .padding(.vertical, ModernTheme.spacingM)
            }
            .modernScreenBackground()
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(ModernTheme.accent)
                    }
                }
            }
        }
    }

    private var monthHeaderBar: some View {
        HStack {
            Button(action: { shiftMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(ModernTheme.accent)
            }
            Spacer()
            Text(monthString(for: displayedMonth))
                .font(.title3.weight(.semibold))
            Spacer()
            Button(action: { shiftMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .foregroundStyle(ModernTheme.accent)
            }
        }
        .padding(.horizontal, ModernTheme.spacingS)
    }

    private var calendarCard: some View {
        VStack(spacing: ModernTheme.spacingS) {
            weekdayHeader
            calendarDayGrid
        }
        .modernCard()
    }

    private var weekdayHeader: some View {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return LazyVGrid(columns: sevenColumns(), spacing: 0) {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarDayGrid: some View {
        let cells = gridCells(for: displayedMonth)
        let sessionMap = sessionsByDay()
        return LazyVGrid(columns: sevenColumns(), spacing: 4) {
            ForEach(cells) { cell in
                calendarDayCell(cell: cell, sessionMap: sessionMap)
            }
        }
    }

    private func calendarDayCell(cell: GridCell, sessionMap: [Date: MockPlannedSession]) -> some View {
        let isToday = cell.date == today
        let inMonth = cal.isDate(cell.date, equalTo: displayedMonth, toGranularity: .month)
        let session = sessionMap[cell.date]
        let isFuture = cell.date >= today

        return ZStack {
            if isToday {
                Circle()
                    .stroke(ModernTheme.accent, lineWidth: 2)
                    .padding(2)
            }

            VStack(spacing: 2) {
                Group {
                    if let session = session, session.isRest, inMonth {
                        Text("—")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.5))
                    } else {
                        Text("\(cell.dayNumber)")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(inMonth ? Color.primary : Color.primary.opacity(0.2))
                    }
                }

                if let session = session, inMonth, !session.isRest {
                    if session.isCompleted {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    } else if isFuture {
                        Circle()
                            .stroke(ModernTheme.accent, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                    } else {
                        Color.clear.frame(width: 8, height: 8)
                    }
                } else {
                    Color.clear.frame(width: 8, height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: ModernTheme.spacingS) {
            Text("This Week")
                .font(.headline)
                .padding(.horizontal, ModernTheme.spacingXS)

            VStack(spacing: ModernTheme.spacingS) {
                ForEach(currentWeekDays(), id: \.self) { day in
                    weekDayRow(for: day)
                }
            }
        }
    }

    private func weekDayRow(for day: Date) -> some View {
        let session = sessionsByDay()[day]
        let isCompleted = session?.isCompleted ?? false
        let isRest = session?.isRest ?? false
        let label = session?.type ?? "Rest"

        return HStack(spacing: ModernTheme.spacingM) {
            Text(shortWeekdayName(for: day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.title3.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Group {
                if isRest {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary.opacity(0.4))
                } else if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(ModernTheme.accent)
                }
            }
            .font(.title3)
        }
        .modernCardFilled(padding: ModernTheme.spacingM)
    }

    private var editSplitButton: some View {
        Button("Edit Split Plan") {}
            .buttonStyle(ModernSecondaryButtonStyle())
    }

    private func shiftMonth(by value: Int) {
        if let shifted = cal.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = shifted
        }
    }

    private func monthString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func sevenColumns() -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private func sessionsByDay() -> [Date: MockPlannedSession] {
        var map: [Date: MockPlannedSession] = [:]
        for session in MockData.monthSessions {
            let day = cal.startOfDay(for: session.date)
            map[day] = session
        }
        return map
    }

    private func gridCells(for month: Date) -> [GridCell] {
        guard
            let firstOfMonth = cal.date(
                from: cal.dateComponents([.year, .month], from: month)
            )
        else { return [] }

        var weekdayOfFirst = cal.component(.weekday, from: firstOfMonth)
        weekdayOfFirst = ((weekdayOfFirst - 2) + 7) % 7

        guard let gridStart = cal.date(byAdding: .day, value: -weekdayOfFirst, to: firstOfMonth) else {
            return []
        }

        return (0..<35).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return GridCell(date: cal.startOfDay(for: date), dayNumber: cal.component(.day, from: date))
        }
    }

    private func currentWeekDays() -> [Date] {
        var weekday = cal.component(.weekday, from: today)
        weekday = ((weekday - 2) + 7) % 7
        guard let monday = cal.date(byAdding: .day, value: -weekday, to: today) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: monday) else { return nil }
            return cal.startOfDay(for: day)
        }
    }

    private func shortWeekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

private struct GridCell: Identifiable {
    let id = UUID()
    let date: Date
    let dayNumber: Int
}

#Preview("Light") {
    MockPlanView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MockPlanView()
        .preferredColorScheme(.dark)
}
