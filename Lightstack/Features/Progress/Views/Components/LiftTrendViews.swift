import SwiftUI
import Charts

/// Nearest weekly point to a selected x position (weeks with no data are skipped).
enum LiftChartSelection {
    static func nearest(_ selection: Int?, in values: [Double?]) -> (index: Int, value: Double)? {
        guard let selection else { return nil }
        let points = values.enumerated().compactMap { i, v in v.map { (index: i, value: $0) } }
        return points.min { abs($0.index - selection) < abs($1.index - selection) }
    }

    static func weekLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Sep 22 · 185 lb est. 1RM" (the date is the Monday of that week).
    static func callout(date: Date?, value: Double) -> String {
        "\(weekLabel(date)) \u{00B7} \(LiftFormat.lb(value)) est. 1RM"
    }
}

extension View {
    /// Tap a chart to pin the nearest point (tap it again to clear). Drag selection still works too.
    func liftTapSelection(_ selection: Binding<Int?>, values: [Double?]) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let plot = proxy.plotFrame else { return }
                        let x = tap.location.x - geo[plot].origin.x
                        guard let raw: Double = proxy.value(atX: x),
                              let hit = LiftChartSelection.nearest(Int(raw.rounded()), in: values) else { return }
                        let current = LiftChartSelection.nearest(selection.wrappedValue, in: values)?.index
                        selection.wrappedValue = current == hit.index ? nil : hit.index
                    })
            }
        }
    }
}

/// Area + line sparkline over weekly values; gaps are skipped. Drag to read a value.
struct SparklineView: View {
    let values: [Double?]
    @Binding var selection: Int?

    var body: some View {
        let points = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        let low = (points.map(\.1).min() ?? 0) - 4
        let high = (points.map(\.1).max() ?? 1) + 4
        let picked = LiftChartSelection.nearest(selection, in: values)
        Chart {
            ForEach(points, id: \.0) { i, v in
                AreaMark(x: .value("Week", i), yStart: .value("Base", low), yEnd: .value("1RM", v))
                    .foregroundStyle(LinearGradient(colors: [AppTheme.accent.opacity(0.35), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Week", i), y: .value("1RM", v))
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            if let picked {
                RuleMark(x: .value("Week", picked.index))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Week", picked.index), y: .value("1RM", picked.value))
                    .foregroundStyle(AppTheme.accent).symbolSize(70)
            } else if let last = points.last {
                PointMark(x: .value("Week", last.0), y: .value("1RM", last.1))
                    .foregroundStyle(AppTheme.accent).symbolSize(40)
            }
        }
        .chartXSelection(value: $selection)
        .liftTapSelection($selection, values: values)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: -0.15...(Double(max(1, values.count - 1)) + 0.15))
        .chartYScale(domain: low...high)
        .clipped()
    }
}

/// Full-width est. 1RM chart with dates on the x axis, lb on the y axis and a value callout on drag.
struct LiftChartView: View {
    let values: [Double?]
    let weekStarts: [Date]
    @Binding var selection: Int?

    var body: some View {
        let points = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        let low = ((points.map(\.1).min() ?? 0) - 8).rounded(.down)
        let high = ((points.map(\.1).max() ?? 1) + 8).rounded(.up)
        let picked = LiftChartSelection.nearest(selection, in: values)
        let lastIndex = max(1, values.count - 1)
        Chart {
            ForEach(points, id: \.0) { i, v in
                AreaMark(x: .value("Week", i), yStart: .value("Base", low), yEnd: .value("1RM", v))
                    .foregroundStyle(LinearGradient(colors: [AppTheme.accent.opacity(0.28), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Week", i), y: .value("1RM", v))
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Week", i), y: .value("1RM", v))
                    .foregroundStyle(AppTheme.accent).symbolSize(picked?.index == i ? 90 : 28)
            }
            if let picked {
                RuleMark(x: .value("Week", picked.index))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(LiftChartSelection.callout(
                            date: weekStarts.indices.contains(picked.index) ? weekStarts[picked.index] : nil,
                            value: picked.value))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityIdentifier("lift.callout")
                    }
            }
        }
        .chartXSelection(value: $selection)
        .liftTapSelection($selection, values: values)
        .chartXScale(domain: -0.6...(Double(lastIndex) + 0.6))
        .chartYScale(domain: low...high)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: lastIndex % 2, through: lastIndex, by: 2))) { value in
                AxisValueLabel(anchor: .top) {
                    if let i = value.as(Int.self), weekStarts.indices.contains(i) {
                        Text(LiftChartSelection.weekLabel(weekStarts[i]))
                            .font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v.rounded()))").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }
}

enum LiftFormat {
    static func lb(_ value: Double) -> String { "\(Int(value.rounded())) lb" }

    static func delta(_ lift: LiftTrend) -> String {
        guard lift.thisMonth != nil else { return "No sets this month" }
        guard let delta = lift.monthDelta else { return "New this month" }
        let rounded = Int(delta.rounded())
        if rounded == 0 { return "Even this month" }
        return rounded > 0 ? "+\(rounded) lb this month" : "\u{2212}\(-rounded) lb this month"
    }

    static func deltaColor(_ lift: LiftTrend) -> Color {
        (lift.monthDelta ?? 0) < -0.5 ? AppTheme.warning : AppTheme.accent
    }
}

/// One lift: name, current e1RM, month delta and a trend chart.
/// `expanded` draws a full-width chart with axes; otherwise a compact sparkline.
struct LiftTrendRow: View {
    let lift: LiftTrend
    var weekStarts: [Date] = []
    var expanded = false
    @State private var selection: Int?

    private var latest: Double { lift.weeklyE1RM.compactMap { $0 }.last ?? lift.allTimeBest }
    private var picked: (index: Int, value: Double)? {
        LiftChartSelection.nearest(selection, in: lift.weeklyE1RM)
    }
    private var pointCount: Int { lift.weeklyE1RM.compactMap { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lift.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(LiftFormat.lb(picked?.value ?? latest))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(picked == nil || expanded ? LiftFormat.deltaColor(lift) : AppTheme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if !expanded, pointCount >= 2 {
                    SparklineView(values: lift.weeklyE1RM, selection: $selection)
                        .frame(width: 110, height: 52)
                        .accessibilityIdentifier("lift.sparkline.\(lift.name)")
                }
            }
            if expanded, pointCount >= 1 {
                LiftChartView(values: lift.weeklyE1RM, weekStarts: weekStarts, selection: $selection)
                    .frame(height: 130)
                    .accessibilityIdentifier("lift.chart.\(lift.name)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.lift.\(lift.name)")
    }

    private var subtitle: String {
        guard let picked, !expanded else { return LiftFormat.delta(lift) }
        let date = weekStarts.indices.contains(picked.index) ? weekStarts[picked.index] : nil
        return "Week of \(LiftChartSelection.weekLabel(date)) \u{00B7} est. 1RM"
    }
}
