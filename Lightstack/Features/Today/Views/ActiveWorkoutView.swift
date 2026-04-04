import SwiftUI

/// Live workout logging screen. Displays the full exercise table
/// and allows inline set logging (weight x reps x RIR).
struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: ActiveWorkoutViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    @ObservedObject var chatViewModel: CoachChatViewModel
    @State private var showChat = false
    @State private var showCancelAlert = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                timerBar
                exerciseList
                finishButton
            }

            chatButton
        }
        .overlay(alignment: .top) {
            if let pr = todayViewModel.lastPR {
                prToast(pr: pr)
            }
        }
        .onAppear { viewModel.startTimer(from: todayViewModel.activeWorkoutElapsed) }
        .onDisappear {
            todayViewModel.activeWorkoutElapsed = viewModel.elapsedSeconds
            viewModel.stopTimer()
            todayViewModel.saveSessionState()
        }
        .sheet(isPresented: $showChat) {
            CoachChatView(viewModel: chatViewModel, todayViewModel: todayViewModel)
        }
        .alert("Discard Workout?", isPresented: $showCancelAlert) {
            Button("Discard", role: .destructive) {
                todayViewModel.resetToSetup()
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("All logged sets will be lost.")
        }
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        HStack(spacing: 10) {
            Button(action: { showCancelAlert = true }) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(6)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
            }

            Image(systemName: "hourglass")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)

            Text(viewModel.formattedElapsedTime)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)

            Button(action: { viewModel.togglePause() }) {
                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accent)
                    .padding(6)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
            }

            Spacer()

            let volume = runningVolume
            if volume > 0 {
                Text(String(format: "%.0f lbs", volume))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.accent.opacity(0.3), lineWidth: 1))
            }

            Text("\(todayViewModel.exercises.count) ex")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(todayViewModel.exercises) { exercise in
                    ExerciseTableView(
                        exercise: exercise,
                        loggedSets: viewModel.loggedSets[exercise.id] ?? [],
                        pendingSets: pendingSetsBinding(for: exercise.id),
                        restTimeRemaining: viewModel.formattedRestTime(for: exercise.id),
                        onLogSet: { index in logSetForExercise(at: index, exerciseId: exercise.id) },
                        onDeletePendingSet: { index in
                            viewModel.deletePendingSet(at: index, exerciseId: exercise.id)
                        },
                        onDeleteSet: { workoutSet in
                            viewModel.deleteSet(workoutSet, exerciseId: exercise.id)
                            viewModel.syncPendingSets(for: exercise)
                        },
                        onAddSet: { viewModel.addPendingSet(for: exercise) }
                    )
                }
            }
            .padding(16)
            .padding(.bottom, 60)
        }
        .onAppear {
            for exercise in todayViewModel.exercises {
                viewModel.prefillTargets(for: exercise)
            }
        }
        .onChange(of: todayViewModel.exercises.count) { _, _ in
            for exercise in todayViewModel.exercises {
                viewModel.prefillTargets(for: exercise)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .foregroundStyle(AppTheme.accent)
            }
        }
    }

    // MARK: - Finish Button

    private func autoLogAllPendingSets() {
        for exercise in todayViewModel.exercises {
            let exerciseId = exercise.id
            // Iterate a copy since logSetForExercise mutates pendingSets
            let count = viewModel.pendingSets[exerciseId]?.count ?? 0
            var logged = 0
            for _ in 0..<count {
                // Always target index 0 because each log removes the entry
                if let set = viewModel.pendingSets[exerciseId], !set.isEmpty,
                   !set[0].reps.isEmpty {
                    logSetForExercise(at: 0, exerciseId: exerciseId)
                    logged += 1
                } else {
                    break
                }
            }
        }
    }

    private var finishButton: some View {
        Button(action: {
            autoLogAllPendingSets()
            todayViewModel.finishWorkout(userNote: nil)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                Text("Finish Workout")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
            }
            .foregroundStyle(Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.successGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color(hex: 0x2A6A2A).opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x2A6A2A).opacity(0.3), radius: 2, x: 1, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    // MARK: - Chat Button

    private var chatButton: some View {
        Button(action: {
            if let userId = todayViewModel.userId,
               let workoutType = todayViewModel.sessionService.currentWorkoutType {
                chatViewModel.configure(
                    userId: userId,
                    workoutType: workoutType,
                    exercises: todayViewModel.exercises,
                    loggedSets: todayViewModel.loggedSets
                )
            }
            showChat = true
        }) {
            Image(systemName: "text.bubble")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1))
                .frame(width: 52, height: 52)
                .background(AppTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.accent.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, x: 2, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 80)
    }

    // MARK: - Helpers

    private var runningVolume: Double {
        var volume = 0.0
        for exercise in todayViewModel.exercises {
            for s in viewModel.loggedSets[exercise.id] ?? [] {
                volume += s.weightLbs * Double(s.reps)
            }
        }
        return volume
    }

    private func pendingSetsBinding(for exerciseId: UUID) -> Binding<[PendingSetInput]> {
        Binding(
            get: { viewModel.pendingSets[exerciseId] ?? [] },
            set: { viewModel.pendingSets[exerciseId] = $0 }
        )
    }

    private func logSetForExercise(at index: Int, exerciseId: UUID) {
        guard let workoutSet = viewModel.logPendingSet(at: index, exerciseId: exerciseId) else { return }
        let isPR = todayViewModel.logSet(workoutSet, exerciseId: exerciseId)

        if isPR {
            var sets = viewModel.loggedSets[exerciseId] ?? []
            if var lastSet = sets.last {
                lastSet.isPR = true
                sets[sets.count - 1] = lastSet
                viewModel.loggedSets[exerciseId] = sets
            }
        }

        if let exercise = todayViewModel.exercises.first(where: { $0.id == exerciseId }),
           let rest = exercise.restSeconds, rest > 0 {
            viewModel.startRestTimer(for: exerciseId, seconds: rest, exerciseName: exercise.name)
        }
    }

    private func prToast(pr: PersonalRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.warning)
                .shadow(color: AppTheme.warning.opacity(0.5), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Personal Record!")
                    .font(.headline.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(pr.exerciseName): \(String(format: "%.1f", pr.weightLbs)) lbs × \(pr.reps)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.warning.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: AppTheme.warning.opacity(0.3), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: todayViewModel.lastPR != nil)
    }
}
