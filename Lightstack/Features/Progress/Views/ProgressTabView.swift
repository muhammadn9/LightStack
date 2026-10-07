import SwiftUI
import Charts

/// Progress tab: streak and consistency, lift trends, and equipment balance.
struct ProgressTabView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var snapshot = ProgressSnapshot()
    @State private var loaded = false
    @State private var section: Section = .overview

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", lifts = "Lifts", equipment = "Equipment"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("progress.title")
                    Spacer()
                }
                segmented
                if loaded && snapshot.totalWorkouts == 0 {
                    emptyState
                } else {
                    switch section {
                    case .overview: overview
                    case .lifts: lifts
                    case .equipment: equipment
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .onAppear(perform: reload)
    }

    private func reload() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        snapshot = ProgressStatsService(localStorage: environment.localStorageService).snapshot(userId: userId)
        loaded = true
    }

    // MARK: - Pieces

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases) { item in
                Button { withAnimation(.easeOut(duration: 0.15)) { section = item } } label: {
                    Text(item.rawValue)
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
                    HeatmapView(cells: snapshot.heatmap)
                }
            }
            trends
            monthCompare
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
                    LiftTrendRow(lift: lift)
                }
            }
        }
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

    // MARK: - Lifts

    private var lifts: some View {
        ProgressCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Top lifts", "est. 1RM, last 8 weeks")
                if snapshot.lifts.isEmpty {
                    Text("Log sets with weight and reps to see your lifts.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                }
                ForEach(Array(snapshot.lifts.enumerated()), id: \.element.id) { index, lift in
                    if index > 0 { Divider().overlay(AppTheme.border) }
                    LiftTrendRow(lift: lift)
                }
            }
        }
        .accessibilityIdentifier("progress.liftsList")
    }

    // MARK: - Equipment

    private var equipment: some View {
        VStack(spacing: 18) {
            EquipmentWeekCard(usage: snapshot.equipmentThisWeek)
            ProgressCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("Sets by equipment", "last 4 weeks")
                    ForEach(EquipmentKind.allCases) { kind in
                        equipmentRow(kind)
                    }
                }
            }
            .accessibilityIdentifier("progress.equipmentWeeks")
        }
    }

    private func equipmentRow(_ kind: EquipmentKind) -> some View {
        let perWeek = snapshot.equipmentByWeek.map { $0[kind] ?? 0 }
        let total = perWeek.reduce(0, +)
        return HStack(spacing: 12) {
            EquipmentIcon(kind: kind, intensity: total > 0 ? 0.7 : 0)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                Text("\(total) sets").font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 4)
            Chart {
                ForEach(Array(perWeek.enumerated()), id: \.offset) { index, sets in
                    BarMark(x: .value("Week", index), y: .value("Sets", sets))
                        .foregroundStyle(index == perWeek.count - 1 ? AppTheme.accent : AppTheme.accent.opacity(0.4))
                        .cornerRadius(3)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...max(1, perWeek.max() ?? 1))
            .frame(width: 80, height: 34)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.equipmentRow.\(kind.name)")
    }
}
