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
                ExerciseCatalogPicker { name, muscleGroup in
                    exercises.append(ManualExercise(name: name, muscleGroup: muscleGroup, targetSets: 3))
                }
            }
        }
    }

    // MARK: - Sections

    private var workoutTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Type")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("e.g., Upper Body, Legs, Push", text: $workoutType)
                .padding(14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
                .submitLabel(.done)
                .onSubmit {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        }
        .cardStyle()
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises (\(exercises.count))")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            if exercises.isEmpty {
                Text("No exercises added yet. Tap + to add.")
                    .font(AppTheme.caveat(15))
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
                    .font(AppTheme.playfair(14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(exercise.muscleGroup)
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    guard exercises[index].targetSets > 1 else { return }
                    exercises[index] = ManualExercise(name: exercise.name, muscleGroup: exercise.muscleGroup, targetSets: exercise.targetSets - 1)
                }) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text("\(exercise.targetSets)")
                    .font(AppTheme.plexMono(13, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minWidth: 20)

                Button(action: {
                    guard exercises[index].targetSets < 10 else { return }
                    exercises[index] = ManualExercise(name: exercise.name, muscleGroup: exercise.muscleGroup, targetSets: exercise.targetSets + 1)
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(AppTheme.accent)
                }
            }

            Button(action: {
                exercises.remove(at: index)
            }) {
                Image(systemName: "trash")
                    .foregroundStyle(AppTheme.warning)
            }
            .padding(.leading, 8)
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private var addExerciseButton: some View {
        Button(action: { showAddExercise = true }) {
            Label("Add Exercise", systemImage: "plus.circle.fill")
                .font(AppTheme.caveat(15, weight: .bold))
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
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
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
                restSeconds: 90,
                coachNote: nil
            )
        }

        // Create the workout record before starting session so it appears in history
        todayViewModel.workoutRepository.createWorkout(workout)
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

