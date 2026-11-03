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
                        .accessibilityIdentifier("nutrition.tab.kitchen")
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

// MARK: - Dashboard (placeholder this phase)

struct NutritionDashboardView: View {
    @ObservedObject var viewModel: NutritionViewModel

    var body: some View {
        VStack(spacing: 0) {
            NutritionScreenHeader(title: "Dashboard", id: "dashboard.title")
            ScrollView {
                VStack(spacing: 14) {
                    progressCard
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(AppTheme.textSecondary)
                        Text("More coming soon").font(.headline).foregroundStyle(AppTheme.textPrimary)
                        Text("Trends, averages and streaks will land here.")
                            .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dashboard.soon")
                }
                .padding(16)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .onAppear { viewModel.reload() }
    }

    private var progressCard: some View {
        let totals = viewModel.summary?.totals ?? NutrientValues()
        let target = viewModel.summary?.target
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(JournalFormat.title(for: viewModel.date))'s macros").font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            bar("Calories", totals.kcal, target?.kcal, "kcal", AppTheme.macroKcal, "dashboard.calories")
            bar("Protein", totals.protein, target?.protein, "g", AppTheme.macroProtein, "dashboard.protein")
            bar("Carbs", totals.carbs, target?.carbs, "g", AppTheme.macroCarbs, "dashboard.carbs")
            bar("Fat", totals.fat, target?.fat, "g", AppTheme.macroFat, "dashboard.fat")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private func bar(_ title: String, _ value: Double, _ goal: Double?, _ unit: String, _ color: Color, _ id: String) -> some View {
        let progress = (goal ?? 0) > 0 ? min(1, value / (goal ?? 1)) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(goal.map { "\(NutritionFormat.whole(value)) / \(NutritionFormat.whole($0)) \(unit)" }
                     ?? "\(NutritionFormat.whole(value)) \(unit)")
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.macroTint(color))
                    Capsule().fill(color).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
