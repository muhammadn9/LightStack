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

    private let logger = Logger(subsystem: "com.lightstack", category: "WorkoutSessionSheet")

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    switch todayViewModel.phase {
                    case .setup, .generating:
                        loadingView
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
                    activeWorkoutViewModel = vm
                    if case .repeatExisting = mode {
                        todayViewModel.exercises.forEach { vm.prefillTargets(for: $0) }
                    }
                } else if newPhase == .setup {
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

    // MARK: - Loading View

    /// `.generate` mode shows a branded sparkles animation;
    /// `.repeatExisting` mode shows a plain spinner (the plan is already loaded).
    @ViewBuilder
    private var loadingView: some View {
        switch mode {
        case .generate:
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
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
