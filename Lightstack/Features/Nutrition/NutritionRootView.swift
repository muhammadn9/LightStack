import SwiftUI

/// The nutrition side: its own native tab bar (Journal, Dashboard, Goals, Kitchen).
struct NutritionRootView: View {
    @EnvironmentObject var environment: AppEnvironment
    @EnvironmentObject var side: AppSideController
    @AppStorage("nutritionSelectedTab") private var selectedTab = 0
    @State private var viewModel: NutritionViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TabView(selection: $selectedTab) {
                    JournalView(viewModel: viewModel)
                        .tabItem { Label("Journal", systemImage: "fork.knife") }
                        .tag(0)
                        .accessibilityIdentifier("nutrition.tab.journal")
                    NutritionDashboardView(viewModel: viewModel)
                        .tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }
                        .tag(1)
                        .accessibilityIdentifier("nutrition.tab.dashboard")
                    GoalsView(viewModel: viewModel)
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
        }
        .onChange(of: side.side) { _, newSide in
            if newSide == .nutrition { viewModel?.reload() }
        }
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

// MARK: - Goals

struct GoalsView: View {
    @ObservedObject var viewModel: NutritionViewModel
    @State private var editing = false

    var body: some View {
        let target = viewModel.currentTarget()
        return VStack(spacing: 0) {
            NutritionScreenHeader(title: "My Goals", id: "goals.title")
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Daily macros").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                                    .accessibilityIdentifier("goals.card")
                                Text("\(viewModel.slots.count) meals").font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Button { editing = true } label: {
                                Text(target == nil ? "Set" : "Edit").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent).padding(.horizontal, 14).frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("goals.edit")
                        }
                        HStack(spacing: 10) {
                            tile("Protein", target?.protein, AppTheme.macroProtein, "goals.protein")
                            tile("Carbs", target?.carbs, AppTheme.macroCarbs, "goals.carbs")
                            tile("Fat", target?.fat, AppTheme.macroFat, "goals.fat")
                            tile("Calories", target?.kcal, AppTheme.macroKcal, "goals.calories")
                        }
                        if target == nil {
                            Text("No targets yet. Set them to see progress on the Journal.")
                                .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                                .accessibilityIdentifier("goals.empty")
                        }
                    }
                    .padding(16)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                }
                .padding(16)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .sheet(isPresented: $editing) { NutritionTargetsView(viewModel: viewModel) }
        .onAppear { viewModel.reload() }
    }

    private func tile(_ title: String, _ value: Double?, _ color: Color, _ id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(value.map { NutritionFormat.whole($0) } ?? "–")
                .font(.title3.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
