import SwiftUI
import Charts

/// Area + line sparkline over weekly values; gaps are skipped.
struct SparklineView: View {
    let values: [Double?]

    var body: some View {
        let points = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        let low = (points.map(\.1).min() ?? 0) - 4
        let high = (points.map(\.1).max() ?? 1) + 4
        Chart {
            ForEach(points, id: \.0) { i, v in
                AreaMark(x: .value("Week", i), yStart: .value("Base", low), yEnd: .value("1RM", v))
                    .foregroundStyle(LinearGradient(colors: [AppTheme.accent.opacity(0.35), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Week", i), y: .value("1RM", v))
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            if let last = points.last {
                PointMark(x: .value("Week", last.0), y: .value("1RM", last.1))
                    .foregroundStyle(AppTheme.accent).symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(1, values.count - 1))
        .chartYScale(domain: low...high)
        .clipped()
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

/// One lift: name, current e1RM, month delta and a sparkline.
struct LiftTrendRow: View {
    let lift: LiftTrend

    private var latest: Double { lift.weeklyE1RM.compactMap { $0 }.last ?? lift.allTimeBest }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lift.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(LiftFormat.lb(latest))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(LiftFormat.delta(lift))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LiftFormat.deltaColor(lift))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            if lift.weeklyE1RM.compactMap({ $0 }).count >= 2 {
                SparklineView(values: lift.weeklyE1RM).frame(width: 110, height: 52)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.lift.\(lift.name)")
    }
}
