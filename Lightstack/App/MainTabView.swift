import SwiftUI

/// Main tab bar with 4 tabs: Today, Month Plan, History, Profile.
struct MainTabView: View {
    // TODO: Phase 0 — Implement tab bar shell (Task #7)

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "figure.strengthtraining.traditional")
                }

            MonthPlanView()
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
    }
}
