import SwiftUI

/// Calendar grid view showing a full month of planned sessions.
struct MonthPlanView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: MonthPlanViewModel
    @Binding var selectedTab: Int
    @State private var selectedSession: PlannedSession?
    @State private var showPlanBuilder = false
    @State private var pendingWorkoutContext: InlineWorkoutContext?
    @State private var inlineWorkoutContext: InlineWorkoutContext?

    var body: some View {
        NavigationStack {
            calendarContent
                .navigationBarHidden(true)
                .toolbar {
                    if viewModel.canCreateNewPlan {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showPlanBuilder = true
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showPlanBuilder) {
                    PlanBuilderWrapper(
                        environment: environment,
                        onPlanGenerated: { plan, sessions in
                            viewModel.reload(plan: plan, sessions: sessions)
                            showPlanBuilder = false
                        }
                    )
                }
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
            VStack(spacing: 16) {
                if viewModel.activePlan == nil {
                    emptyPlansState
                } else {
                    // Month header
                    if let plan = viewModel.activePlan {
                        monthHeader(plan)
                    }

                    // Plan switcher chips
                    if viewModel.allPlans.count > 1 {
                        planSwitcherChips
                    }

                    // Calendar card
                    VStack(spacing: 10) {
                        // Progress bar
                        progressSection

                        InkDivider()

                        // Calendar grid (Mon-Sun)
                        calendarGrid

                        InkDivider()

                        // This Week's Plan
                        thisWeekSection
                    }
                    .cardStyle()

                    // Start Today's Workout button
                    if let session = viewModel.todaySession, !session.isRestDay {
                        Button(action: { selectedTab = 0 }) {
                            HStack(spacing: 8) {
                                Text("✦")
                                Text("Start Today's Workout")
                            }
                        }
                        .buttonStyle(WaxSealButtonStyle(isSecondary: false))
                    }
                }
            }
            .padding(16)
        }
        .themedBackground()
        .sheet(item: $selectedSession, onDismiss: {
            if let pending = pendingWorkoutContext {
                inlineWorkoutContext = pending
                pendingWorkoutContext = nil
            }
        }) { session in
            NavigationStack {
                PlannedSessionView(
                    session: session,
                    onStartWorkout: {
                        let vm = environment.makeInlineTodayViewModel()
                        if let userId = environment.authService.currentUser()?.userId {
                            vm.setUserIdSkipRestore(userId)
                        }
                        pendingWorkoutContext = InlineWorkoutContext(
                            viewModel: vm,
                            workoutType: session.workoutType
                        )
                        selectedSession = nil
                    },
                    onConfigureWithAI: {
                        selectedSession = nil
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { selectedSession = nil }
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
        .fullScreenCover(item: $inlineWorkoutContext) { context in
            WorkoutSessionSheet(
                todayViewModel: context.viewModel,
                workoutType: context.workoutType,
                mode: .generate,
                onDismiss: { inlineWorkoutContext = nil }
            )
            .environmentObject(environment)
        }
    }

    // MARK: - Month Header

    private func monthHeader(_ plan: MonthPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                // Month + year
                let monthStr: String = DateFormatter.monthName.string(from: plan.startDate)
                let yearStr: String = DateFormatter.year.string(from: plan.startDate)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(monthStr)
                        .font(AppTheme.playfair(20, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(yearStr)
                        .font(AppTheme.playfairItalic(20, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }

                Spacer()

                if viewModel.canCreateNewPlan {
                    Button(action: { showPlanBuilder = true }) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }

            if let overview = plan.aiOverview {
                Text(overview)
                    .font(AppTheme.caveat(13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyPlansState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent)
            Text("No Active Plans")
                .font(AppTheme.playfair(18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Tap + to create your first month plan")
                .font(AppTheme.caveat(14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: { showPlanBuilder = true }) {
                HStack { Text("✦"); Text("Create Plan") }
            }
            .buttonStyle(WaxSealButtonStyle(isSecondary: false))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .cardStyle()
    }

    // MARK: - Plan Switcher Chips

    private var planSwitcherChips: some View {
        PlanSwitcherChipsView(
            plans: viewModel.allPlans,
            activePlanId: viewModel.activePlan?.id,
            onSelect: { viewModel.selectPlan($0) }
        )
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        HStack {
            Text("Progress")
                .font(AppTheme.playfairItalic(13))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text("\(viewModel.completedCount)/\(viewModel.totalTrainingDays) sessions")
                .font(AppTheme.plexMono(11))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - Calendar Grid (Mon-Sun)

    private var calendarGrid: some View {
        MonthCalendarGridView(
            weeks: calendarWeeks,
            sessionForDate: { viewModel.session(for: $0) },
            onTapDate: { date in
                if let session = viewModel.session(for: date) {
                    selectedSession = session
                }
            }
        )
    }

    // MARK: - This Week's Plan

    private var thisWeekSection: some View {
        ThisWeekSectionView(sessions: currentWeekSessions)
    }

    // MARK: - Computed

    /// Organize dates into Mon-Sun weeks, with nil for empty cells.
    private var calendarWeeks: [[Date?]] {
        let dates = viewModel.calendarDates
        guard let firstDate = dates.first else { return [] }

        let calendar = Calendar.current
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat — we want Mon=0
        let weekday = calendar.component(.weekday, from: firstDate) // 1-7
        let leadingEmpties = (weekday + 5) % 7 // Mon-based offset

        var allSlots: [Date?] = Array(repeating: nil, count: leadingEmpties) + dates.map { $0 }

        let remainder = allSlots.count % 7
        if remainder > 0 {
            allSlots.append(contentsOf: Array(repeating: nil as Date?, count: 7 - remainder))
        }

        return stride(from: 0, to: allSlots.count, by: 7).map {
            Array(allSlots[$0..<min($0 + 7, allSlots.count)])
        }
    }

    private var currentWeekSessions: [PlannedSession] {
        let calendar = Calendar.current
        let today = Date()
        // Start of this week (Monday)
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        components.weekday = 2 // Monday
        guard let weekStart = calendar.date(from: components),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return [] }
        return viewModel.sessions
            .filter { $0.plannedDate >= weekStart && $0.plannedDate < weekEnd }
            .sorted { $0.plannedDate < $1.plannedDate }
    }
}

// MARK: - Plan Builder Wrapper

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

// MARK: - Inline Workout Context

private struct InlineWorkoutContext: Identifiable {
    let id = UUID()
    let viewModel: TodayViewModel
    let workoutType: String
}

// MARK: - PlannedSession + Hashable

extension PlannedSession: Hashable {
    static func == (lhs: PlannedSession, rhs: PlannedSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
