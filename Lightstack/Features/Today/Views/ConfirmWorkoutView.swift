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
        VStack(spacing: 6) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Workout Ready")
                .font(AppTheme.playfairItalic(20, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Your coach prepared \(todayViewModel.exercises.count) exercises")
                .font(AppTheme.caveat(15))
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
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("Tap × to remove")
                    .font(AppTheme.caveat(10))
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
                        .font(AppTheme.playfair(14, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(exercise.muscleGroup)
                        .font(AppTheme.caveat(11))
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
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
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
                .font(AppTheme.caveat(12))
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
        VStack(spacing: 10) {
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
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                        Text("Chat with Coach")
                    }
                }
                .buttonStyle(WaxSealButtonStyle(isSecondary: true))
            }

            Button(action: { todayViewModel.confirmAndStartWorkout() }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("Start Workout")
                }
            }
            .buttonStyle(WaxSealButtonStyle(isSecondary: false))
        }
        .padding(.horizontal, 4)
    }
}
