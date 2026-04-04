import SwiftUI

/// Profile tab: header card, stats grid, and sign out.
struct ProfileView: View {
    @EnvironmentObject var environment: AppEnvironment

    @State private var viewModel: ProfileViewModel?
    @State private var showEditSheet = false
    @State private var streak: Int = 0
    @State private var totalSessions: Int = 0
    @State private var totalVolume: Double = 0
    @State private var averageSessionDuration: Int = 0
    @State private var topLifts: [(exerciseName: String, e1rm: Double)] = []

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.sectionSpacing) {
                        headerCard
                        statsGrid
                        if let vm = viewModel, !vm.setsPerMuscleGroup.isEmpty {
                            MuscleGroupChartView(
                                setsPerGroup: vm.setsPerMuscleGroup,
                                volumePerGroup: vm.volumePerMuscleGroup
                            )
                        }
                        if !topLifts.isEmpty {
                            topLiftsSection
                        }
                        if let vm = viewModel, !vm.personalRecords.isEmpty {
                            personalRecordsSection(vm: vm)
                        }
                        signOutButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Profile")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { loadProfileData() }
            .sheet(isPresented: $showEditSheet) {
                if let vm = viewModel, let userId = environment.authService.currentUser()?.userId {
                    EditProfileView(viewModel: vm, userId: userId, userEmail: environment.supabaseClient.auth.currentUser?.email ?? "")
                        .onDisappear {
                            vm.cancelEditing()
                        }
                }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.2))
                    .frame(width: 60, height: 60)
                Text(initials)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Member since \(memberSince)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Button(action: {
                print("[ProfileView] Edit button tapped, viewModel exists: \(viewModel != nil)")
                viewModel?.startEditing()
                showEditSheet = true
                print("[ProfileView] After startEditing, isEditing: \(viewModel?.isEditing ?? false), showEditSheet: \(showEditSheet)")
            }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .cardStyle()
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(icon: "flame.fill", iconColor: AppTheme.streakFlame, value: "\(streak)", label: "Streak")
            statCard(icon: "figure.strengthtraining.traditional", iconColor: AppTheme.accent, value: "\(totalSessions)", label: "Sessions")
            statCard(icon: "scalemass", iconColor: AppTheme.accentSecondary, value: formatVolume(totalVolume), label: "Total Volume")
            statCard(icon: "clock", iconColor: AppTheme.success, value: "\(averageSessionDuration)", label: "Avg Min")
        }
    }

    private func statCard(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .shadow(color: iconColor.opacity(0.3), radius: 4)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .cardStyle()
    }

    // MARK: - Top Lifts

    private var topLiftsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Lifts (est. 1RM)")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(topLifts, id: \.exerciseName) { lift in
                HStack {
                    Text(lift.exerciseName)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(String(format: "%.0f lbs", lift.e1rm))
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accentSecondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
        .cardStyle()
    }

    // MARK: - Personal Records

    private func personalRecordsSection(vm: ProfileViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Records")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(vm.personalRecords.prefix(5)) { pr in
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(AppTheme.warning)
                        .font(.caption)
                    Text(pr.exerciseName)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(String(format: "%.1f lbs × %d", pr.weightLbs, pr.reps))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentSecondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
        .cardStyle()
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button(action: { environment.authService.signOut() }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(.headline)
            .foregroundStyle(AppTheme.destructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.destructive.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers

    private func loadProfileData() {
        guard let userId = environment.authService.currentUser()?.userId else {
            print("[ProfileView] No userId found")
            return
        }
        print("[ProfileView] Creating ProfileViewModel for userId: \(userId)")
        let vm = environment.makeProfileViewModel()
        vm.loadStats(userId: userId)
        vm.loadProfile(userId: userId)
        print("[ProfileView] Profile loaded, isEditing: \(vm.isEditing), profile exists: \(vm.profile != nil)")
        streak = vm.streak
        totalSessions = vm.totalSessions
        totalVolume = vm.totalVolume
        averageSessionDuration = vm.averageSessionDuration
        topLifts = vm.topLifts
        viewModel = vm
        print("[ProfileView] ViewModel assigned")
    }

    private var displayName: String {
        environment.authService.currentUser()?.displayName ?? "Athlete"
    }

    private var initials: String {
        let name = displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
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
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.0fK", volume / 1_000)
        }
        return String(format: "%.0f", volume)
    }
}
