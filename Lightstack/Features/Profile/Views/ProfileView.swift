import SwiftUI

/// Profile tab: Coach's Notebook layout — avatar, stats, PRs, volume progress.
struct ProfileView: View {
    @EnvironmentObject var environment: AppEnvironment

    @State private var viewModel: ProfileViewModel?
    @AppStorage("selectedTab") private var selectedTab: Int = 0
    @State private var showEditSheet = false
    @State private var showAllPRs = false
    @State private var showSettings = false
    @State private var streak: Int = 0
    @State private var totalSessions: Int = 0
    @State private var totalVolume: Double = 0
    @State private var averageSessionDuration: Int = 0
    @State private var thisMonthSessions: Int = 0
    @State private var topLifts: [(exerciseName: String, e1rm: Double)] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileCard
                }
                .padding(16)
            }
            .themedBackground()
            .toolbar(.hidden, for: .navigationBar)
            .statusBarBackdrop()
            .onAppear { loadProfileData() }
            // Reload whenever this becomes the visible tab.
            .onChange(of: selectedTab) { _, tab in
                if tab == 3 { loadProfileData() }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showEditSheet) {
                if let vm = viewModel, let userId = environment.authService.currentUser()?.userId {
                    EditProfileView(viewModel: vm, userId: userId, userEmail: environment.supabaseClient.auth.currentUser?.email ?? "")
                        .keyboardDoneButton()
                        .onDisappear { vm.cancelEditing() }
                }
            }
        }
    }

    // MARK: - Profile Card (all-in-one notebook page)

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header: avatar + name + streak
            HStack(spacing: 12) {
                // Circle avatar
                ZStack {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 48, height: 48)
                    Circle()
                        .stroke(AppTheme.warning, lineWidth: 2)
                        .frame(width: 48, height: 48)
                    Text(initials)
                        .font(AppTheme.playfair(20, weight: .bold))
                        .foregroundStyle(AppTheme.onAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(AppTheme.playfair(16, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(experienceLabel)
                        .font(AppTheme.caveat(12))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                // Streak badge
                VStack(alignment: .center, spacing: 1) {
                    Text("\(streak)")
                        .font(AppTheme.playfair(22, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("day streak")
                        .font(AppTheme.caveat(9))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                // Edit button
                Button(action: {
                    viewModel?.startEditing()
                    showEditSheet = true
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityIdentifier("profile.edit")

                // Settings button
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("profile.settings")
            }
            .padding(.bottom, 12)

            InkDivider()
                .padding(.bottom, 10)

            // Training Stats section
            Text("Training Stats")
                .notebookSectionHeader()
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                statRow(id: "totalWorkouts", label: "Total Workouts", value: "\(totalSessions)")
                InkDivider()
                statRow(id: "thisMonth", label: "This Month", value: "\(thisMonthSessions)")
                InkDivider()
                statRow(id: "volume", label: "Volume (Total)", value: formatVolume(totalVolume))
                InkDivider()
                statRow(id: "avgDuration", label: "Avg Duration", value: "\(averageSessionDuration) min")
            }
            .padding(.bottom, 12)

            // Personal Records
            if let vm = viewModel, !vm.personalRecords.isEmpty {
                InkDivider()
                    .padding(.vertical, 10)

                HStack {
                    Text("Top Lifts")
                        .notebookSectionHeader()
                    Spacer()
                    Button("See all") { showAllPRs = true }
                        .font(AppTheme.caveat(13))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("profile.seeAllPRs")
                }
                .padding(.bottom, 8)
                .sheet(isPresented: $showAllPRs) {
                    NavigationStack {
                        PersonalRecordsListView(records: vm.personalRecords)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showAllPRs = false }
                                        .accessibilityIdentifier("prList.done")
                                }
                            }
                    }
                }

                VStack(spacing: 6) {
                    ForEach(PersonalRecordsListView.sorted(PersonalRecordsListView.bestPerExercise(vm.personalRecords), by: .heaviest).prefix(5)) { pr in
                        HStack(spacing: 8) {
                            PRStamp()
                                .frame(width: 24, height: 24)
                            Text(pr.exerciseName)
                                .font(AppTheme.caveat(13))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Text(String(format: "%.0f lbs × %d", pr.weightLbs, pr.reps))
                                .font(AppTheme.plexMono(11, weight: .medium))
                                .foregroundStyle(AppTheme.prStamp)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
    }

    // MARK: - Stat Row

    private func statRow(id: String, label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.caveat(13))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(AppTheme.plexMono(13, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("profile.stat.\(id)")
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func loadProfileData() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        let vm = environment.makeProfileViewModel()
        vm.loadStats(userId: userId)
        vm.loadProfile(userId: userId)
        streak = vm.streak
        totalSessions = vm.totalSessions
        totalVolume = vm.totalVolume
        averageSessionDuration = vm.averageSessionDuration
        topLifts = vm.topLifts

        thisMonthSessions = vm.thisMonthSessions
        viewModel = vm
    }

    private var displayName: String {
        if let name = viewModel?.profile?.displayName, !name.isEmpty { return name }
        if let email = environment.supabaseClient.auth.currentUser?.email {
            return email.components(separatedBy: "@").first?.capitalized ?? email
        }
        return "Athlete"
    }

    private var initials: String {
        let name = displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    private var experienceLabel: String {
        if let profile = viewModel?.profile {
            let months = profile.trainingAgeMonths ?? 0
            let years = months / 12
            if months < 6 { return "Beginner" }
            if months < 18 { return "Beginner · \(months)m" }
            if years < 3 { return "Intermediate · \(years) yr\(years == 1 ? "" : "s")" }
            return "Advanced · \(years) yrs"
        }
        return "Member since \(memberSince)"
    }

    private var memberSince: String {
        if let user = environment.authService.currentUser() {
            return DateFormatter.monthYear.string(from: user.createdAt)
        }
        return "Unknown"
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM lbs", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.0fK lbs", volume / 1_000)
        }
        return String(format: "%.0f lbs", volume)
    }
}
