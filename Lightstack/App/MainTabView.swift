import SwiftUI

/// Main app container: notebook-style tab row at top + content area below.
/// Replaces the native iOS tab bar with an inline horizontal tab strip.
struct MainTabView: View {
    @EnvironmentObject var environment: AppEnvironment
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    @State private var todayViewModel: TodayViewModel?
    @State private var monthPlanViewModel: MonthPlanViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // Notebook tab row
            NotebookTabRow(selectedTab: $selectedTab)

            // Content — TabView with page style for smooth swiping
            TabView(selection: $selectedTab) {
                Group {
                    if let todayVM = todayViewModel {
                        TodayTabContent(viewModel: todayVM)
                    } else {
                        AppTheme.background
                    }
                }
                .tag(0)

                Group {
                    if let monthVM = monthPlanViewModel {
                        MonthPlanView(viewModel: monthVM, selectedTab: $selectedTab)
                    } else {
                        AppTheme.background
                    }
                }
                .tag(1)

                HistoryListView()
                    .tag(2)

                ProfileView()
                    .tag(3)

                SettingsView()
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .themedBackground()
        .onAppear {
            setupAppearance()
            if todayViewModel == nil {
                todayViewModel = environment.makeTodayViewModel()
            }
            if monthPlanViewModel == nil {
                monthPlanViewModel = environment.makeMonthPlanViewModel()
            }
        }
    }

    // MARK: - UIKit Appearance

    private func setupAppearance() {
        // Hide native tab bar entirely (custom tab row replaces it)
        UITabBar.appearance().isHidden = true

        // Navigation bar styling — use system defaults
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }
}

// MARK: - Notebook Tab Row

struct NotebookTabRow: View {
    @Binding var selectedTab: Int
    private let tabs = ["Today", "Month", "History", "Profile", "Settings"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = i } }) {
                        VStack(spacing: 0) {
                            Text(tabs[i])
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(i == selectedTab ? AppTheme.accent : AppTheme.textSecondary)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)

                            // Active indicator
                            Capsule()
                                .fill(i == selectedTab ? AppTheme.accent : Color.clear)
                                .frame(height: 3)
                                .padding(.horizontal, 18)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            InkDivider()
        }
        .background(.bar)
    }
}

// MARK: - Today Tab Content

/// Wraps TodayViewModel lifecycle within the custom tab architecture.
private struct TodayTabContent: View {
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
                            WorkoutSetupView(viewModel: setupVM, todayViewModel: viewModel)
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
            .themedBackground()
            .navigationBarHidden(true)
            .onAppear {
                if chatViewModel == nil {
                    chatViewModel = environment.makeCoachChatViewModel()
                }
                if setupViewModel == nil {
                    setupViewModel = environment.makeWorkoutSetupViewModel()
                }
                if let userId = environment.authService.currentUser()?.userId {
                    viewModel.setUserId(userId)
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

    private var generatingView: some View {
        VStack(spacing: 24) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.accent.opacity(0.18 - Double(i) * 0.05), lineWidth: 1.5)
                        .frame(width: CGFloat(56 + i * 24), height: CGFloat(56 + i * 24))
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
