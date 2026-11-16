import SwiftUI
import Charts

/// Progress tab: Overview (streak, consistency, top lift trends, equipment balance) and
/// Lifts (every lift ever logged, with a detail page per lift).
struct ProgressTabView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var snapshot = ProgressSnapshot()
    @State private var lifts: [LiftSummary] = []
    @State private var loaded = false
    /// The last chosen segment is remembered.
    @AppStorage("progressSegment") private var sectionRaw = Section.overview.rawValue

    enum Section: String, CaseIterable, Identifiable {
        case overview, lifts
        var id: String { rawValue }
        var title: String { self == .overview ? "Overview" : "Lifts" }
    }

    private var section: Section { Section(rawValue: sectionRaw) ?? .overview }

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { key in
                    if let lift = lifts.first(where: { $0.key == key }) {
                        LiftDetailView(lift: lift, refresh: reload)
                    } else {
                        Text("This lift has no logged sets any more.")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .navigationDestination(for: LiftSessionRoute.self) { route in
                    LiftSessionDestination(workoutId: route.workoutId)
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("progress.title")
                    Spacer()
                    SideSwitchButton()
                }
                segmented
                if loaded && snapshot.totalWorkouts == 0 {
                    emptyState
                } else {
                    switch section {
                    case .overview: overview
                    case .lifts: LiftsListView(lifts: lifts)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .statusBarBackdrop()
        .onAppear(perform: reload)
    }

    private func reload() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        let data = ProgressStatsService(localStorage: environment.localStorageService).loadProgress(userId: userId)
        snapshot = data.snapshot
        lifts = data.lifts
        loaded = true
    }

    // MARK: - Pieces

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases) { item in
                Button { select(item) } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(section == item ? ProgressStyle.onAccent : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(section == item ? AppTheme.accent : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progress.segment.\(item.rawValue)")
                .accessibilityAddTraits(section == item ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(AppTheme.surface, in: Capsule())
    }

    private func select(_ item: Section) {
        withAnimation(.easeOut(duration: 0.15)) { sectionRaw = item.rawValue }
    }

    private var emptyState: some View {
        ProgressCard {
            VStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("No workouts yet")
                    .font(.headline).foregroundStyle(AppTheme.textPrimary)
                Text("Log your first workout and your streak, lift trends and equipment balance show up here.")
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("progress.empty")
    }

    private func sectionTitle(_ title: String, _ trailing: String? = nil) -> some View {
        HStack {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(AppTheme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing).font(.footnote).foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                StatCard(symbol: "flame.fill",
                         value: "\(snapshot.streak) \(snapshot.streak == 1 ? "day" : "days")",
                         caption: "Current streak", identifier: "progress.streak")
                StatCard(symbol: "calendar",
                         value: String(format: "%.1f\u{00D7}", snapshot.averageWorkoutsPerWeek),
                         caption: "Workouts / week", identifier: "progress.perWeek")
            }
            HStack(spacing: 12) {
                StatCard(symbol: "figure.strengthtraining.traditional",
                         value: "\(snapshot.daysTrainedThisWeek) of 7",
                         caption: "Days this week", identifier: "progress.daysThisWeek")
                StatCard(symbol: "number",
                         value: "\(snapshot.totalSetsThisWeek)",
                         caption: "Sets this week", identifier: "progress.setsThisWeek")
            }
            ProgressCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Training", "last 13 weeks")
                    HeatmapView(cells: snapshot.heatmap, start: snapshot.heatmapStart,
                                summaries: snapshot.daySummaries)
                }
            }
            trends
            monthCompare
            equipmentCard
        }
    }

    private var trends: some View {
        ProgressCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Top lift trends", "est. 1RM")
                if snapshot.topLifts.isEmpty {
                    Text("Log sets with weight and reps to see lift trends.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
                ForEach(Array(snapshot.topLifts.enumerated()), id: \.element.id) { index, lift in
                    if index > 0 { Divider().overlay(AppTheme.border) }
                    LiftTrendRow(lift: lift, weekStarts: snapshot.liftWeekStarts, expanded: true,
                                 detailKey: lift.key)
                }
                if !lifts.isEmpty {
                    Divider().overlay(AppTheme.border)
                    Button { select(.lifts) } label: {
                        HStack {
                            Text("See all lifts")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(lifts.count)").font(.subheadline)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progress.seeAllLifts")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.trends")
    }

    private var monthCompare: some View {
        ProgressCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("This month vs last")
                if snapshot.topLifts.isEmpty {
                    Text("Nothing to compare yet.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
                ForEach(snapshot.topLifts) { lift in monthRow(lift) }
            }
        }
        .accessibilityIdentifier("progress.monthCompare")
    }

    private func setText(_ set: BestSet?) -> String {
        guard let set else { return "\u{2014}" }
        return "\(Int(set.weightLbs.rounded())) \u{00D7} \(set.reps)"
    }

    private func monthRow(_ lift: LiftTrend) -> some View {
        let change: Double? = {
            guard let now = lift.thisMonth, let before = lift.lastMonth else { return nil }
            return now.e1rm - before.e1rm
        }()
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Best \(lift.name) set")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(setText(lift.thisMonth))  (last month \(setText(lift.lastMonth)))")
                    .font(.system(.footnote, design: .rounded)).foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 4)
            if let change {
                let rounded = Int(change.rounded())
                let up = change >= 0
                HStack(spacing: 4) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                    Text(up ? "+\(rounded) lb" : "\u{2212}\(-rounded) lb")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(up ? AppTheme.accent : AppTheme.warning)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background((up ? AppTheme.accent : AppTheme.warning).opacity(0.14), in: Capsule())
            }
        }
    }

    // MARK: - Equipment

    /// Sets per equipment type this week, most first; types with none are left out.
    private var equipmentCard: some View {
        let rows = EquipmentKind.allCases
            .map { (kind: $0, sets: snapshot.equipmentThisWeek[$0] ?? 0) }
            .filter { $0.sets > 0 }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.kind.name < $1.kind.name }
        let maxSets = max(1, rows.map(\.sets).max() ?? 1)
        return ProgressCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Sets by equipment", "This week")
                if rows.isEmpty {
                    Text("No sets logged this week.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("progress.equipmentEmpty")
                }
                ForEach(rows, id: \.kind) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.kind.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer(minLength: 8)
                            Text("\(row.sets) \(row.sets == 1 ? "set" : "sets")")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppTheme.surfaceElevated)
                                Capsule().fill(AppTheme.accent)
                                    .frame(width: proxy.size.width * max(0.04, CGFloat(row.sets) / CGFloat(maxSets)))
                            }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.kind.name), \(row.sets) sets")
                    .accessibilityIdentifier("progress.equipmentRow.\(row.kind.name)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.equipmentCard")
    }
}
