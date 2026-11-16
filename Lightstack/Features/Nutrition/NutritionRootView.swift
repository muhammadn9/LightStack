import SwiftUI

/// The nutrition side: its own native tab bar (Journal, Dashboard, Goals, Kitchen).
struct NutritionRootView: View {
    @EnvironmentObject var environment: AppEnvironment
    @EnvironmentObject var side: AppSideController
    @AppStorage("nutritionSelectedTab") private var selectedTab = 0
    @AppStorage("nutritionSetupSkipped") private var setupSkipped = false
    @State private var viewModel: NutritionViewModel?
    @State private var setupRequest: SetupRequest?

    private struct SetupRequest: Identifiable { let id = UUID() }

    var body: some View {
        Group {
            if let viewModel {
                TabView(selection: $selectedTab) {
                    JournalView(viewModel: viewModel, onStartSetup: startSetup)
                        .tabItem { Label("Journal", systemImage: "fork.knife") }
                        .tag(0)
                        .accessibilityIdentifier("nutrition.tab.journal")
                    NutritionDashboardView(viewModel: viewModel)
                        .tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }
                        .tag(1)
                        .accessibilityIdentifier("nutrition.tab.dashboard")
                    GoalsView(viewModel: viewModel, onStartSetup: startSetup)
                        .tabItem { Label("Goals", systemImage: "target") }
                        .tag(2)
                        .accessibilityIdentifier("nutrition.tab.goals")
                    KitchenView(viewModel: viewModel)
                        .tabItem { Label("Kitchen", systemImage: "refrigerator") }
                        .tag(3)
                }
                .tint(AppTheme.accent)
                .sensoryFeedback(.selection, trigger: selectedTab)
            } else {
                AppTheme.background.ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { SessionExpiredBanner() }
        .themedBackground()
        .onAppear {
            if viewModel == nil { viewModel = environment.makeNutritionViewModel() }
            autoShowSetupIfNeeded()
        }
        .onChange(of: side.side) { _, newSide in
            if newSide == .nutrition {
                viewModel?.reload()
                autoShowSetupIfNeeded()
            }
        }
        .fullScreenCover(item: $setupRequest) { _ in
            if let viewModel {
                NutritionSetupWizardView(viewModel: viewModel) { finished in
                    if !finished { setupSkipped = true }
                    setupRequest = nil
                    viewModel.reload()
                }
            }
        }
    }

    private func startSetup() { setupRequest = SetupRequest() }

    /// First visit with no targets at all: offer the wizard once. Existing users with targets are never nagged.
    private func autoShowSetupIfNeeded() {
        guard let viewModel, setupRequest == nil, !setupSkipped, side.side == .nutrition else { return }
        #if DEBUG
        if UITestMode.isActive, !UITestMode.wantsNutritionWizard { return }
        #endif
        viewModel.reload()
        guard !viewModel.isSetupComplete, viewModel.plans.isEmpty, viewModel.currentTarget() == nil else { return }
        setupRequest = SetupRequest()
    }
}

/// Large screen title with the side-switch button, shared by Dashboard, Goals and Kitchen.
struct NutritionScreenHeader: View {
    let title: String
    let id: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier(id)
            Spacer()
            SideSwitchButton()
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }
}
