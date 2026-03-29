import SwiftUI

/// Main tab bar with 4 tabs: Today, Month Plan, History, Profile.
struct MainTabView: View {
    @EnvironmentObject var environment: AppEnvironment

    var body: some View {
        TabView {
            TodayView(viewModel: environment.makeTodayViewModel())
                .tabItem {
                    Label("Today", systemImage: "figure.strengthtraining.traditional")
                }

            MonthPlanView(viewModel: environment.makeMonthPlanViewModel())
                .tabItem {
                    Label("Month Plan", systemImage: "calendar")
                }

            HistoryListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(AppTheme.accent)
    }
}
