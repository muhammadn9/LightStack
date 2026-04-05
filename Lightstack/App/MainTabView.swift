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
            let tabBarBgColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(netHex: 0x1C1510)
                    : UIColor(netHex: 0xFBF8F1)
            }
            let tabSelectedColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(netHex: 0xC8860A)
                    : UIColor(netHex: 0x1B3A6B)
            }
            let tabUnselectedColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(netHex: 0x6A5840)
                    : UIColor(netHex: 0x6A5840)
            }
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = tabBarBgColor
            appearance.stackedLayoutAppearance.selected.iconColor = tabSelectedColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: tabSelectedColor,
                .font: AppTheme.uiCaveat(11)
            ]
            appearance.stackedLayoutAppearance.normal.iconColor = tabUnselectedColor
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: tabUnselectedColor,
                .font: AppTheme.uiCaveat(10)
            ]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance

            // Notebook-styled navigation bar
            let navBarBgColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(netHex: 0x1C1510)
                    : UIColor(netHex: 0xFBF8F1)
            }
            let navTitleColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(netHex: 0xEDE0C4)
                    : UIColor(netHex: 0x1B2A40)
            }
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithOpaqueBackground()
            navAppearance.backgroundColor = navBarBgColor
            navAppearance.titleTextAttributes = [
                .foregroundColor: navTitleColor,
                .font: AppTheme.uiPlayfairBoldItalic(17)
            ]
            navAppearance.largeTitleTextAttributes = [
                .foregroundColor: navTitleColor,
                .font: AppTheme.uiPlayfairBoldItalic(34)
            ]
            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
            UINavigationBar.appearance().compactAppearance = navAppearance
        }
    }
}
