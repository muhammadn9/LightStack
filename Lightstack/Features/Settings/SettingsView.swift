import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var environment: AppEnvironment
    @AppStorage("appColorScheme") private var colorScheme = "system"
    @AppStorage("restTimerNotificationsEnabled") private var restTimerNotif = true
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("weightUnit") private var weightUnit = "lbs"

    // No NavigationStack: Settings never pushes, and a visible navigation bar
    // inside the paged tab container crashed UIKit (UINavigationBar layout
    // assertion) and drew its title white-on-white in Light mode.
    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityAddTraits(.isHeader)
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $colorScheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(AppTheme.surface)
                }

                Section("Notifications") {
                    Toggle("Rest Timer Alerts", isOn: $restTimerNotif)
                        .tint(AppTheme.accent)
                        .listRowBackground(AppTheme.surface)
                }

                Section("Workout") {
                    Picker("Default Rest Timer", selection: $defaultRestSeconds) {
                        Text("60s").tag(60)
                        Text("90s").tag(90)
                        Text("120s").tag(120)
                        Text("150s").tag(150)
                        Text("180s").tag(180)
                    }
                    .listRowBackground(AppTheme.surface)

                    Picker("Weight Unit", selection: $weightUnit) {
                        Text("lbs").tag("lbs")
                        Text("kg").tag("kg")
                    }
                    .listRowBackground(AppTheme.surface)
                }

                Section("Account") {
                    Button(action: { environment.authService.signOut() }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .font(AppTheme.playfairItalic(14, weight: .bold))
                        .foregroundStyle(AppTheme.destructive)
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }
}
