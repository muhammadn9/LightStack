import SwiftUI

/// Entry point for the Today tab.
/// Switches on phase to show setup -> generating -> active -> post-workout.
struct TodayView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: TodayViewModel
    @State private var chatViewModel: CoachChatViewModel?
    @State private var setupViewModel: WorkoutSetupViewModel?
    @State private var activeWorkoutViewModel: ActiveWorkoutViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    switch viewModel.phase {
                    case .setup:
                        if let setupVM = setupViewModel {
                            WorkoutSetupView(
                                viewModel: setupVM,
                                todayViewModel: viewModel
                            )
                        }

                    case .generating:
                        generatingView

                    case .confirmation:
                        ConfirmWorkoutView(
                            todayViewModel: viewModel,
                            chatViewModel: chatViewModel,
                            workoutType: viewModel.sessionService.currentWorkoutType ?? ""
                        )

                    case .active:
                        if let activeVM = activeWorkoutViewModel {
                            ActiveWorkoutView(
                                viewModel: activeVM,
                                todayViewModel: viewModel,
                                chatViewModel: chatViewModel ?? environment.makeCoachChatViewModel()
                            )
                        }

                    case .postWorkout:
                        PostWorkoutView(todayViewModel: viewModel)
                    }
                }
            }
            .onAppear {
                if chatViewModel == nil {
                    chatViewModel = environment.makeCoachChatViewModel()
                }
                if setupViewModel == nil {
                    setupViewModel = environment.makeWorkoutSetupViewModel()
                }
            }
            .onChange(of: viewModel.phase) { _, newPhase in
                if newPhase == .setup {
                    chatViewModel?.clearChat()
                    activeWorkoutViewModel = nil
                } else if newPhase == .active, activeWorkoutViewModel == nil {
                    let vm = environment.makeActiveWorkoutViewModel()
                    vm.onRestTimerStart = { name, seconds in
                        environment.notificationService.scheduleRestTimerAlert(exerciseName: name, totalRestSeconds: seconds)
                    }
                    vm.onRestTimerCancel = {
                        environment.notificationService.cancelPendingRestAlerts()
                    }
                    activeWorkoutViewModel = vm
                }
            }
            .navigationTitle("Today")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StreakView(count: viewModel.streak)
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Generating State

    private var generatingView: some View {
        VStack(spacing: 20) {
            ZStack {
                // Pulsing rings
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.2 - Double(i) * 0.05), lineWidth: 2)
                        .frame(width: CGFloat(60 + i * 30), height: CGFloat(60 + i * 30))
                        .scaleEffect(1.0)
                        .animation(
                            .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.3),
                            value: viewModel.phase
                        )
                }

                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
            }

            Text("Generating your workout...")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("Your AI coach is building a plan")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
