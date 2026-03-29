import SwiftUI

/// Calendar grid view showing a full month of planned sessions.
/// Days are color-coded: rest (grey), planned (default), today (highlighted),
/// completed (checkmark), missed (amber).
struct MonthPlanView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: MonthPlanViewModel
    @State private var selectedSession: PlannedSession?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.activePlan != nil {
                    calendarContent
                } else {
                    PlanBuilderWrapper(
                        environment: environment,
                        onPlanGenerated: { plan, sessions in
                            viewModel.reload(plan: plan, sessions: sessions)
                        }
                    )
                }
            }
            .navigationTitle("Month Plan")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                if let userId = environment.authService.currentUser()?.userId {
                    viewModel.setUserId(userId)
                    viewModel.loadPlan()
                }
            }
        }
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let plan = viewModel.activePlan {
                    planHeader(plan)
                }
                progressBar
                calendarGrid
            }
            .padding(16)
        }
        .themedBackground()
        .sheet(item: $selectedSession) { session in
            NavigationStack {
                PlannedSessionView(session: session, onStartWorkout: nil)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedSession = nil }
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
            }
        }
    }

    // MARK: - Plan Header

    private func planHeader(_ plan: MonthPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = plan.title {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.textPrimary)
            }

            if let overview = plan.aiOverview {
                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(3)
            }

            HStack {
                Text(DateFormatter.shortDate.string(from: plan.startDate))
                Image(systemName: "arrow.right")
                    .font(.caption)
                Text(DateFormatter.shortDate.string(from: plan.endDate))
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(viewModel.completedCount)/\(viewModel.totalTrainingDays) sessions")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.surfaceElevated)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.accentGradient)
                        .frame(width: geo.size.width * viewModel.progressFraction, height: 8)
                }
            }
            .frame(height: 8)
        }
        .cardStyle()
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            // Day headers
            HStack(spacing: 4) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar weeks
            let weeks = calendarWeeks
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, dateOpt in
                        if let date = dateOpt {
                            MonthDayTileView(
                                date: date,
                                session: viewModel.session(for: date),
                                onTap: {
                                    if let session = viewModel.session(for: date) {
                                        selectedSession = session
                                    }
                                }
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    /// Organize dates into weeks (Sun-Sat rows), with nil for empty cells.
    private var calendarWeeks: [[Date?]] {
        let dates = viewModel.calendarDates
        guard let firstDate = dates.first else { return [] }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: firstDate) // 1 = Sun
        let leadingEmpties = weekday - 1

        var allSlots: [Date?] = Array(repeating: nil, count: leadingEmpties) + dates.map { $0 }

        // Pad to complete the last week
        let remainder = allSlots.count % 7
        if remainder > 0 {
            allSlots.append(contentsOf: Array(repeating: nil as Date?, count: 7 - remainder))
        }

        return stride(from: 0, to: allSlots.count, by: 7).map {
            Array(allSlots[$0..<min($0 + 7, allSlots.count)])
        }
    }
}

// MARK: - Plan Builder Wrapper

/// Wrapper that owns the PlanBuilderViewModel as a @StateObject so it
/// isn't recreated on every SwiftUI body evaluation.
private struct PlanBuilderWrapper: View {
    let environment: AppEnvironment
    let onPlanGenerated: (MonthPlan, [PlannedSession]) -> Void
    @State private var builderVM: PlanBuilderViewModel?

    var body: some View {
        Group {
            if let vm = builderVM {
                PlanBuilderChatView(viewModel: vm, onPlanGenerated: onPlanGenerated)
            } else {
                ProgressView()
                    .tint(AppTheme.accent)
            }
        }
        .onAppear {
            if builderVM == nil {
                builderVM = environment.makePlanBuilderViewModel()
            }
        }
    }
}

// MARK: - PlannedSession + Hashable (for sheet)

extension PlannedSession: Hashable {
    static func == (lhs: PlannedSession, rhs: PlannedSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
