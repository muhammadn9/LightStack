import SwiftUI

/// Full detail view for a past workout session.
/// Shows complete set log table, AI progression note, and user note.
struct WorkoutDetailView: View {
    @EnvironmentObject var environment: AppEnvironment
    let viewModel: HistoryViewModel

    /// Held in state so the header, title and sets refresh after a save.
    @State private var workout: Workout
    @State private var repeatWorkoutContext: RepeatWorkoutContext?
    @State private var draft: WorkoutEditDraft?
    @State private var fieldErrors: [WorkoutEditDraft.DraftFieldError] = []
    @State private var showAddExercise = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(workout: Workout, viewModel: HistoryViewModel) {
        _workout = State(initialValue: workout)
        self.viewModel = viewModel
    }

    private var isEditing: Bool { draft != nil }

    @State private var exercises: [Exercise] = []
    @State private var setsByExercise: [UUID: [WorkoutSet]] = [:]
    @State private var isInProgress = false

    /// Loads exercises, sets and in-progress status once (not from `body`).
    /// In-progress checks the live session service and the persisted session
    /// (covers a cold start before the Today tab has restored it).
    private func reload() {
        let exs = viewModel.fetchExercises(workoutId: workout.id)
        var sets: [UUID: [WorkoutSet]] = [:]
        for ex in exs { sets[ex.id] = viewModel.fetchSets(exerciseId: ex.id) }
        exercises = exs
        setsByExercise = sets
        isInProgress = environment.workoutSessionService.currentWorkoutId == workout.id
            || environment.sessionPersistence.restoreSession()?.workout.id == workout.id
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                if draft != nil {
                    WorkoutEditForm(
                        draft: Binding(
                            get: { draft ?? WorkoutEditDraft(workout: workout, exercises: [], sets: [:]) },
                            set: { draft = $0 }
                        ),
                        errors: fieldErrors,
                        onAddExercise: { showAddExercise = true }
                    )
                    .padding(20)
                } else {
                VStack(spacing: AppTheme.sectionSpacing) {
                    headerSection
                    exercisesSection
                    NoteCardView(
                        icon: "pencil.and.list.clipboard",
                        iconColor: AppTheme.accent,
                        title: "Pre-Workout Notes",
                        content: workout.setupNote
                    )
                    NoteCardView(
                        icon: "note.text",
                        iconColor: AppTheme.accentSecondary,
                        title: "My Notes",
                        content: workout.userNote
                    )
                    NoteCardView(
                        icon: "sparkles",
                        iconColor: AppTheme.accent,
                        title: "AI Progression Note",
                        content: workout.aiProgressionNote
                    )

                    if !isEditing {
                        repeatButton
                            .padding(.bottom, 8)
                    }
                }
                .padding(20)
                }
            }
        }
        .navigationTitle(workout.workoutType)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { reload() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelEditing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .fontWeight(.semibold)
                }
            } else if !isInProgress {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { startEditing() }
                        .accessibilityLabel("Edit workout")
                }
            }
        }
        .sheet(isPresented: $showAddExercise) {
            ExerciseCatalogPicker { name, muscleGroup in
                draft?.addExercise(name: name, muscleGroup: muscleGroup)
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) { deleteWorkout() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("All exercises were removed, so the workout will be deleted.")
        }
        .fullScreenCover(item: $repeatWorkoutContext) { ctx in
            WorkoutSessionSheet(
                todayViewModel: ctx.todayViewModel,
                workoutType: ctx.workoutType,
                mode: .repeatExisting,
                onDismiss: { repeatWorkoutContext = nil }
            )
            .environmentObject(environment)
        }
    }

    // MARK: - Editing

    private func startEditing() {
        fieldErrors = []
        draft = WorkoutEditDraft(workout: workout, exercises: exercises, sets: setsByExercise)
    }

    private func cancelEditing() {
        draft = nil
        fieldErrors = []
    }

    private func attemptSave() {
        guard let current = draft,
              let userId = environment.authService.currentUser()?.userId else { return }
        let errors = current.validate()
        fieldErrors = errors
        guard errors.isEmpty else { return }
        if current.isEmpty {
            showDeleteConfirm = true
            return
        }
        if let updated = viewModel.saveEdits(original: workout, draft: current, userId: userId) {
            workout = updated
            draft = nil
            reload()
        }
    }

    private func deleteWorkout() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        viewModel.deleteWorkout(workout, userId: userId)
        dismiss()
    }

    // MARK: - Repeat Button

    private var repeatButton: some View {
        Button(action: startRepeatWorkout) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                Text("Use This Workout Today")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.accentGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    private func startRepeatWorkout() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        let vm = environment.makeInlineTodayViewModel()
        vm.setUserIdSkipRestore(userId)
        let exs = viewModel.fetchExercises(workoutId: workout.id)
        vm.loadExistingWorkout(exercises: exs, workoutType: workout.workoutType)
        repeatWorkoutContext = RepeatWorkoutContext(todayViewModel: vm, workoutType: workout.workoutType)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(formatDate(workout.date))
                .font(AppTheme.playfair(18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 16) {
                if let duration = workout.durationMinutes {
                    statPill(icon: "clock", value: "\(duration) min")
                }
                statPill(icon: "scalemass", value: formatVolume(totalVolume))
            }
        }
        .cardStyle()
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.accentSecondary)
            Text(value)
                .font(AppTheme.plexMono(10))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exercise.name)
                            .font(AppTheme.playfairItalic(16, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text(exercise.muscleGroup)
                            .font(AppTheme.caveat(11))
                            .foregroundStyle(AppTheme.accentSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.accent.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }

                    VStack(spacing: 4) {
                        ForEach(setsForExercise(exercise.id)) { set in
                            SetRowView(workoutSet: set)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func setsForExercise(_ exerciseId: UUID) -> [WorkoutSet] {
        setsByExercise[exerciseId] ?? []
    }

    private var totalVolume: Double {
        var volume = 0.0
        for exercise in exercises {
            for set in setsForExercise(exercise.id) {
                volume += set.weightLbs * Double(set.reps)
            }
        }
        return volume
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatter.weekdayMonthDayYear.string(from: date)
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

// MARK: - Repeat Workout Support

private struct RepeatWorkoutContext: Identifiable {
    let id = UUID()
    let todayViewModel: TodayViewModel
    let workoutType: String
}
