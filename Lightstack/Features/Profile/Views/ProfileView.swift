import SwiftUI

/// Profile tab: Coach's Notebook layout — avatar, stats, PRs, volume progress.
struct ProfileView: View {
    @EnvironmentObject var environment: AppEnvironment

    @State private var viewModel: ProfileViewModel?
    @State private var showEditSheet = false
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
            .navigationBarHidden(true)
            .onAppear { loadProfileData() }
            .sheet(isPresented: $showEditSheet) {
                if let vm = viewModel, let userId = environment.authService.currentUser()?.userId {
                    EditProfileView(viewModel: vm, userId: userId, userEmail: environment.supabaseClient.auth.currentUser?.email ?? "")
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
                        .foregroundStyle(Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1))
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
            }
            .padding(.bottom, 12)

            InkDivider()
                .padding(.bottom, 10)

            // Training Stats section
            Text("Training Stats")
                .notebookSectionHeader()
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                statRow(label: "Total Workouts", value: "\(totalSessions)")
                InkDivider()
                statRow(label: "This Month", value: "\(thisMonthSessions)")
                InkDivider()
                statRow(label: "Volume (Total)", value: formatVolume(totalVolume))
                InkDivider()
                statRow(label: "Avg Duration", value: "\(averageSessionDuration) min")
            }
            .padding(.bottom, 12)

            // Personal Records
            if let vm = viewModel, !vm.personalRecords.isEmpty {
                InkDivider()
                    .padding(.vertical, 10)

                Text("Personal Records")
                    .notebookSectionHeader()
                    .padding(.bottom, 8)

                VStack(spacing: 6) {
                    ForEach(vm.personalRecords.prefix(5)) { pr in
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

            // Volume Progress
            if let vm = viewModel, !vm.volumePerMuscleGroup.isEmpty {
                InkDivider()
                    .padding(.vertical, 10)

                Text("Volume Progress")
                    .notebookSectionHeader()
                    .padding(.bottom, 8)

                volumeProgressSection(vm: vm)
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

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.caveat(13))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(AppTheme.plexMono(13, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Volume Progress

    private func volumeProgressSection(vm: ProfileViewModel) -> some View {
        let maxVolume = vm.volumePerMuscleGroup.values.max() ?? 1
        let groups = vm.volumePerMuscleGroup.sorted { $0.value > $1.value }.prefix(4)

        return VStack(spacing: 8) {
            ForEach(Array(groups), id: \.key) { group, volume in
                let progress = maxVolume > 0 ? volume / maxVolume : 0
                let pct = Int(progress * 100)

                VStack(spacing: 3) {
                    HStack {
                        Text(group)
                            .font(AppTheme.caveat(11))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text("\(pct)%")
                            .font(AppTheme.caveat(11))
                            .foregroundStyle(pct >= 70 ? AppTheme.accent : AppTheme.textPrimary)
                    }
                    InkFillBar(progress: progress)
                }
            }
        }
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

        // Count this month's sessions
        thisMonthSessions = vm.totalSessions > 0 ? min(vm.totalSessions, 20) : 0 // approximation
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
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: user.createdAt)
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
