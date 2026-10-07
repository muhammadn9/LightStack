#if DEBUG
import SwiftUI
import Charts

/// DEBUG-only design lab: static mock screens with hard-coded data.
/// Launch with `-designLab -designVariant A|B -designScreen today|stats|workout`.
struct DesignLabView: View {
    private let theme = DLTheme(variant: DesignLabConfig.variant)
    private let screen = DesignLabConfig.screen

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                switch screen {
                case .today: DLTodayScreen()
                case .stats: DLStatsScreen()
                case .workout: DLWorkoutScreen()
                }
                DLTabBar(selected: screen == .stats ? 2 : 0)
            }
        }
        .environment(\.dlTheme, theme)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("designLab.root")
    }
}

// MARK: - Today

private struct EquipUse: Identifiable {
    let kind: EquipmentKind
    let sets: Int
    var id: EquipmentKind { kind }
    var intensity: Double { sets == 0 ? 0 : min(1, 0.35 + Double(sets) / 18) }
}

private let sampleUse: [EquipUse] = [
    EquipUse(kind: .barbell, sets: 12), EquipUse(kind: .dumbbells, sets: 9),
    EquipUse(kind: .kettlebell, sets: 0), EquipUse(kind: .cable, sets: 6),
    EquipUse(kind: .machine, sets: 0), EquipUse(kind: .bench, sets: 8),
    EquipUse(kind: .bodyweight, sets: 0)
]

struct DLTodayScreen: View {
    @Environment(\.dlTheme) private var t

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                DLWeekStrip()
                hero
                DLPillButton(title: "Start Workout", icon: "play.fill")
                plan
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Good evening, Muhammad")
                    .font(t.heading(26)).foregroundStyle(t.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Thursday, Oct 8")
                    .font(t.isNotebook ? t.note(14) : t.label(15, weight: .medium))
                    .foregroundStyle(t.subtext)
            }
            Spacer(minLength: 0)
        }
    }

    private var hero: some View {
        DLCard(margin: true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("4 of 7").font(t.number(40)).foregroundStyle(t.text)
                        Text("57%").font(t.number(18)).foregroundStyle(t.accent)
                    }
                    Text("Equipment Worked This Week")
                        .font(t.isNotebook ? t.note(14) : t.label(15, weight: .medium))
                        .foregroundStyle(t.subtext)
                }
                let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(sampleUse) { use in
                        VStack(spacing: 5) {
                            DLEquipmentIcon(kind: use.kind, style: t.isNotebook ? .ink : .filled,
                                          intensity: use.intensity)
                                .padding(.horizontal, 6)
                            Text(use.kind.name)
                                .font(t.label(11, weight: .medium))
                                .foregroundStyle(use.sets > 0 ? t.text : t.subtext)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(use.sets > 0 ? "\(use.sets) sets" : "not yet")
                                .font(t.note(11))
                                .foregroundStyle(use.sets > 0 ? t.accent : t.dim)
                        }
                    }
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().stroke(t.field, lineWidth: 5)
                            Circle().trim(from: 0, to: 0.57)
                                .stroke(t.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("35").font(t.number(17)).foregroundStyle(t.text)
                        }
                        .frame(width: 44, height: 44)
                        .frame(maxHeight: 50)
                        Text("Total sets").font(t.label(11, weight: .medium)).foregroundStyle(t.subtext)
                    }
                }
            }
        }
    }

    private var plan: some View {
        DLCard(margin: true) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's plan").font(t.isNotebook ? t.note(13) : t.label(13, weight: .medium))
                        .foregroundStyle(t.subtext)
                    Text("Push").font(t.heading(24)).foregroundStyle(t.text)
                    HStack(spacing: 8) {
                        DLChip(text: "5 exercises", icon: "list.bullet")
                        DLChip(text: "~50 min", icon: "clock")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(t.subtext)
            }
        }
    }
}

// MARK: - Stats

private struct Trend: Identifiable {
    let name: String
    let value: String
    let delta: String
    let data: [Double]
    var id: String { name }
}

private let sampleTrends: [Trend] = [
    Trend(name: "Bench Press", value: "190 lb", delta: "+15 lb this month",
          data: [165, 167, 170, 172, 177, 180, 185, 190]),
    Trend(name: "Squat", value: "265 lb", delta: "+20 lb this month",
          data: [225, 230, 235, 240, 245, 250, 255, 265]),
    Trend(name: "Overhead Press", value: "110 lb", delta: "+5 lb this month",
          data: [95, 97, 97, 100, 102, 105, 107, 110])
]

struct DLStatsScreen: View {
    @Environment(\.dlTheme) private var t

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Progress").font(t.heading(34)).foregroundStyle(t.text)
                    Spacer()
                }
                segmented
                HStack(spacing: 12) {
                    statTile(symbol: "flame.fill", value: "6 days", caption: "Current streak")
                    statTile(symbol: "calendar", value: "3.5×", caption: "Per week")
                }
                heatmap
                trends
                monthCompare
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Overview", "Lifts", "Equipment"].enumerated()), id: \.offset) { i, title in
                Text(title)
                    .font(t.label(14, weight: .semibold))
                    .foregroundStyle(i == 0 ? t.onAccent : t.subtext)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(i == 0 ? t.accent : .clear, in: Capsule())
            }
        }
        .padding(3)
        .background(t.card, in: Capsule())
    }

    private func statTile(symbol: String, value: String, caption: String) -> some View {
        DLCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(t.accent)
                Text(value).font(t.number(28)).foregroundStyle(t.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(caption).font(t.note(12)).foregroundStyle(t.subtext)
            }
        }
    }

    private var heatmap: some View {
        DLCard {
            VStack(alignment: .leading, spacing: 12) {
                DLSectionTitle(title: "Training", trailing: "last 13 weeks")
                DLHeatmap()
                HStack(spacing: 4) {
                    Text("Less").font(t.note(11)).foregroundStyle(t.subtext)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(i == 0 ? Color.white.opacity(0.07) : t.accent.opacity([0, 0.3, 0.5, 0.75, 1][i]))
                            .frame(width: 11, height: 11)
                    }
                    Text("More").font(t.note(11)).foregroundStyle(t.subtext)
                    Spacer()
                }
            }
        }
    }

    private var trends: some View {
        DLCard(margin: true) {
            VStack(alignment: .leading, spacing: 14) {
                DLSectionTitle(title: "Top lift trends", trailing: "est. 1RM")
                ForEach(Array(sampleTrends.enumerated()), id: \.element.id) { i, trend in
                    if i > 0 { Rectangle().fill(t.hairline).frame(height: 1) }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(trend.name).font(t.label(15)).foregroundStyle(t.text)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Text(trend.value).font(t.number(22)).foregroundStyle(t.text)
                            Text(trend.delta).font(t.note(12)).foregroundStyle(t.accent)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 4)
                        miniChart(trend.data).frame(width: 110, height: 52)
                    }
                }
            }
        }
    }

    private func miniChart(_ data: [Double]) -> some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("Week", i), yStart: .value("Base", (data.min() ?? 0) - 4), yEnd: .value("1RM", v))
                    .foregroundStyle(LinearGradient(colors: [t.accent.opacity(0.35), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Week", i), y: .value("1RM", v))
                    .foregroundStyle(t.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            if let last = data.last {
                PointMark(x: .value("Week", data.count - 1), y: .value("1RM", last))
                    .foregroundStyle(t.accent).symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (data.min() ?? 0) - 4...(data.max() ?? 1) + 4)
        .clipped()
    }

    private var monthCompare: some View {
        DLCard {
            VStack(alignment: .leading, spacing: 12) {
                DLSectionTitle(title: "This month vs last")
                monthRow("Best bench set", "185 × 5", "+10 lb", up: true)
                monthRow("Weekly volume", "42.1k lb", "+8%", up: true)
                monthRow("Best squat set", "250 × 3", "−5 lb", up: false)
            }
        }
    }

    private func monthRow(_ title: String, _ value: String, _ delta: String, up: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(t.label(14)).foregroundStyle(t.text)
                Text(value).font(t.mono(13)).foregroundStyle(t.subtext)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                Text(delta).font(t.label(14, weight: .bold))
            }
            .foregroundStyle(up ? t.accent : t.danger)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((up ? t.accent : t.danger).opacity(0.14), in: Capsule())
        }
    }
}

// MARK: - Workout

struct DLWorkoutScreen: View {
    @Environment(\.dlTheme) private var t

    private struct SetRow { let n: Int; let lbs: String; let reps: String; let rir: String; let state: Int; let pr: Bool }
    // state: 0 pending, 1 logged, 2 active
    private let rows: [SetRow] = [
        SetRow(n: 1, lbs: "135", reps: "8", rir: "3", state: 1, pr: false),
        SetRow(n: 2, lbs: "155", reps: "8", rir: "2", state: 1, pr: false),
        SetRow(n: 3, lbs: "175", reps: "6", rir: "1", state: 1, pr: true),
        SetRow(n: 4, lbs: "175", reps: "6", rir: "2", state: 2, pr: false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    exerciseCard
                    pager
                    upNext
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            restPill
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Push Day").font(t.heading(28)).foregroundStyle(t.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Image(systemName: "timer").font(.system(size: 13, weight: .semibold))
                    Text("42:18").font(t.mono(15))
                }
                .foregroundStyle(t.accent)
            }
            Spacer(minLength: 8)
            Text("End")
                .font(t.label(15, weight: .bold))
                .foregroundStyle(t.danger)
                .padding(.horizontal, 20).frame(height: 40)
                .background(t.danger.opacity(0.15), in: Capsule())
        }
    }

    private var exerciseCard: some View {
        DLCard(margin: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bench Press").font(t.heading(24)).foregroundStyle(t.text)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("Chest · 4 sets")
                            .font(t.isNotebook ? t.note(14) : t.label(14, weight: .medium))
                            .foregroundStyle(t.subtext)
                    }
                    Spacer(minLength: 6)
                    DLEquipmentIcon(kind: .barbell, style: t.isNotebook ? .ink : .filled, intensity: 0.8)
                        .frame(width: 44, height: 44)
                }
                HStack(spacing: 8) {
                    Color.clear.frame(width: 30, height: 1)
                    ForEach(["LBS", "REPS", "RIR"], id: \.self) { h in
                        Text(h).font(t.label(11, weight: .bold)).foregroundStyle(t.subtext)
                            .frame(maxWidth: .infinity)
                    }
                    Color.clear.frame(width: 40, height: 1)
                }
                VStack(spacing: 10) {
                    ForEach(rows, id: \.n) { row in setRow(row) }
                }
            }
        }
    }

    private func setRow(_ r: SetRow) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(t.field)
                Text("\(r.n)").font(t.mono(14)).foregroundStyle(t.subtext)
            }
            .frame(width: 30, height: 30)
            field(r.lbs, active: r.state == 2)
                .overlay(alignment: .topTrailing) {
                    if r.pr { DLPRBadge().scaleEffect(0.8).offset(x: 8, y: -14) }
                }
            field(r.reps, active: r.state == 2)
            field(r.rir, active: r.state == 2)
            ZStack {
                Circle().fill(r.state == 1 ? t.accent : t.field)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(r.state == 1 ? t.onAccent : t.dim)
            }
            .frame(width: 40, height: 40)
        }
    }

    private func field(_ value: String, active: Bool) -> some View {
        Text(value)
            .font(t.mono(18))
            .foregroundStyle(t.text)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(t.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.accent, lineWidth: 1.5)
                }
            }
    }

    private var pager: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule().fill(i == 1 ? t.accent : t.field)
                            .frame(width: i == 1 ? 22 : 7, height: 7)
                    }
                }
                Text("2 of 5").font(t.isNotebook ? t.note(14) : t.label(14, weight: .medium))
                    .foregroundStyle(t.subtext)
            }
            HStack(spacing: 0) {
                DLIconButton(symbol: "chevron.left").frame(maxWidth: .infinity)
                DLIconButton(symbol: "ellipsis").frame(maxWidth: .infinity)
                DLIconButton(symbol: "plus").frame(maxWidth: .infinity)
                DLIconButton(symbol: "chevron.right", prominent: true).frame(maxWidth: .infinity)
            }
        }
    }

    private var upNext: some View {
        DLCard(padding: 16) {
            HStack(spacing: 12) {
                DLEquipmentIcon(kind: .dumbbells, style: t.isNotebook ? .ink : .filled, intensity: 0)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up next").font(t.note(12)).foregroundStyle(t.subtext)
                    Text("Incline DB Press").font(t.label(16)).foregroundStyle(t.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text("3 sets · 10 reps").font(t.mono(12)).foregroundStyle(t.subtext)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var restPill: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(t.onAccent.opacity(0.2), lineWidth: 3.5)
                Circle().trim(from: 0, to: 0.62)
                    .stroke(t.onAccent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)
            Text("Rest").font(t.label(15, weight: .semibold))
            Text("1:24").font(t.mono(20))
            Spacer(minLength: 4)
            Text("Skip").font(t.label(14, weight: .bold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(t.onAccent.opacity(0.14), in: Capsule())
        }
        .foregroundStyle(t.onAccent)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(t.accent, in: Capsule())
        .shadow(color: t.accent.opacity(0.3), radius: 12, y: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }
}
#endif
