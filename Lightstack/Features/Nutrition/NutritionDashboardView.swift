import SwiftUI
import Charts

private enum DashboardRoute: Hashable { case summary, weightHistory }

/// The nutrition Dashboard: week of macros, weigh-in and food-log cards.
struct NutritionDashboardView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @EnvironmentObject var environment: AppEnvironment
    @State private var path: [DashboardRoute] = []
    @State private var selectedDay = Date().startOfDay
    @State private var week: [DashboardDay] = []
    @State private var overview: NutritionDashboard?
    @State private var logWeight = false

    private let calendar = Calendar.current
    private var today: Date { Date().startOfDay }
    private var unit: BodyWeightUnit { viewModel.bodyWeightUnit }
    private var weekIsCurrent: Bool { week.contains { calendar.isDate($0.date, inSameDayAs: today) } }
    private var selected: DashboardDay? { week.first { calendar.isDate($0.date, inSameDayAs: selectedDay) } }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        macrosCard
                        HStack(alignment: .top, spacing: 12) {
                            weighInCard
                            foodLogCard
                        }
                    }
                    .padding(16)
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .summary: NutritionSummaryView(viewModel: viewModel)
                case .weightHistory: WeightHistoryView(viewModel: viewModel)
                }
            }
        }
        .sheet(isPresented: $logWeight) {
            WeightSheet(viewModel: viewModel).presentationDetents([.medium, .large])
        }
        .onAppear(perform: refresh)
        .onChange(of: viewModel.dataVersion) { _, _ in refresh() }
    }

    private func refresh() {
        let anchor = viewModel.dashboard(for: selectedDay)
        week = anchor?.week ?? []
        overview = calendar.isDate(selectedDay, inSameDayAs: today) ? anchor : viewModel.dashboard(for: today)
    }

    // MARK: - Header

    private var firstName: String {
        environment.authService.currentUser()?.displayName?
            .split(separator: " ").first.map(String.init) ?? ""
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(firstName.isEmpty ? "Welcome" : "Welcome, \(firstName)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("dashboard.title")
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("dashboard.date")
            }
            Spacer()
            SideSwitchButton()
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: - Macros card

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Macronutrients").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button { path.append(.summary) } label: {
                    HStack(spacing: 2) { Text("See All"); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("dashboard.seeAll")
            }
            weekNavigator
            chart
            dayLabels
            tiles
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.macros")
    }

    private var weekNavigator: some View {
        HStack {
            Button { shiftWeek(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 36)
            }
            .accessibilityLabel("Previous week")
            .accessibilityIdentifier("dashboard.prevWeek")
            Spacer()
            Text(weekTitle).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("dashboard.weekTitle")
            Spacer()
            Button { shiftWeek(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 36)
            }
            .disabled(weekIsCurrent)
            .accessibilityLabel("Next week")
            .accessibilityIdentifier("dashboard.nextWeek")
        }
        .foregroundStyle(AppTheme.textPrimary)
    }

    private var weekTitle: String {
        guard let first = week.first, let last = week.last else { return "" }
        if weekIsCurrent { return "This week" }
        let f = Date.FormatStyle().month(.abbreviated).day()
        return "\(first.date.formatted(f)) – \(last.date.formatted(f))"
    }

    private func shiftWeek(_ delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: 7 * delta, to: selectedDay) else { return }
        selectedDay = delta > 0 ? min(next, today) : next
        refresh()
    }

    private var yMax: Double {
        var peak = 0.0
        for day in week {
            let macroKcal: Double = day.totals.protein * 4 + day.totals.carbs * 4 + day.totals.fat * 9
            let goal: Double = day.target?.kcal ?? 0
            peak = max(peak, day.totals.kcal, goal, macroKcal)
        }
        return max(peak, 1000) * 1.1
    }

    private struct Slice: Identifiable {
        let index: String
        let macro: String
        let kcal: Double
        let selected: Bool
        var id: String { index + macro }
    }

    private var slices: [Slice] {
        var out: [Slice] = []
        for (index, day) in week.enumerated() where day.hasLog {
            let sel = calendar.isDate(day.date, inSameDayAs: selectedDay)
            out.append(Slice(index: String(index), macro: "Protein", kcal: day.totals.protein * 4, selected: sel))
            out.append(Slice(index: String(index), macro: "Carbs", kcal: day.totals.carbs * 4, selected: sel))
            out.append(Slice(index: String(index), macro: "Fat", kcal: day.totals.fat * 9, selected: sel))
        }
        return out
    }

    private var emptyKeys: [String] {
        week.enumerated().filter { !$0.element.hasLog }.map { String($0.offset) }
    }

    private var targetMarks: [(String, Double)] {
        week.enumerated().compactMap { index, day in
            guard let kcal = day.target?.kcal, kcal > 0 else { return nil }
            return (String(index), kcal)
        }
    }

    private var chart: some View {
        let top = yMax
        return Chart {
            ForEach(slices) { slice in
                BarMark(x: .value("Day", slice.index), y: .value("kcal", slice.kcal), width: .ratio(0.55))
                    .foregroundStyle(by: .value("Macro", slice.macro))
                    .opacity(slice.selected ? 1 : 0.55)
            }
            ForEach(emptyKeys, id: \.self) { key in
                PointMark(x: .value("Day", key), y: .value("kcal", 0))
                    .foregroundStyle(AppTheme.textSecondary).symbolSize(36)
            }
            ForEach(targetMarks, id: \.0) { mark in
                PointMark(x: .value("Day", mark.0), y: .value("Target", mark.1))
                    .symbol { Capsule().fill(AppTheme.textSecondary).frame(width: 22, height: 3) }
            }
        }
        .chartForegroundStyleScale(domain: ["Protein", "Carbs", "Fat"], range: [AppTheme.macroProtein, AppTheme.macroCarbs, AppTheme.macroFat])
        .chartLegend(.hidden)
        .chartXScale(domain: (0..<7).map(String.init))
        .chartYScale(domain: (-top * 0.05)...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 170)
        .accessibilityIdentifier("dashboard.chart")
    }

    private var dayLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDay)
                Button { selectedDay = day.date } label: {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AppTheme.background : AppTheme.textPrimary)
                        .padding(.horizontal, 8).frame(height: 34)
                        .background(isSelected ? AppTheme.textPrimary : Color.clear, in: Capsule())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("dashboard.day.\(index)")
            }
        }
    }

    private var tiles: some View {
        let totals = selected?.totals ?? NutrientValues()
        let target = selected?.target
        return HStack(spacing: 8) {
            tile("Protein", AppTheme.macroProtein, totals.protein, target?.protein, id: "dashboard.tile.protein")
            tile("Carbs", AppTheme.macroCarbs, totals.carbs, target?.carbs, id: "dashboard.tile.carbs")
            tile("Fat", AppTheme.macroFat, totals.fat, target?.fat, id: "dashboard.tile.fat")
            tile("Calories", AppTheme.macroKcal, totals.kcal, target?.kcal, id: "dashboard.tile.kcal")
        }
    }

    private func tile(_ title: String, _ color: Color, _ value: Double, _ goal: Double?, id: String) -> some View {
        let valueText = NutritionFormat.whole(value)
        let goalText = goal.map { "of \(NutritionFormat.whole($0))" } ?? "no target"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(valueText).font(.title3.weight(.bold)).foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(goalText).font(.caption).foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(valueText) \(goalText)")
        .accessibilityIdentifier(id)
    }

    // MARK: - Weigh-in card

    private var weighInCard: some View {
        let grid = overview?.weighInGrid.map(\.hasWeighIn) ?? Array(repeating: false, count: 30)
        let latest = overview?.latestWeight
        let change = overview?.weightChange30Days
        let latestText = latest.map { "\(NutritionFormat.amount($0.value)) \(unit.label)" }
        let changeText = change.map { signed($0) } ?? "—"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weigh-in").font(.headline).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button { logWeight = true } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.accent.opacity(0.16), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Log weight")
                .accessibilityIdentifier("dashboard.weighIn.add")
            }
            .frame(height: 28)
            Button { path.append(.weightHistory) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    DotGrid(filled: grid, color: AppTheme.waterBlue)
                    if let latestText {
                        Text(latestText).font(.title3.weight(.bold)).foregroundStyle(AppTheme.textPrimary)
                        Text("30-day change \(changeText)").font(.caption).foregroundStyle(AppTheme.textSecondary)
                    } else {
                        Text("No weigh-ins yet").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weight history")
            .accessibilityValue(latestText.map { "\($0), 30-day change \(changeText)" } ?? "No weigh-ins yet")
            .accessibilityIdentifier("dashboard.weighIn.open")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.weighIn")
    }

    private func signed(_ value: Double) -> String {
        let magnitude = NutritionFormat.amount(abs(value))
        if magnitude == "0" { return "0 \(unit.label)" }
        return "\(value < 0 ? "−" : "+")\(magnitude) \(unit.label)"
    }

    // MARK: - Food Log card

    private var foodLogCard: some View {
        let grid = overview?.foodLogGrid.map(\.hasLog) ?? Array(repeating: false, count: 30)
        let streak = overview?.currentStreak ?? 0
        let best = overview?.bestStreak ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Food Log").font(.headline).foregroundStyle(AppTheme.textPrimary).frame(height: 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            DotGrid(filled: grid, color: AppTheme.trackerWater)
            if best == 0 {
                Text("No logs yet").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("dashboard.streak")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current streak \(streak) \(streak == 1 ? "day" : "days")")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("dashboard.streak")
                    Text("Best \(best)").font(.caption).foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("dashboard.bestStreak")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.foodLog")
    }
}

/// 30 small cells (3 rows of 10), oldest first; filled where something was logged.
private struct DotGrid: View {
    let filled: [Bool]
    let color: Color

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 10), spacing: 3) {
            ForEach(Array(filled.enumerated()), id: \.offset) { _, on in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(on ? color : AppTheme.surfaceElevated)
                    .aspectRatio(0.7, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Summary

/// "See All": averages over 4 weeks or 3 months with a daily calorie chart.
struct NutritionSummaryView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var range = 0
    @State private var summary: RangeSummary = .empty(days: 28)
    @State private var days: [DashboardDay] = []

    private var dayCount: Int { range == 0 ? 28 : 90 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Range", selection: $range) {
                    Text("4 weeks").tag(0)
                    Text("3 months").tag(1)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("dashboard.range")

                averagesCard
                chartCard
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Macronutrients")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.summary")
        .onAppear(perform: refresh)
        .onChange(of: range) { _, _ in refresh() }
        .onChange(of: viewModel.dataVersion) { _, _ in refresh() }
    }

    private func refresh() {
        let today = Date().startOfDay
        let overview = viewModel.dashboard(for: today)
        summary = (range == 0 ? overview?.range28 : overview?.range90) ?? .empty(days: dayCount)
        days = viewModel.dashboardDays(dayCount, endingOn: today)
    }

    private var averagesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if summary.loggedDays == 0 {
                Text("No logs in this period").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("dashboard.summary.empty")
            } else {
                Text("Daily average").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                Text("\(NutritionFormat.whole(summary.avgKcal)) kcal")
                    .font(.system(size: 34, weight: .bold)).foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("dashboard.summary.avgKcal")
                HStack(spacing: 8) {
                    macroStat("Protein", AppTheme.macroProtein, summary.avgProtein)
                    macroStat("Carbs", AppTheme.macroCarbs, summary.avgCarbs)
                    macroStat("Fat", AppTheme.macroFat, summary.avgFat)
                }
                Text("\(summary.daysOnTarget) of \(summary.loggedDaysWithTarget) logged days on target")
                    .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("dashboard.summary.onTarget")
                Text("\(summary.loggedDays) of \(summary.days) days logged")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("dashboard.summary.logged")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private func macroStat(_ title: String, _ color: Color, _ grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
            }
            Text("\(NutritionFormat.whole(grams)) g").font(.headline).foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.border, lineWidth: 1))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily calories").font(.headline).foregroundStyle(AppTheme.textPrimary)
            Chart {
                ForEach(days.filter(\.hasLog)) { day in
                    BarMark(x: .value("Date", day.date, unit: .day), y: .value("kcal", day.totals.kcal))
                        .foregroundStyle(AppTheme.macroKcal)
                }
                if summary.loggedDays > 0 {
                    RuleMark(y: .value("Average", summary.avgKcal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .chartXScale(domain: (days.first?.date ?? Date())...(days.last?.date ?? Date()).addingTimeInterval(86_400))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == 0 ? 7 : 30)) { _ in
                    AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 200)
            .accessibilityIdentifier("dashboard.summary.chart")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }
}
