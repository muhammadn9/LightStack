import SwiftUI

/// Entry point for the Today tab.
/// Switches on phase to show setup -> generating -> active -> post-workout.
struct TodayView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: TodayViewModel
    @State private var chatViewModel: CoachChatViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    switch viewModel.phase {
                    case .setup:
                        WorkoutSetupView(
                            viewModel: environment.makeWorkoutSetupViewModel(),
                            todayViewModel: viewModel
                        )

                    case .generating:
                        generatingView

                    case .active:
                        ActiveWorkoutView(
                            viewModel: environment.makeActiveWorkoutViewModel(),
                            todayViewModel: viewModel,
                            chatViewModel: chatViewModel ?? environment.makeCoachChatViewModel()
                        )

                    case .postWorkout:
                        PostWorkoutView(todayViewModel: viewModel)
                    }
                }
            }
            .onAppear {
                if chatViewModel == nil {
                    chatViewModel = environment.makeCoachChatViewModel()
                }
            }
            .onChange(of: viewModel.phase) { _, newPhase in
                if newPhase == .setup {
                    chatViewModel?.clearChat()
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
