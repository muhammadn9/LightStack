import SwiftUI

/// Main tab bar with 4 tabs: Today, Month Plan, History, Profile.
struct MainTabView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var selectedTab: Int = 0
    @State private var monthPlanViewModel: MonthPlanViewModel?

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(viewModel: environment.makeTodayViewModel())
                .tabItem {
                    Label("Today", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(0)

            Group {
                if let vm = monthPlanViewModel {
                    MonthPlanView(viewModel: vm, selectedTab: $selectedTab)
                } else {
                    ProgressView()
                        .tint(AppTheme.accent)
                }
            }
            .tabItem {
                Label("Month Plan", systemImage: "calendar")
            }
            .tag(1)

            HistoryListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(3)
        }
        .tint(AppTheme.accent)
        .onAppear {
            if monthPlanViewModel == nil {
                monthPlanViewModel = environment.makeMonthPlanViewModel()
            }
            // Notebook-styled tab bar
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(netHex: 0x1C1510)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(netHex: 0xC8860A)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(netHex: 0xC8860A),
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(netHex: 0x6A5840)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(netHex: 0x6A5840),
                .font: UIFont.systemFont(ofSize: 10)
            ]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            // Notebook-styled navigation bar
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithOpaqueBackground()
            navAppearance.backgroundColor = UIColor(netHex: 0x1C1510)
            navAppearance.titleTextAttributes = [
                .foregroundColor: UIColor(netHex: 0xEDE0C4),
                .font: UIFont(name: "Georgia-Bold", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .bold)
            ]
            navAppearance.largeTitleTextAttributes = [
                .foregroundColor: UIColor(netHex: 0xEDE0C4),
                .font: UIFont(name: "Georgia-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
            ]
            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
            UINavigationBar.appearance().compactAppearance = navAppearance
        }
    }
}
