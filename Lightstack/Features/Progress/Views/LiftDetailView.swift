import SwiftUI

/// Pushed from the Progress tab: one lift's numbers, trend chart and every session.
struct LiftDetailView: View {
    let lift: LiftSummary
    /// Reloads Progress data when the page comes back from a workout (it may have been edited).
    var refresh: () -> Void = {}

    @AppStorage("weightUnit") private var weightUnitRaw = "lbs"
    @State private var metric: Metric = .estMax
    @State private var selection: Int?
    @State private var appearedOnce = false

    enum Metric: String, CaseIterable, Identifiable {
        case estMax = "Est. max", topWeight = "Top weight", volume = "Volume"
        var id: String { rawValue }
        var identifier: String {
            switch self {
            case .estMax: return "est"
            case .topWeight: return "top"
            case .volume: return "volume"
            }
        }
    }

    private var unit: BodyWeightUnit { weightUnitRaw == "kg" ? .kg : .lb }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                tiles
                chartCard
                sessionsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .onAppear {
            if appearedOnce { refresh() }
            appearedOnce = true
        }
        .accessibilityIdentifier("liftDetail")
    }

    // MARK: - Header and tiles

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lift.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("liftDetail.title")
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("liftDetail.subtitle")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !lift.muscleGroup.isEmpty { parts.append(lift.muscleGroup) }
        var sessions = "\(lift.sessionCount) \(lift.sessionCount == 1 ? "session" : "sessions")"
        if let first = lift.firstDate { sessions += " since \(LiftFormat.date(first))" }
        parts.append(sessions)
        return parts.joined(separator: " \u{00B7} ")
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile("Est. 1-rep max",
                 LiftFormat.weight(lift.currentE1RM, unit: unit, perArm: lift.isPerArm),
                 caption: changeCaption, captionColor: LiftFormat.changeColor(lift.change),
                 id: "liftDetail.tile.e1rm")
            tile("Best set",
                 LiftFormat.setText(weightLbs: lift.bestSet.weightLbs, reps: lift.bestSet.reps, unit: unit),
                 caption: LiftFormat.date(lift.bestSet.date), captionColor: AppTheme.textSecondary,
                 id: "liftDetail.tile.best")
            tile("Heaviest",
                 LiftFormat.weight(lift.heaviest.weightLbs, unit: unit, perArm: lift.isPerArm),
                 caption: LiftFormat.date(lift.heaviest.date), captionColor: AppTheme.textSecondary,
                 id: "liftDetail.tile.heaviest")
        }
    }

    private var changeCaption: String {
        switch lift.change {
        case .new: return "New"
        case .even: return "Even, 30 days"
        case .delta: return "\(LiftFormat.change(lift.change, unit: unit)), 30 days"
        }
    }

    private func tile(_ title: String, _ value: String, caption: String, captionColor: Color,
                      id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption.weight(.semibold)).foregroundStyle(captionColor)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: - Chart

    private var series: [Double?] {
        lift.sessions.map { session in
            switch metric {
            case .estMax: return unit.fromLbs(session.e1rm)
            case .topWeight: return unit.fromLbs(session.topWeightLbs)
            case .volume: return unit.fromLbs(session.volumeLbs)
            }
        }
    }

    private var chartCard: some View {
        let values = series
        let numbers = values.compactMap { $0 }
        let spread = (numbers.max() ?? 0) - (numbers.min() ?? 0)
        let padding = max(1, spread * 0.15, (numbers.max() ?? 0) * 0.02)
        return VStack(spacing: 12) {
            metricPicker
            LiftChartView(
                values: values,
                weekStarts: lift.sessions.map(\.date),
                perArm: lift.isPerArm,
                calloutText: { date, value in
                    "\(LiftFormat.date(date ?? Date())) \u{00B7} \(Int(value.rounded())) \(unit.rawValue) \(metric.callSuffix)"
                },
                labelStride: max(2, lift.sessions.count / 3),
                yPadding: padding,
                selection: $selection)
                .frame(height: 170)
                .padding(.top, 30)
                .accessibilityIdentifier("liftDetail.chart")
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var metricPicker: some View {
        HStack(spacing: 0) {
            ForEach(Metric.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { metric = item }
                    selection = nil
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(metric == item ? AppTheme.onAccent : AppTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(metric == item ? AppTheme.accent : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("liftDetail.metric.\(item.identifier)")
                .accessibilityAddTraits(metric == item ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(AppTheme.surfaceElevated, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liftDetail.metric")
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent sessions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                if lift.sessions.contains(where: { $0.sets.contains(where: \.isWarmup) }) {
                    Text("Lighter sets are warm-ups")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
            }
            let sessions = lift.recentSessions
            LazyVStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider().overlay(AppTheme.border) }
                    NavigationLink(value: LiftSessionRoute(workoutId: session.workoutId)) {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("liftDetail.session.\(index)")
                }
            }
            .padding(.horizontal, 14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func sessionRow(_ session: LiftSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle(session))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                setsText(session)
                    .font(.footnote)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if session.workoutId == lift.bestSet.workoutId {
                Text("Best set")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.14), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func rowTitle(_ session: LiftSession) -> String {
        let day = session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let name = session.workoutName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? day : "\(day) \u{00B7} \(name)"
    }

    /// "95 × 8 · 135 × 8", warm-ups in a lighter tone.
    private func setsText(_ session: LiftSession) -> Text {
        var text = Text("")
        for (index, set) in session.sets.enumerated() {
            if index > 0 {
                text = text + Text(" \u{00B7} ").foregroundColor(AppTheme.textSecondary)
            }
            let piece = Text(LiftFormat.setText(weightLbs: set.weightLbs, reps: set.reps, unit: unit))
            text = text + (set.isWarmup
                ? piece.foregroundColor(AppTheme.textSecondary.opacity(0.6)).italic()
                : piece.foregroundColor(AppTheme.textSecondary))
        }
        return text
    }
}

private extension LiftDetailView.Metric {
    var callSuffix: String {
        switch self {
        case .estMax: return "est. 1RM"
        case .topWeight: return "top weight"
        case .volume: return "volume"
        }
    }
}

/// Navigation value for a lift session: opens that workout's history detail.
struct LiftSessionRoute: Hashable {
    let workoutId: UUID
}

/// Resolves a workout by id and shows the existing history detail for it.
struct LiftSessionDestination: View {
    @EnvironmentObject var environment: AppEnvironment
    let workoutId: UUID
    @State private var resolved: (workout: Workout, model: HistoryViewModel)?

    var body: some View {
        Group {
            if let resolved {
                WorkoutDetailView(workout: resolved.workout, viewModel: resolved.model)
            } else {
                AppTheme.background.ignoresSafeArea()
            }
        }
        .onAppear {
            guard resolved == nil, let entity = environment.localStorageService.fetchWorkout(id: workoutId) else { return }
            resolved = (Workout(from: entity), environment.makeHistoryViewModel())
        }
    }
}
