import SwiftUI
import os

/// Unified full-screen workout sheet used by both MonthPlan (generate flow)
/// and WorkoutDetail (repeat-existing flow).
///
/// `Mode` encodes the two behavioral differences between the two call sites:
/// - `.generate` triggers AI plan generation on appear and shows a branded generating view.
/// - `.repeatExisting` skips generation (the caller has already called `loadExistingWorkout`)
///   and prefills per-exercise targets when the session goes active.
struct WorkoutSessionSheet: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var todayViewModel: TodayViewModel
    let workoutType: String
    let mode: Mode
    let onDismiss: () -> Void

    /// Distinguishes the two call-site behaviours that cannot be unified without changing
    /// when generation fires or when targets are prefilled.
    enum Mode {
        /// AI-generation flow (MonthPlan). Fires `generatePlan` once on appear.
        case generate
        /// Repeat-existing flow (WorkoutDetail). Caller already called `loadExistingWorkout`;
        /// prefills targets from `todayViewModel.exercises` when the session goes active.
        case repeatExisting
    }

    @State private var activeWorkoutViewModel: ActiveWorkoutViewModel?
    @State private var chatViewModel: CoachChatViewModel?
    @State private var hasTriggeredGeneration = false
    @State private var showManualEntry = false

    private let logger = Logger(subsystem: "com.lightstack", category: "WorkoutSessionSheet")

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    switch todayViewModel.phase {
                    case .setup, .generating:
                        if showsPlanFailure {
                            planFailureView
                        } else {
                            loadingView
                        }
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
                        PostWorkoutView(todayViewModel: todayViewModel, chatViewModel: chatViewModel)
                    }
                }
            }
            .navigationTitle(workoutType)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
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
                if case .generate = mode, !hasTriggeredGeneration {
                    hasTriggeredGeneration = true
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
                    vm.setTargetsProvider = { [weak today = todayViewModel] id in today?.setTargets[id] }
                    activeWorkoutViewModel = vm
                    if case .repeatExisting = mode {
                        todayViewModel.exercises.forEach { vm.prefillTargets(for: $0) }
                    }
                } else if newPhase == .setup, !showsPlanFailure {
                    // A failed generation also lands on .setup, but with an error: stay open so the athlete
                    // sees the Retry / Build manually screen instead of the sheet vanishing.
                    onDismiss()
                }
            }
            .alert("Error", isPresented: .init(
                get: { todayViewModel.errorMessage != nil && !showsPlanFailure },
                set: { if !$0 { todayViewModel.errorMessage = nil } }
            )) {
                Button("OK") { todayViewModel.errorMessage = nil }
            } message: {
                Text(todayViewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showManualEntry) {
                if let userId = environment.authService.currentUser()?.userId {
                    ManualWorkoutEntryView(todayViewModel: todayViewModel, userId: userId)
                        .keyboardDoneButton()
                }
            }
        }
    }

    // MARK: - Plan failure

    /// True while a generation attempt has failed and the athlete is back at setup.
    private var showsPlanFailure: Bool {
        guard case .generate = mode else { return false }
        return todayViewModel.phase == .setup && todayViewModel.errorMessage != nil
    }

    /// Friendly failure state with Retry and a manual fallback (no AI needed).
    private var planFailureView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .scaledSymbol(size: 36)
                .foregroundStyle(AppTheme.accent)
            Text("Couldn't build your workout")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(todayViewModel.errorMessage ?? AIErrorPresentation.genericMessage)
                .font(AppTheme.caveat(14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("planFailure.message")
            Button {
                todayViewModel.retryPlanGeneration()
            } label: {
                Text("Retry")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .accessibilityIdentifier("planFailure.retryButton")
            Button {
                todayViewModel.errorMessage = nil
                showManualEntry = true
            } label: {
                Text("Build manually")
                    .font(AppTheme.playfairItalic(14, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
            .accessibilityIdentifier("planFailure.manualButton")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading View

    /// `.generate` mode shows a branded sparkles animation;
    /// `.repeatExisting` mode shows a plain spinner (the plan is already loaded).
    @ViewBuilder
    private var loadingView: some View {
        switch mode {
        case .generate:
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .scaledSymbol(size: 40)
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Generating \(workoutType) workout...")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Your AI coach is building a plan")
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .repeatExisting:
            ProgressView()
                .tint(AppTheme.accent)
        }
    }
}
