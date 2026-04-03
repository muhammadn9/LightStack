import SwiftUI

/// Calendar grid view showing a full month of planned sessions.
/// Days are color-coded: rest (grey), planned (default), today (highlighted),
/// completed (checkmark), missed (amber).
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
                .navigationTitle("Month Plan")
                .toolbarColorScheme(.dark, for: .navigationBar)
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
            VStack(spacing: 20) {
                if viewModel.activePlan == nil {
                    emptyPlansState
                } else {
                    if let plan = viewModel.activePlan {
                        planHeader(plan)
                    }
                    // Plan switcher chips (when more than 1 plan)
                    if viewModel.allPlans.count > 1 {
                        planSwitcherChips
                    }
                    progressBar
                    calendarGrid
                }
            }
            .padding(16)
        }
        .themedBackground()
        .sheet(item: $selectedSession, onDismiss: {
            // Present the inline workout AFTER the sheet fully dismisses to avoid
            // a black screen from concurrent sheet-dismiss + fullScreenCover-present.
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
                        // Skip session restoration so we don't replay the Today tab's workout.
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
        // fullScreenCover(item:) guarantees the context is non-nil when the view renders,
        // eliminating the empty-view → black screen race condition.
        .fullScreenCover(item: $inlineWorkoutContext) { context in
            InlineWorkoutSheet(
                todayViewModel: context.viewModel,
                workoutType: context.workoutType,
                onDismiss: { inlineWorkoutContext = nil }
            )
            .environmentObject(environment)
        }
    }

    // MARK: - Empty State

    private var emptyPlansState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent)
            Text("No Active Plans")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Tap + to create your first month plan")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .cardStyle()
    }

    // MARK: - Plan Switcher Chips

    private var planSwitcherChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.allPlans) { plan in
                    Button {
                        viewModel.selectPlan(plan)
                    } label: {
                        Text(plan.title ?? "Plan")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.activePlan?.id == plan.id ? AppTheme.accent : AppTheme.surfaceElevated)
                            .foregroundStyle(viewModel.activePlan?.id == plan.id ? Color.white : AppTheme.textPrimary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 4)
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

// MARK: - Inline Workout Sheet

private struct InlineWorkoutSheet: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var todayViewModel: TodayViewModel
    let workoutType: String
    let onDismiss: () -> Void

    @State private var activeWorkoutViewModel: ActiveWorkoutViewModel?
    @State private var chatViewModel: CoachChatViewModel?
    @State private var hasTriggeredGeneration = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    switch todayViewModel.phase {
                    case .setup, .generating:
                        generatingView
                    case .confirmation:
                        ConfirmWorkoutView(
                            todayViewModel: todayViewModel,
                            chatViewModel: chatViewModel,
                            workoutType: workoutType
                        )
                    case .active:
                        if let activeVM = activeWorkoutViewModel {
                            ActiveWorkoutView(
                                viewModel: activeVM,
                                todayViewModel: todayViewModel,
                                chatViewModel: chatViewModel ?? environment.makeCoachChatViewModel()
                            )
                        }
                    case .postWorkout:
                        PostWorkoutView(todayViewModel: todayViewModel)
                    }
                }
            }
            .navigationTitle(workoutType)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onDismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .onAppear {
                if chatViewModel == nil {
                    chatViewModel = environment.makeCoachChatViewModel()
                }
                if !hasTriggeredGeneration {
                    hasTriggeredGeneration = true
                    // Ensure userId is set without restoring an old saved session
                    if todayViewModel.userId == nil,
                       let userId = environment.authService.currentUser()?.userId {
                        todayViewModel.setUserIdSkipRestore(userId)
                    }
                    todayViewModel.generatePlan(
                        workoutType: workoutType,
                        time: 60,
                        energy: 3,
                        notes: nil
                    )
                }
            }
            .onChange(of: todayViewModel.phase) { _, newPhase in
                if newPhase == .active, activeWorkoutViewModel == nil {
                    let vm = environment.makeActiveWorkoutViewModel()
                    vm.onRestTimerStart = { name, seconds in
                        environment.notificationService.scheduleRestTimerAlert(
                            exerciseName: name, totalRestSeconds: seconds
                        )
                    }
                    vm.onRestTimerCancel = {
                        environment.notificationService.cancelPendingRestAlerts()
                    }
                    activeWorkoutViewModel = vm
                } else if newPhase == .setup {
                    // Workout was saved — auto-dismiss
                    onDismiss()
                }
            }
            .alert("Error", isPresented: .init(
                get: { todayViewModel.errorMessage != nil },
                set: { if !$0 { todayViewModel.errorMessage = nil } }
            )) {
                Button("OK") { todayViewModel.errorMessage = nil }
            } message: {
                Text(todayViewModel.errorMessage ?? "")
            }
        }
    }

    private var generatingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.pulse, options: .repeating)
            Text("Generating \(workoutType) workout...")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Your AI coach is building a plan")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Inline Workout Context

/// Identifiable wrapper for the inline workout flow so fullScreenCover(item:)
/// guarantees a non-nil context when the cover renders.
private struct InlineWorkoutContext: Identifiable {
    let id = UUID()
    let viewModel: TodayViewModel
    let workoutType: String
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
