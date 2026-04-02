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
        }
    }
}
