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
    static func callout(date: Date?, value: Double, perArm: Bool = false) -> String {
        "\(weekLabel(date)) \u{00B7} \(LiftFormat.lb(value, perArm: perArm)) est. 1RM"
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
    var perArm = false
    /// Custom callout text for the selected point (date, value); default is the weekly est. 1RM text.
    var calloutText: ((Date?, Double) -> String)?
    /// Distance between x-axis labels (in points).
    var labelStride = 2
    /// Padding above and below the data in the y scale.
    var yPadding: Double = 8
    @Binding var selection: Int?

    var body: some View {
        let points = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        let low = ((points.map(\.1).min() ?? 0) - yPadding).rounded(.down)
        let high = ((points.map(\.1).max() ?? 1) + yPadding).rounded(.up)
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
                        let pickedDate = weekStarts.indices.contains(picked.index) ? weekStarts[picked.index] : nil
                        Text(calloutText?(pickedDate, picked.value)
                             ?? LiftChartSelection.callout(date: pickedDate, value: picked.value, perArm: perArm))
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
            AxisMarks(values: Array(stride(from: lastIndex % labelStride, through: lastIndex, by: labelStride))) { value in
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
    static func lb(_ value: Double, perArm: Bool = false) -> String {
        "\(Int(value.rounded())) lb" + (perArm ? " / arm" : "")
    }

    /// "171 lb" / "78 kg" in the user's unit (stored weights are pounds), "/ arm" for per-arm lifts.
    static func weight(_ lbs: Double, unit: BodyWeightUnit, perArm: Bool = false) -> String {
        "\(Int(unit.fromLbs(lbs).rounded())) \(unit.rawValue)" + (perArm ? " / arm" : "")
    }

    /// Weight number only ("135", "61.2").
    static func number(_ lbs: Double, unit: BodyWeightUnit) -> String {
        let value = (unit.fromLbs(lbs) * 10).rounded() / 10
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// "135 \u{00D7} 8"
    static func setText(weightLbs: Double, reps: Int, unit: BodyWeightUnit) -> String {
        "\(number(weightLbs, unit: unit)) \u{00D7} \(reps)"
    }

    /// "+15 lb", "\u{2212}10 lb", "Even" or "New".
    static func change(_ change: LiftChange, unit: BodyWeightUnit) -> String {
        switch change {
        case .new: return "New"
        case .even: return "Even"
        case .delta(let lbs):
            let rounded = Int(unit.fromLbs(lbs).rounded())
            if rounded == 0 { return "Even" }
            return rounded > 0 ? "+\(rounded) \(unit.rawValue)" : "\u{2212}\(-rounded) \(unit.rawValue)"
        }
    }

    static func changeColor(_ change: LiftChange) -> Color {
        switch change {
        case .new, .even: return AppTheme.textSecondary
        case .delta(let lbs): return lbs < 0 ? AppTheme.warning : AppTheme.accent
        }
    }

    /// "Nov 14", with the year when it is not this year.
    static func date(_ date: Date, now: Date = Date()) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "+15 lb, 30 days", "Even" or "New", same wording as the Lifts list.
    static func delta(_ lift: LiftTrend) -> String {
        switch lift.change {
        case .new: return "New"
        case .even: return "Even"
        case .delta:
            let text = change(lift.change, unit: .lb)
            return text == "Even" ? text : "\(text), 30 days"
        }
    }

    static func deltaColor(_ lift: LiftTrend) -> Color {
        changeColor(lift.change)
    }
}

/// One lift: name, current e1RM, month delta and a trend chart.
/// `expanded` draws a full-width chart with axes; otherwise a compact sparkline.
struct LiftTrendRow: View {
    let lift: LiftTrend
    var weekStarts: [Date] = []
    var expanded = false
    /// When set (expanded rows), a "Details" link opens that lift's detail page.
    var detailKey: String?
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
                    Text(LiftFormat.lb(picked?.value ?? latest, perArm: lift.isPerArm))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(picked == nil || expanded ? LiftFormat.deltaColor(lift) : AppTheme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if expanded, let detailKey {
                    NavigationLink(value: detailKey) {
                        HStack(spacing: 2) {
                            Text("Details").font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progress.trendOpen.\(lift.name)")
                }
                if !expanded, pointCount >= 2 {
                    SparklineView(values: lift.weeklyE1RM, selection: $selection)
                        .frame(width: 110, height: 52)
                        .accessibilityIdentifier("lift.sparkline.\(lift.name)")
                }
            }
            if expanded, pointCount >= 1 {
                LiftChartView(values: lift.weeklyE1RM, weekStarts: weekStarts, perArm: lift.isPerArm, selection: $selection)
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
