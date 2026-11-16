import SwiftUI
import Charts

/// Progress > Lifts: every strength lift ever logged, A to Z, with search.
struct LiftsListView: View {
    let lifts: [LiftSummary]
    @AppStorage("weightUnit") private var weightUnitRaw = "lbs"
    @State private var query = ""

    private var unit: BodyWeightUnit { weightUnitRaw == "kg" ? .kg : .lb }

    private var filtered: [LiftSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return lifts }
        return lifts.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.muscleGroup.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        if lifts.isEmpty {
            ProgressCard {
                VStack(spacing: 10) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("No lifts yet")
                        .font(.headline).foregroundStyle(AppTheme.textPrimary)
                    Text("Log sets with weight and reps and every lift shows up here with its progress.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .accessibilityIdentifier("progress.lifts.empty")
        } else {
            let rows = filtered
            VStack(spacing: 14) {
                searchField
                HStack {
                    Text("\(rows.count) \(rows.count == 1 ? "lift" : "lifts"), A to Z")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("progress.lifts.count")
                    Spacer()
                    Text("Estimated 1-rep max")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if rows.isEmpty {
                    Text("No lifts match \u{201C}\(query)\u{201D}.")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .accessibilityIdentifier("progress.lifts.noMatch")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, lift in
                            if index > 0 { Divider().overlay(AppTheme.border) }
                            NavigationLink(value: lift.key) {
                                LiftListRow(lift: lift, unit: unit)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("progress.lift.\(lift.name)")
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(AppTheme.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("progress.liftsList")
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textSecondary)
            TextField("Search your lifts", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("progress.lifts.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// One row of the Lifts list: name and facts, tiny 1RM trend, current 1RM and 30-day change.
private struct LiftListRow: View {
    let lift: LiftSummary
    let unit: BodyWeightUnit

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            MiniTrend(values: lift.sessions.map(\.e1rm), tint: LiftFormat.changeColor(lift.change))
                .frame(width: 56, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 1) {
                Text(LiftFormat.weight(lift.currentE1RM, unit: unit, perArm: lift.isPerArm))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(LiftFormat.change(lift.change, unit: unit))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LiftFormat.changeColor(lift.change))
                    .lineLimit(1)
            }
            .frame(width: 84, alignment: .trailing)
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !lift.muscleGroup.isEmpty { parts.append(lift.muscleGroup) }
        parts.append("\(lift.sessionCount) \(lift.sessionCount == 1 ? "session" : "sessions")")
        if let last = lift.lastDate { parts.append(LiftFormat.date(last)) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// Non-interactive line sparkline (taps pass through to the row).
struct MiniTrend: View {
    let values: [Double]
    var tint: Color = AppTheme.accent

    var body: some View {
        let low = values.min() ?? 0
        let high = max(values.max() ?? 1, low + 1)
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Session", index), y: .value("1RM", value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let last = values.last {
                PointMark(x: .value("Session", values.count - 1), y: .value("1RM", last))
                    .foregroundStyle(tint).symbolSize(24)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: -0.2...(Double(max(1, values.count - 1)) + 0.2))
        .chartYScale(domain: low...high)
        .allowsHitTesting(false)
    }
}
