import SwiftUI

/// Manual workout entry: create workout, add exercises manually without AI.
struct ManualWorkoutEntryView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var todayViewModel: TodayViewModel
    let userId: UUID

    @State private var workoutType = ""
    @State private var exercises: [ManualExercise] = []
    @State private var showAddExercise = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        workoutTypeSection
                        exercisesSection
                        addExerciseButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Manual Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        startManualWorkout()
                    }
                    .foregroundStyle(AppTheme.accent)
                    .disabled(!canStart)
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseSheet(exercises: $exercises)
            }
        }
    }

    // MARK: - Sections

    private var workoutTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Type")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            TextField("e.g., Upper Body, Legs, Push", text: $workoutType)
                .padding(14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
        }
        .cardStyle()
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises (\(exercises.count))")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if exercises.isEmpty {
                Text("No exercises added yet. Tap + to add.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    exerciseRow(exercise, index: index)
                }
            }
        }
        .cardStyle()
    }

    private func exerciseRow(_ exercise: ManualExercise, index: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(exercise.muscleGroup) • \(exercise.targetSets) sets")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Button(action: {
                exercises.remove(at: index)
            }) {
                Image(systemName: "trash")
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var addExerciseButton: some View {
        Button(action: { showAddExercise = true }) {
            Label("Add Exercise", systemImage: "plus.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Logic

    private var canStart: Bool {
        !workoutType.trimmingCharacters(in: .whitespaces).isEmpty && !exercises.isEmpty
    }

    private func startManualWorkout() {
        let workout = Workout.create(
            userId: userId,
            workoutType: workoutType.trimmingCharacters(in: .whitespaces),
            energyLevel: nil,
            timeAvailableMinutes: nil
        )

        let exerciseModels = exercises.enumerated().map { index, ex in
            Exercise.create(
                workoutId: workout.id,
                name: ex.name,
                muscleGroup: ex.muscleGroup,
                orderIndex: index,
                targetSets: ex.targetSets,
                targetReps: nil,
                targetRir: nil,
                restSeconds: nil,
                coachNote: nil
            )
        }

        todayViewModel.sessionService.startSession(workout: workout, exercises: exerciseModels)
        todayViewModel.exercises = exerciseModels
        todayViewModel.phase = .active

        dismiss()
    }
}

// MARK: - Manual Exercise Model

struct ManualExercise {
    let name: String
    let muscleGroup: String
    let targetSets: Int
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var exercises: [ManualExercise]

    @State private var exerciseName = ""
    @State private var selectedMuscleGroup = "Chest"
    @State private var targetSets = 3

    private let muscleGroups = [
        "Chest", "Back", "Shoulders", "Biceps", "Triceps",
        "Legs", "Quads", "Hamstrings", "Glutes", "Calves",
        "Core", "General"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        exerciseNameSection
                        muscleGroupSection
                        targetSetsSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addExercise()
                    }
                    .foregroundStyle(AppTheme.accent)
                    .disabled(exerciseName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var exerciseNameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise Name")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            TextField("e.g., Bench Press, Squat", text: $exerciseName)
                .padding(14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
        }
        .cardStyle()
    }

    private var muscleGroupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Muscle Group")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Picker("Muscle Group", selection: $selectedMuscleGroup) {
                ForEach(muscleGroups, id: \.self) { group in
                    Text(group).tag(group)
                }
            }
            .pickerStyle(.menu)
            .padding(14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .cardStyle()
    }

    private var targetSetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target Sets: \(targetSets)")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Stepper(value: $targetSets, in: 1...10) {
                Text("\(targetSets) sets")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .cardStyle()
    }

    private func addExercise() {
        let exercise = ManualExercise(
            name: exerciseName.trimmingCharacters(in: .whitespaces),
            muscleGroup: selectedMuscleGroup,
            targetSets: targetSets
        )
        exercises.append(exercise)
        dismiss()
    }
}
