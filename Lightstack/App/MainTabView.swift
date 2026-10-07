import SwiftUI

/// Main app container: native bottom tab bar (Today · History · Progress · Profile).
struct MainTabView: View {
    @EnvironmentObject var environment: AppEnvironment
    /// 0 Today, 1 History, 2 Progress, 3 Profile (4 Month, only when its flag is on).
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    @AppStorage("selectedTabLayoutV2") private var tabLayoutMigrated = false
    @State private var todayViewModel: TodayViewModel?
    @State private var monthPlanViewModel: MonthPlanViewModel?

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if let todayVM = todayViewModel {
                    TodayTabContent(viewModel: todayVM)
                } else {
                    AppTheme.background.ignoresSafeArea()
                }
            }
            .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
            .tag(0)

            HistoryListView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)

            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(3)

            if FeatureFlags.monthTabEnabled {
                Group {
                    if let monthVM = monthPlanViewModel {
                        MonthPlanView(viewModel: monthVM, selectedTab: $selectedTab)
                    } else {
                        AppTheme.background
                    }
                }
                .tabItem { Label("Month", systemImage: "calendar") }
                .tag(4)
            }
        }
        .tint(AppTheme.accent)
        .themedBackground()
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onAppear {
            setupAppearance()
            migrateStoredTab()
            if todayViewModel == nil {
                todayViewModel = environment.makeTodayViewModel()
            }
            if monthPlanViewModel == nil && FeatureFlags.monthTabEnabled {
                monthPlanViewModel = environment.makeMonthPlanViewModel()
            }
        }
    }

    /// Old layout: 0 Today, 1 Month, 2 History, 3 Profile, 4 Settings.
    private func migrateStoredTab() {
        guard !tabLayoutMigrated else { return }
        tabLayoutMigrated = true
        switch selectedTab {
        case 1: selectedTab = 0
        case 2: selectedTab = 1
        case 3, 4: selectedTab = 3
        default: break
        }
    }

    // MARK: - UIKit Appearance

    private func setupAppearance() {
        let barColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(netHex: 0x111314) : .white }
        let unselected = UIColor { $0.userInterfaceStyle == .dark ? UIColor(netHex: 0x8D9296) : UIColor(netHex: 0x555555) }
        let selected = UIColor { $0.userInterfaceStyle == .dark ? UIColor(netHex: 0x3DDC4A) : UIColor(netHex: 0x1A7F2E) }

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = barColor
        tabAppearance.shadowColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.1) }
        for item in [tabAppearance.stackedLayoutAppearance, tabAppearance.inlineLayoutAppearance, tabAppearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = unselected
            item.normal.titleTextAttributes = [.foregroundColor: unselected]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar styling — use system defaults
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }
}

// MARK: - Today Tab Content

/// Wraps TodayViewModel lifecycle within the tab architecture.
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
                    vm.setTargetsProvider = { [weak today = viewModel] id in today?.setTargets[id] }
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
                    .font(.system(.title, design: .default, weight: .light))
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
