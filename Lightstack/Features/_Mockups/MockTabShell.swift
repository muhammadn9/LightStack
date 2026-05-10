import SwiftUI

struct MockTabShell: View {
    var body: some View {
        TabView {
            MockTodayView()
                .tabItem {
                    Image(systemName: "figure.run")
                    Text("Today")
                }

            MockPlanView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Plan")
                }

            MockLogView()
                .tabItem {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Log")
                }

            MockMeView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("Me")
                }
        }
        .tint(ModernTheme.accent)
    }
}

#Preview("Light") {
    MockTabShell()
}

#Preview("Dark") {
    MockTabShell()
        .preferredColorScheme(.dark)
}
