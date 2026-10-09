import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var environment: AppEnvironment
    @AppStorage("appColorScheme") private var colorScheme = "system"
    @AppStorage("restTimerNotificationsEnabled") private var restTimerNotif = true
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("weightUnit") private var weightUnit = "lbs"

    // Pushed from Profile's NavigationStack (gear button), so it uses the
    // system navigation bar for its title and back button.
    var body: some View {
        VStack(spacing: 0) {
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

                #if DEBUG
                AIUsageDebugSection()
                #endif

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
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("settings.screen")
    }
}

#if DEBUG
/// Today's AI calls and tokens per task (from Gemini usageMetadata). Debug builds only.
private struct AIUsageDebugSection: View {
    @State private var rows: [(task: AITask, entry: AIUsageTracker.Entry)] = []

    var body: some View {
        Section("AI usage (debug)") {
            if rows.isEmpty {
                Text("No AI calls today").foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
            }
            ForEach(rows, id: \.task) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row.task.label): \(row.entry.calls) calls")
                    Text("prompt \(row.entry.prompt) · out \(row.entry.candidates) · think \(row.entry.thoughts) · total \(row.entry.total)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }
            Button("Refresh") { rows = AIUsageTracker.shared.snapshot() }
                .listRowBackground(AppTheme.surface)
            Button("Reset", role: .destructive) {
                AIUsageTracker.shared.reset()
                rows = AIUsageTracker.shared.snapshot()
            }
            .listRowBackground(AppTheme.surface)
        }
        .onAppear { rows = AIUsageTracker.shared.snapshot() }
    }
}
#endif
