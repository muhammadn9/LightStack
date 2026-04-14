import SwiftUI

/// Live workout logging screen. Shows one exercise at a time with notebook journal styling.
struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: ActiveWorkoutViewModel
    @ObservedObject var todayViewModel: TodayViewModel
    @ObservedObject var chatViewModel: CoachChatViewModel
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    @State private var showChat = false
    @State private var showCancelAlert = false
    @State private var currentExerciseIndex = 0

    // Form Analysis
    @State private var formCaptureExercise: Exercise?
    @State private var formFeedbackResult: FormAnalysisResult?
    @State private var formDemoExercise: Exercise?
    @State private var formViewModel: FormAnalysisViewModel?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                timerBar
                if !todayViewModel.exercises.isEmpty {
                    currentExerciseView
                        .id(currentExerciseIndex)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .animation(.easeInOut(duration: 0.25), value: currentExerciseIndex)
                }
                finishButton
            }

            chatButton
        }
        .overlay(alignment: .top) {
            if let pr = todayViewModel.lastPR {
                prToast(pr: pr)
            }
        }
        .onAppear {
            viewModel.startTimer(from: todayViewModel.activeWorkoutElapsed)
            for exercise in todayViewModel.exercises {
                viewModel.prefillTargets(for: exercise)
            }
            if formViewModel == nil {
                formViewModel = FormAnalysisViewModel(
                    poseService: PoseEstimationService(),
                    repCounter: RepCounterService(),
                    feedbackService: FormFeedbackService(aiServiceManager: environment.aiServiceManager)
                )
            }
        }
        .onDisappear {
            todayViewModel.activeWorkoutElapsed = viewModel.elapsedSeconds
            viewModel.stopTimer()
            todayViewModel.saveSessionState()
        }
        .onChange(of: todayViewModel.exerciseListResetToken) { _ in
            currentExerciseIndex = 0
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.refreshRestTimers()
            }
        }
        .sheet(isPresented: $showChat) {
            CoachChatView(viewModel: chatViewModel, todayViewModel: todayViewModel)
        }
        .sheet(item: $formDemoExercise) { exercise in
            ExerciseFormDemoView(exerciseName: exercise.name) {
                formDemoExercise = nil
                formCaptureExercise = exercise
            }
        }
        .fullScreenCover(item: $formCaptureExercise) { exercise in
            if let vm = formViewModel {
                FormCaptureView(viewModel: vm, exerciseName: exercise.name) { result in
                    formFeedbackResult = result
                }
            }
        }
        .sheet(item: $formFeedbackResult) { result in
            FormFeedbackView(result: result)
        }
        .alert("Discard Workout?", isPresented: $showCancelAlert) {
            Button("Discard", role: .destructive) {
                todayViewModel.resetToSetup()
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("All logged sets will be lost.")
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

    // MARK: - Timer Bar

    private var timerBar: some View {
        HStack(spacing: 0) {
            // Left: workout type + timer
            VStack(alignment: .leading, spacing: 2) {
                Text(todayViewModel.sessionService.currentWorkoutType ?? "Workout")
                    .font(AppTheme.playfairItalic(10))
                    .foregroundStyle(Color(adaptiveDark: 0x8AAAD4, light: 0x5A7AAE))
                HStack(spacing: 6) {
                    Button(action: { showCancelAlert = true }) {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Text(viewModel.formattedElapsedTime)
                        .font(AppTheme.plexMono(16, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                    Button(action: { viewModel.togglePause() }) {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }

            Spacer()

            // Right: volume
            let volume = runningVolume
            if volume > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Volume")
                        .font(AppTheme.caveat(11))
                        .foregroundStyle(Color(adaptiveDark: 0x8AAAD4, light: 0x5A7AAE))
                    Text(String(format: "%.0f lbs", volume))
                        .font(AppTheme.plexMono(13, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(adaptiveDark: 0x1B3A6B, light: 0x1B3A6B))
        .overlay(alignment: .bottom) {
            InkDivider()
        }
    }

    // MARK: - Current Exercise View

    private var currentExerciseView: some View {
        let exercises = todayViewModel.exercises
        let exercise = exercises[currentExerciseIndex]
        let nextExercise: Exercise? = currentExerciseIndex + 1 < exercises.count
            ? exercises[currentExerciseIndex + 1]
            : nil

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Exercise header + navigation
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(AppTheme.playfair(17, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        HStack(spacing: 4) {
                            Text(exercise.muscleGroup)
                                .font(AppTheme.caveat(12))
                                .foregroundStyle(AppTheme.textSecondary)
                            if let target = exercise.targetSets {
                                Text("· \(target) sets")
                                    .font(AppTheme.caveat(12))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    Spacer()
                    // Form Guide & Watch Form
                    HStack(spacing: 6) {
                        Button(action: { formDemoExercise = exercise }) {
                            Image(systemName: "figure.stand")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(6)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
                        }
                        Button(action: { formCaptureExercise = exercise }) {
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(6)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
                        }
                    }
                    // Exercise navigation
                    HStack(spacing: 6) {
                        if currentExerciseIndex > 0 {
                            Button(action: {
                                withAnimation { currentExerciseIndex -= 1 }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(6)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
                            }
                        }
                        Text("\(currentExerciseIndex + 1)/\(exercises.count)")
                            .font(AppTheme.plexMono(11))
                            .foregroundStyle(AppTheme.textSecondary)
                        if currentExerciseIndex < exercises.count - 1 {
                            Button(action: {
                                withAnimation { currentExerciseIndex += 1 }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(6)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.border, lineWidth: 1))
                            }
                        }
                    }
                }

                InkDivider()

                // Logged sets
                let logged = viewModel.loggedSets[exercise.id] ?? []
                ForEach(Array(logged.enumerated()), id: \.element.id) { index, set in
                    loggedSetRow(set, number: index + 1, exerciseId: exercise.id)
                }

                // Pending set inputs
                let pending = viewModel.pendingSets[exercise.id] ?? []
                if !pending.isEmpty {
                    // Column headers
                    HStack(spacing: 8) {
                        Text("")
                            .frame(width: 24)
                        Text("lbs")
                            .font(AppTheme.caveat(10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 70)
                        Text("reps")
                            .font(AppTheme.caveat(10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 60)
                        Text("RIR")
                            .font(AppTheme.caveat(10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 50)
                        Spacer()
                    }
                    .padding(.top, 2)
                }

                let pendingBinding = pendingSetsBinding(for: exercise.id)
                ForEach(Array(pending.enumerated()), id: \.element.id) { index, _ in
                    pendingSetRow(
                        index: index,
                        setNumber: logged.count + index + 1,
                        pendingSets: pendingBinding,
                        exerciseId: exercise.id
                    )
                }

                InkDivider()

                // Add set button
                Button(action: { viewModel.addPendingSet(for: exercise) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Add Set")
                    }
                    .font(AppTheme.caveat(12, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                // Rest timer banner
                if let restTime = viewModel.formattedRestTime(for: exercise.id) {
                    HStack(spacing: 10) {
                        RestTimerRing(progress: restTimerProgress(for: exercise.id))
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest Period")
                                .font(AppTheme.caveat(13, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                            if let next = nextExercise {
                                Text("Next: \(next.name)")
                                    .font(AppTheme.plexMono(9))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        Spacer()
                        Text(restTime)
                            .font(AppTheme.plexMono(14, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }
            }
            .padding(16)
            .padding(.bottom, 60)
        }
        .themedBackground()
        .onChange(of: exercises.count) { _, _ in
            for ex in exercises {
                viewModel.prefillTargets(for: ex)
            }
        }
    }

    // MARK: - Logged Set Row (notebook style)

    private func loggedSetRow(_ workoutSet: WorkoutSet, number: Int, exerciseId: UUID) -> some View {
        HStack(spacing: 8) {
            SetNumberCircle(number: number, isLogged: true)

            Text(String(format: "%.1f", workoutSet.weightLbs))
                .font(AppTheme.caveat(14, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("lbs")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Text("×\(workoutSet.reps)")
                .font(AppTheme.caveat(14, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            if workoutSet.isPR {
                PRStamp()
            } else {
                Text("✓ RIR \(workoutSet.rir)")
                    .font(AppTheme.caveat(11))
                    .foregroundStyle(AppTheme.success)
            }

            Button(action: {
                viewModel.deleteSet(workoutSet, exerciseId: exerciseId)
                viewModel.syncPendingSets(for: todayViewModel.exercises.first { $0.id == exerciseId }!)
            }) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.caption)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(AppTheme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Pending Set Row (input)

    private func pendingSetRow(index: Int, setNumber: Int, pendingSets: Binding<[PendingSetInput]>, exerciseId: UUID) -> some View {
        HStack(spacing: 8) {
            SetNumberCircle(number: setNumber, isLogged: false)

            // Weight field
            VStack(spacing: 2) {
                TextField("lbs", text: pendingSets[index].weight)
                    .keyboardType(.decimalPad)
                    .font(AppTheme.plexMono(14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(pendingSets[index].weight.wrappedValue.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 70, height: 1.5)
            }

            Text("×")
                .font(AppTheme.caveat(16))
                .foregroundStyle(AppTheme.border)

            // Reps field
            VStack(spacing: 2) {
                TextField("reps", text: pendingSets[index].reps)
                    .keyboardType(.numberPad)
                    .font(AppTheme.plexMono(14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(pendingSets[index].reps.wrappedValue.isEmpty ? AppTheme.border : AppTheme.accent.opacity(0.7))
                    .frame(width: 60, height: 1.5)
            }

            // RIR field
            VStack(spacing: 2) {
                TextField("RIR", text: pendingSets[index].rir)
                    .keyboardType(.numberPad)
                    .font(AppTheme.plexMono(14))
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
                    .foregroundStyle(AppTheme.textPrimary)
                Rectangle()
                    .fill(AppTheme.border.opacity(0.5))
                    .frame(width: 50, height: 1.5)
            }

            // Log button
            Button(action: { logSet(at: index, exerciseId: exerciseId) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pendingSets[index].reps.wrappedValue.isEmpty ? AppTheme.surfaceElevated : AppTheme.accent)
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pendingSets[index].reps.wrappedValue.isEmpty
                                         ? AppTheme.textSecondary
                                         : Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1))
                }
                .shadow(color: AppTheme.accent.opacity(pendingSets[index].reps.wrappedValue.isEmpty ? 0 : 0.3), radius: 2, x: 1, y: 2)
            }
            .disabled(pendingSets[index].reps.wrappedValue.isEmpty)

            // Delete pending
            Button(action: { viewModel.deletePendingSet(at: index, exerciseId: exerciseId) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.warning.opacity(0.7))
                    .font(.caption)
            }
        }
    }

    // MARK: - Finish Button (amber wax-seal style)

    private var finishButton: some View {
        Button(action: {
            autoLogAllPendingSets()
            todayViewModel.finishWorkout(userNote: nil)
        }) {
            HStack(spacing: 8) {
                Text("✦")
                Text("Finish Workout")
                    .font(AppTheme.playfairItalic(15, weight: .bold))
            }
            .foregroundStyle(Color(adaptiveDark: 0x1C1510, light: 0xFBF8F1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.accent.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: AppTheme.accent.opacity(0.3), radius: 2, x: 1, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
        .overlay(alignment: .top) {
            InkDivider()
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
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
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

    private func logSet(at index: Int, exerciseId: UUID) {
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

    private func logSetForExercise(at index: Int, exerciseId: UUID) {
        logSet(at: index, exerciseId: exerciseId)
    }

    private func autoLogAllPendingSets() {
        for exercise in todayViewModel.exercises {
            let exerciseId = exercise.id
            let count = viewModel.pendingSets[exerciseId]?.count ?? 0
            for _ in 0..<count {
                if let set = viewModel.pendingSets[exerciseId], !set.isEmpty,
                   !set[0].reps.isEmpty {
                    logSet(at: 0, exerciseId: exerciseId)
                } else {
                    break
                }
            }
        }
    }

    private func restTimerProgress(for exerciseId: UUID) -> Double {
        guard let target = viewModel.restTimerTargetDates[exerciseId] else { return 0 }
        let total = Double(viewModel.restTimerTotalSeconds[exerciseId] ?? 90)
        let remaining = max(0, target.timeIntervalSinceNow)
        return total > 0 ? (total - remaining) / total : 0
    }

    private func prToast(pr: PersonalRecord) -> some View {
        HStack(spacing: 12) {
            PRStamp()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Personal Record!")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(pr.exerciseName): \(String(format: "%.1f", pr.weightLbs)) lbs × \(pr.reps)")
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.prStamp.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: AppTheme.prStamp.opacity(0.2), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: todayViewModel.lastPR != nil)
    }
}
