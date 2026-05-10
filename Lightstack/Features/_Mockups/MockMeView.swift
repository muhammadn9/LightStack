import SwiftUI

struct MockMeView: View {

    @State private var remindersOn: Bool = true
    @State private var restAlertsOn: Bool = true

    var body: some View {
        NavigationStack {
            List {
                profileHeaderSection
                statsSection
                workoutSection
                coachSection
                appearanceSection
                notificationsSection
                accountSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Me")
        }
    }

    // MARK: - Sections

    private var profileHeaderSection: some View {
        Section {
            Button(action: {}) {
                HStack(spacing: ModernTheme.spacingM) {
                    ZStack {
                        Circle()
                            .fill(ModernTheme.accent.opacity(0.2))
                            .frame(width: 64, height: 64)
                        Text(initials(from: MockData.userName))
                            .font(.title2)
                            .bold()
                            .foregroundStyle(ModernTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MockData.userName)
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.primary)
                        Text(MockData.userEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .modernCard()
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var statsSection: some View {
        Section("Your stats") {
            HStack(spacing: ModernTheme.spacingS) {
                ModernStatTile(
                    value: "\(MockData.userStreak)",
                    label: "Streak",
                    systemImage: "flame.fill"
                )
                ModernStatTile(
                    value: "\(MockData.userTotalSessions)",
                    label: "Sessions",
                    systemImage: "checkmark.seal.fill"
                )
                ModernStatTile(
                    value: "\(MockData.userAvgSessionMin)m",
                    label: "Avg session",
                    systemImage: "clock.fill"
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: ModernTheme.spacingM, bottom: 0, trailing: ModernTheme.spacingM))
        }
    }

    private var workoutSection: some View {
        Section("Workout") {
            NavigationLink { EmptyView() } label: {
                Label("Split & schedule", systemImage: "calendar")
                    .foregroundStyle(.primary)
            }
            .tint(ModernTheme.accent)

            NavigationLink { EmptyView() } label: {
                Label("Equipment", systemImage: "wrench.and.screwdriver")
                    .foregroundStyle(.primary)
            }
            .tint(ModernTheme.accent)

            NavigationLink { EmptyView() } label: {
                Label("Goals", systemImage: "target")
                    .foregroundStyle(.primary)
            }
            .tint(ModernTheme.accent)

            HStack {
                Image(systemName: "timer")
                    .foregroundStyle(ModernTheme.accent)
                Text("Default rest timer")
                Spacer()
                Text("90s")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var coachSection: some View {
        Section("Coach") {
            HStack {
                Image(systemName: "person.wave.2")
                    .foregroundStyle(ModernTheme.accent)
                Text("Tone")
                Spacer()
                Text("Friendly")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            NavigationLink { EmptyView() } label: {
                Label("Suggestion notes", systemImage: "note.text")
                    .foregroundStyle(.primary)
            }
            .tint(ModernTheme.accent)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack {
                Image(systemName: "paintbrush")
                    .foregroundStyle(ModernTheme.accent)
                Text("Theme")
                Spacer()
                Text("System")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            NavigationLink { EmptyView() } label: {
                Label("App icon", systemImage: "app.badge")
                    .foregroundStyle(.primary)
            }
            .tint(ModernTheme.accent)
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Workout reminders", isOn: $remindersOn)
                .tint(ModernTheme.accent)
            Toggle("Rest timer alerts", isOn: $restAlertsOn)
                .tint(ModernTheme.accent)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            HStack {
                Image(systemName: "envelope")
                    .foregroundStyle(ModernTheme.accent)
                Text("Email")
                Spacer()
                Text(MockData.userEmail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            NavigationLink { EmptyView() } label: {
                Label("Privacy & data", systemImage: "lock.shield")
                    .foregroundStyle(.primary)
            }
            .tint(ModernTheme.accent)

            Button(action: {}) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                    Text("Sign out")
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("3.0.0 (1)")
                    .foregroundStyle(.secondary)
            }

            NavigationLink { EmptyView() } label: {
                Label("Help & feedback", systemImage: "questionmark.circle")
                    .foregroundStyle(.primary)
            }
            .tint(ModernTheme.accent)
        }
    }

    // MARK: - Helpers

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map { String($0) } }
        return letters.joined()
    }
}

#Preview("Light") {
    MockMeView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MockMeView()
        .preferredColorScheme(.dark)
}
