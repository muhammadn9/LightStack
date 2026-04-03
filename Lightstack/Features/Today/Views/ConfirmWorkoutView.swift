import SwiftUI

/// Shows the AI-generated workout plan for user confirmation before starting.
/// Each exercise lists its individual sets so the user can review volume,
/// remove exercises, or chat with the coach before committing.
struct ConfirmWorkoutView: View {
    @ObservedObject var todayViewModel: TodayViewModel
    /// Optional — when provided, a "Chat with Coach" button appears.
    var chatViewModel: CoachChatViewModel? = nil
    /// Workout type label used when configuring the chat context.
    var workoutType: String = ""

    @State private var showChat = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                exerciseList
                actionButtons
            }
            .padding(16)
        }
        .themedBackground()
        .sheet(isPresented: $showChat) {
            if let chatVM = chatViewModel {
                CoachChatView(viewModel: chatVM, todayViewModel: todayViewModel)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.accent)
            Text("Workout Ready")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Your AI coach prepared \(todayViewModel.exercises.count) exercises")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Exercise Plan")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("Tap × to remove")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            ForEach(todayViewModel.exercises) { exercise in
                exerciseCard(exercise)
            }
        }
        .cardStyle()
    }

    private func exerciseCard(_ exercise: Exercise) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // Name + muscle group
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(exercise.muscleGroup)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentSecondary)
                }

                // Per-set rows
                setRows(for: exercise)
            }

            Spacer()

            Button(action: {
                todayViewModel.applyModification(
                    .removeExercise(name: exercise.name),
                    preserveLoggedSets: false
                )
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.warning)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Renders one row per target set showing weight × reps @ RIR.
    @ViewBuilder
    private func setRows(for exercise: Exercise) -> some View {
        let count = max(1, exercise.targetSets ?? 1)
        let weight = extractWeight(from: exercise.coachNote)
        let reps = exercise.targetReps ?? "—"
        let rir: String = {
            guard let r = exercise.targetRir,
                  let range = r.range(of: #"\d+"#, options: .regularExpression)
            else { return "—" }
            return String(r[range])
        }()

        VStack(alignment: .leading, spacing: 4) {
            ForEach(1...count, id: \.self) { setNum in
                HStack(spacing: 6) {
                    Text("Set \(setNum)")
                        .frame(width: 38, alignment: .leading)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    if !weight.isEmpty {
                        Text(weight)
                    }
                    Text("×")
                    Text("\(reps) reps")
                    if rir != "—" {
                        Text("@ RIR \(rir)")
                            .foregroundStyle(AppTheme.accent.opacity(0.8))
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textPrimary)
            }
        }
    }

    private func extractWeight(from coachNote: String?) -> String {
        guard let note = coachNote else { return "" }
        let prefix = "Target: "
        return note.hasPrefix(prefix) ? String(note.dropFirst(prefix.count)) : note
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Chat with Coach button (only shown when chatViewModel is provided)
            if let chatVM = chatViewModel {
                Button(action: {
                    if let userId = todayViewModel.userId {
                        let wt = workoutType.isEmpty
                            ? (todayViewModel.sessionService.currentWorkoutType ?? "")
                            : workoutType
                        chatVM.configure(
                            userId: userId,
                            workoutType: wt,
                            exercises: todayViewModel.exercises,
                            loggedSets: [:]
                        )
                    }
                    showChat = true
                }) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Chat with Coach")
                    }
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
            }

            // Start Workout button
            Button(action: { todayViewModel.confirmAndStartWorkout() }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Workout")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
        .padding(.horizontal, 4)
    }
}
