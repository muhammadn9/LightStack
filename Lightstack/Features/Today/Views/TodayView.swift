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
                .id(viewModel.phase)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                .animation(.easeInOut(duration: 0.28), value: viewModel.phase)
            }
            .themedBackground()
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
        VStack(spacing: 24) {
            ZStack {
                // Ink-ring pulse
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.accent.opacity(0.18 - Double(i) * 0.05), lineWidth: 1.5)
                        .frame(width: CGFloat(56 + i * 24), height: CGFloat(56 + i * 24))
                        .animation(
                            .easeInOut(duration: 1.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.35),
                            value: viewModel.phase
                        )
                }
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
            }

            VStack(spacing: 6) {
                Text("Writing your plan…")
                    .font(AppTheme.playfairItalic(17, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Your coach is preparing the workout")
                    .font(AppTheme.caveat(15))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
