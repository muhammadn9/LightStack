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
    @State private var showFinishConfirm = false
    @State private var currentExerciseIndex = 0
    @State private var exercisePendingRemoval: Exercise?
    @State private var showAddExercise = false
    @State private var showReorder = false
    /// Scroll position of the card pager; mirrors `currentExerciseIndex`.
    @State private var scrolledPage: Int? = 0

    // Form Analysis
    @State private var formCaptureExercise: Exercise?
    @State private var formFeedbackResult: FormAnalysisResult?
    @State private var formDemoExercise: Exercise?
    @State private var formViewModel: FormAnalysisViewModel?

    var body: some View {
        VStack(spacing: 0) {
            timerBar
            if !todayViewModel.exercises.isEmpty {
                cardsPager
                pageIndicator
            }
            bottomBar
        }
        .themedBackground()
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) {
            if let pr = todayViewModel.lastPR {
                prToast(pr: pr)
            }
        }
        .onAppear {
            viewModel.startTimer(from: todayViewModel.activeWorkoutElapsed)
            if todayViewModel.timerPaused { viewModel.pauseTimer() }
            viewModel.previousHints = todayViewModel.previousHints
            // After a relaunch the display copy is empty; seed it from the
            // authoritative (persisted) copy so logged sets stay logged.
            if viewModel.loggedSets.isEmpty, !todayViewModel.loggedSets.isEmpty {
                viewModel.loggedSets = todayViewModel.loggedSets
            }
            // Restore typed-but-unlogged rows saved before the app was closed.
            if !todayViewModel.pendingSetsSnapshot.isEmpty {
                viewModel.pendingSets = todayViewModel.pendingSetsSnapshot
                todayViewModel.pendingSetsSnapshot = [:]
            }
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
            persistSession()
            viewModel.stopTimer()
        }
        .onChange(of: todayViewModel.exerciseListResetToken) { _, _ in
            currentExerciseIndex = 0
        }
        .onChange(of: todayViewModel.targetsRevision) { _, _ in
            for exercise in todayViewModel.exercises {
                viewModel.refreshTargets(for: exercise)
            }
            clampPageIndex()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.syncElapsed()
                viewModel.refreshRestTimers()
            } else {
                // iOS may terminate the app once backgrounded; save typed
                // rows and the clock so a relaunch picks up where we left off.
                persistSession()
            }
        }
        .sheet(isPresented: $showChat) {
            // No floating keyboard Done pill here: it would cover the chat input.
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
        .sheet(isPresented: $showAddExercise) {
            ExerciseCatalogPicker(loadYourExercises: { todayViewModel.historyExercises() }) { name, muscleGroup in
                addExercise(name: name, muscleGroup: muscleGroup)
            }
            .keyboardDoneButton()
        }
        .sheet(isPresented: $showReorder) {
            ReorderExercisesSheet(exercises: todayViewModel.exercises) { unitOrder in
                applyReorder(unitOrder)
            }
        }
        .alert(
            "Remove \(exercisePendingRemoval?.name ?? "exercise")?",
            isPresented: Binding(
                get: { exercisePendingRemoval != nil },
                set: { if !$0 { exercisePendingRemoval = nil } }
            ),
            presenting: exercisePendingRemoval
        ) { exercise in
            Button("Remove", role: .destructive) {
                todayViewModel.removeExercise(at: exercise.id)
                clampPageIndex()
                exercisePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { exercisePendingRemoval = nil }
        } message: { exercise in
            let count = viewModel.loggedSets[exercise.id]?.count ?? 0
            Text(count > 0
                 ? "This also deletes its \(count) logged \(count == 1 ? "set" : "sets")."
                 : "It will be removed from this workout.")
        }
        .alert("Finish workout?", isPresented: $showFinishConfirm) {
            if loggedTotals.sets == 0 {
                Button("Discard Workout", role: .destructive) {
                    viewModel.cancelAllRestTimers()
                    todayViewModel.discardWorkout()
                }
                .accessibilityIdentifier("discardFromFinishButton")
            } else {
                Button("Finish") { performFinish() }
                    .accessibilityIdentifier("confirmFinishWorkoutButton")
            }
            Button("Keep Training", role: .cancel) {}
                .accessibilityIdentifier("keepTrainingButton")
        } message: {
            Text(finishConfirmMessage)
        }
        .alert("Discard Workout?", isPresented: $showCancelAlert) {
            Button("Discard", role: .destructive) {
                viewModel.cancelAllRestTimers()
                todayViewModel.discardWorkout()
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("All logged sets will be lost.")
        }
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        ActiveWorkoutTimerBar(
            viewModel: viewModel,
            workoutType: todayViewModel.sessionService.currentWorkoutType,
            runningVolume: viewModel.runningVolume(exercises: todayViewModel.exercises),
            onCancel: { showCancelAlert = true }
        )
    }

    // MARK: - Current Page View

    /// One card per exercise, or per superset (rows interleaved round by round).
    /// Cards sit side by side with the neighbours peeking in; swipe to page.
    private var cardsPager: some View {
        let pages = SupersetGroup.pages(from: todayViewModel.exercises)
        let safeIndex = min(currentExerciseIndex, max(0, pages.count - 1))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    let isCurrent = index == safeIndex
                    pageView(page, pages: pages, safeIndex: index)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.interactive) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                .opacity(phase.isIdentity ? 1 : 0.7)
                        }
                        .allowsHitTesting(isCurrent)
                        .overlay {
                            // Neighbours are inert previews; tapping one brings it forward.
                            // The overlay also keeps the peek area a valid swipe start.
                            if !isCurrent {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { currentExerciseIndex = index }
                            }
                        }
                        .accessibilityHidden(!isCurrent)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 32, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledPage)
        .scrollClipDisabled()
        .padding(.vertical, 8)
        .onAppear { scrolledPage = safeIndex }
        .onChange(of: scrolledPage) { _, newValue in
            if let newValue, newValue != currentExerciseIndex, newValue < pages.count {
                currentExerciseIndex = newValue
            }
        }
        .onChange(of: currentExerciseIndex) { _, newValue in
            if scrolledPage != newValue {
                withAnimation(.easeInOut(duration: 0.3)) { scrolledPage = newValue }
            }
        }
        .sensoryFeedback(.selection, trigger: currentExerciseIndex)
    }

    private var pageIndicator: some View {
        let count = SupersetGroup.pages(from: todayViewModel.exercises).count
        let current = min(currentExerciseIndex, max(0, count - 1))
        return VStack(spacing: 5) {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index == current ? AppTheme.accent : AppTheme.border)
                        .frame(width: index == current ? 16 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            .animation(.easeOut(duration: 0.2), value: current)
            Text("\(current + 1) of \(count)")
                .font(AppTheme.plexMono(12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private func pageView(_ page: SupersetPage, pages: [SupersetPage], safeIndex: Int) -> some View {
        let exercises = todayViewModel.exercises
        let members = page.exerciseIds.compactMap { id in exercises.first { $0.id == id } }
        let nextName: String? = safeIndex + 1 < pages.count
            ? exercises.first { $0.id == pages[safeIndex + 1].exerciseIds.first }?.name
            : nil
        let rows = SupersetRounds.rows(
            memberIds: page.exerciseIds,
            logged: viewModel.loggedSets,
            pending: viewModel.pendingSets
        )
        let loggedTotal = members.reduce(0) { $0 + (viewModel.loggedSets[$1.id]?.count ?? 0) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ExerciseHeaderView(
                    members: members,
                    evidence: todayViewModel.evidence,
                    exerciseIndex: { exerciseIndex(of: $0) },
                    totalCount: pages.count,
                    canLinkWithNext: members.last.map { todayViewModel.canLinkWithNext($0.id) } ?? false,
                    onAdd: { showAddExercise = true },
                    isRestRunning: viewModel.isRestRunning(for: members.map(\.id)),
                    onToggleRest: { toggleRest(for: members) },
                    onFormDemo: { formDemoExercise = members.first },
                    onRecordForm: { formCaptureExercise = members.first },
                    onLinkWithNext: {
                        if let last = members.last { todayViewModel.linkWithNext(last.id) }
                    },
                    onUnlink: {
                        if let gid = page.groupId { todayViewModel.unlinkSuperset(groupId: gid) }
                    },
                    onRemove: { exercisePendingRemoval = $0 },
                    onReorder: { showReorder = true }
                )

                InkDivider()

                pageRows(rows: rows, members: members, isSuperset: page.isSuperset)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: loggedTotal)

                InkDivider()

                // Add set (a round, on a superset page)
                Button(action: {
                    viewModel.addRound(for: members)
                    members.forEach { syncPlannedSetCount(for: $0) }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text(page.isSuperset ? "Add Round" : "Add Set")
                    }
                    .font(AppTheme.caveat(13, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(minHeight: AppTheme.minTouchSize, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("addSetButton")

                // Optional one-tap verdict per exercise, once it has a logged set.
                ForEach(members) { member in
                    if member.trackingType != .cardio, !(viewModel.loggedSets[member.id] ?? []).isEmpty {
                        ExerciseFeedbackPicker(exercise: member, exerciseIndex: exerciseIndex(of: member))
                            .id(member.id)
                    }
                }

                // Rest timer banner (a superset's timer is keyed by the member that triggered it)
                if let restId = viewModel.activeRestExerciseId,
                   members.contains(where: { $0.id == restId }),
                   let target = viewModel.restTimerTargetDates[restId] {
                    RestBannerView(
                        target: target,
                        totalSeconds: viewModel.restTimerTotalSeconds[restId] ?? RestPreference.defaultSeconds,
                        nextExerciseName: nextName,
                        onEnd: { viewModel.cancelRestTimer(for: members.map(\.id)) }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8),
                       value: members.contains { viewModel.activeRestExerciseId == $0.id })
            .padding(16)
            .padding(.bottom, 67)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        .onChange(of: exercises.count) { _, _ in
            for ex in exercises {
                viewModel.prefillTargets(for: ex)
            }
        }
    }

    /// Logged and pending rows. On a superset page rows are grouped under "Round N"
    /// and each row is captioned with its exercise's name.
    @ViewBuilder
    private func pageRows(rows: [SupersetRow], members: [Exercise], isSuperset: Bool) -> some View {
        let byId = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let headers = columnHeaderRowIds(rows: rows, byId: byId)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                if let exercise = byId[row.exerciseId] {
                    VStack(alignment: .leading, spacing: 6) {
                        if isSuperset, isFirstRowOfRound(row, in: rows) {
                            Text("Round \(row.round + 1)")
                                .font(AppTheme.caveat(15, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, row.round == 0 ? 0 : 4)
                        }
                        if isSuperset {
                            Text(exercise.name)
                                .font(AppTheme.caveat(13))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }
                        if headers.contains(row.id) {
                            columnHeaders(for: exercise)
                        }
                        setRow(row, exercise: exercise)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
    }

    private func isFirstRowOfRound(_ row: SupersetRow, in rows: [SupersetRow]) -> Bool {
        rows.first { $0.round == row.round }?.id == row.id
    }

    /// Ids of pending rows that get a column-header line: the first pending row, and
    /// any later one whose tracking type differs from the pending row before it.
    private func columnHeaderRowIds(rows: [SupersetRow], byId: [UUID: Exercise]) -> Set<UUID> {
        var ids = Set<UUID>()
        var previous: TrackingType?
        for row in rows where row.isPending {
            guard let type = byId[row.exerciseId]?.trackingType else { continue }
            if previous != type { ids.insert(row.id) }
            previous = type
        }
        return ids
    }

    private func columnHeaders(for exercise: Exercise) -> some View {
        let labels = exercise.trackingType == .cardio ? ["Time", "Distance", "Incline"] : ["lbs", "reps", "RIR"]
        return HStack(spacing: 9) {
            Text("").frame(width: 22)
            Text(labels[0]).font(AppTheme.caveat(11)).foregroundStyle(AppTheme.textSecondary).frame(width: 78)
            Text(labels[1]).font(AppTheme.caveat(11)).foregroundStyle(AppTheme.textSecondary).frame(width: 67)
            Text(labels[2]).font(AppTheme.caveat(11)).foregroundStyle(AppTheme.textSecondary).frame(width: 56)
            Spacer()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func setRow(_ row: SupersetRow, exercise: Exercise) -> some View {
        switch row.kind {
        case .logged(let index):
            if let set = viewModel.loggedSets[exercise.id]?[safe: index] {
                LoggedSetRow(
                    workoutSet: set,
                    number: index + 1,
                    exercise: exercise,
                    idPrefix: "loggedSet.\(exerciseIndex(of: exercise)).\(index)",
                    onDelete: {
                        viewModel.deleteSet(set, exerciseId: exercise.id)
                        todayViewModel.deleteLoggedSet(set, exerciseId: exercise.id)
                        viewModel.syncPendingSets(for: exercise)
                    }
                )
            }
        case .pending(let index):
            let loggedCount = viewModel.loggedSets[exercise.id]?.count ?? 0
            let binding = pendingSetsBinding(for: exercise.id)
            if exercise.trackingType == .cardio {
                CardioPendingSetRow(
                    index: index,
                    setNumber: loggedCount + index + 1,
                    pendingSets: binding,
                    exerciseId: exercise.id,
                    idPrefix: "setRow.\(exerciseIndex(of: exercise)).\(index)",
                    onLog: { logSet(at: index, exerciseId: exercise.id) },
                    onDelete: {
                        viewModel.deletePendingSet(at: index, exerciseId: exercise.id)
                        syncPlannedSetCount(for: exercise)
                    }
                )
            } else {
                StrengthPendingSetRow(
                    index: index,
                    setNumber: loggedCount + index + 1,
                    pendingSets: binding,
                    exerciseId: exercise.id,
                    idPrefix: "setRow.\(exerciseIndex(of: exercise)).\(index)",
                    onLog: { logSet(at: index, exerciseId: exercise.id) },
                    onDelete: {
                        viewModel.deletePendingSet(at: index, exerciseId: exercise.id)
                        syncPlannedSetCount(for: exercise)
                    }
                )
            }
        }
    }

    // MARK: - Finish Button (amber wax-seal style)

    private var bottomBar: some View {
        HStack(spacing: 10) {
            finishButton
            chatButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(AppTheme.background)
        .overlay(alignment: .top) {
            InkDivider()
        }
    }

    private var finishButton: some View {
        Button(action: { showFinishConfirm = true }) {
            HStack(spacing: 9) {
                Text("✦")
                    .font(.title3)
                Text("Finish Workout")
                    .font(AppTheme.playfairItalic(17, weight: .bold))
            }
            .foregroundStyle(AppTheme.onAccent)
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
        .accessibilityIdentifier("finishWorkoutButton")
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
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppTheme.onAccent)
                .frame(width: 56, height: 56)
                .background(AppTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.accent.opacity(0.4), lineWidth: 1)
                )
        }
        .accessibilityLabel("Chat with coach")
    }

    // MARK: - Helpers

    /// Keeps the planned set count equal to logged + pending rows, so a removed row
    /// is not topped back up (and re-prefilled) when the session is restored.
    private func syncPlannedSetCount(for exercise: Exercise) {
        guard let i = todayViewModel.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        let total = (viewModel.loggedSets[exercise.id]?.count ?? 0) + (viewModel.pendingSets[exercise.id]?.count ?? 0)
        guard todayViewModel.exercises[i].targetSets != total else { return }
        todayViewModel.exercises[i].targetSets = total
        persistSession()
    }

    private func pendingSetsBinding(for exerciseId: UUID) -> Binding<[PendingSetInput]> {
        Binding(
            get: { viewModel.pendingSets[exerciseId] ?? [] },
            set: { viewModel.pendingSets[exerciseId] = $0 }
        )
    }

    private func logSet(at index: Int, exerciseId: UUID, startRest: Bool = true) {
        let exercise = todayViewModel.exercises.first { $0.id == exerciseId }
        guard let workoutSet = viewModel.logPendingSet(at: index, exerciseId: exerciseId, exercise: exercise) else { return }
        let isPR = todayViewModel.logSet(workoutSet, exerciseId: exerciseId)

        if isPR {
            var sets = viewModel.loggedSets[exerciseId] ?? []
            if var lastSet = sets.last {
                lastSet.isPR = true
                sets[sets.count - 1] = lastSet
                viewModel.loggedSets[exerciseId] = sets
            }
        }

        // Strength exercises without a rest time (e.g. repeated from an imported
        // workout) fall back to the preferred rest, matching manual entry.
        // In a superset, only the last member's row in a round starts rest, using
        // the longest rest among the members.
        if startRest,
           let plan = SupersetRounds.restPlan(afterLogging: exerciseId, in: todayViewModel.exercises) {
            viewModel.startRestTimer(for: exerciseId, seconds: plan.seconds, exerciseName: plan.name)
        }
    }

    /// Manual rest button: starts the page's rest with the seconds a logged set would use,
    /// or stops it when already running.
    private func toggleRest(for members: [Exercise]) {
        let ids = members.map(\.id)
        if viewModel.isRestRunning(for: ids) {
            viewModel.cancelRestTimer(for: ids)
        } else if let first = ids.first,
                  let plan = SupersetRounds.manualRestPlan(forPageContaining: first, in: todayViewModel.exercises) {
            viewModel.startRestTimer(for: plan.timerId, seconds: plan.seconds, exerciseName: plan.name)
        }
    }

    static func restSeconds(for exercise: Exercise) -> Int? {
        if let rest = exercise.restSeconds, rest > 0 { return rest }
        return exercise.trackingType == .strength ? RestPreference.defaultSeconds : nil
    }

    private func exerciseIndex(of exercise: Exercise) -> Int {
        todayViewModel.exercises.firstIndex { $0.id == exercise.id } ?? 0
    }

    private func clampPageIndex() {
        let count = SupersetGroup.pages(from: todayViewModel.exercises).count
        currentExerciseIndex = min(currentExerciseIndex, max(0, count - 1))
    }

    private func persistSession() {
        viewModel.syncElapsed()
        todayViewModel.activeWorkoutElapsed = viewModel.elapsedSeconds
        todayViewModel.timerPaused = viewModel.isPaused
        todayViewModel.pendingSetsSnapshot = viewModel.pendingSets
        todayViewModel.saveSessionState()
    }

    private func performFinish() {
        viewModel.cancelAllRestTimers()
        viewModel.syncElapsed()
        todayViewModel.activeWorkoutElapsed = viewModel.elapsedSeconds
        todayViewModel.finishWorkout(userNote: nil)
    }

    private var loggedTotals: (sets: Int, exercises: Int) {
        var sets = 0
        var exercises = 0
        for exercise in todayViewModel.exercises {
            let count = viewModel.loggedSets[exercise.id]?.count ?? 0
            sets += count
            if count > 0 { exercises += 1 }
        }
        return (sets, exercises)
    }

    private var finishConfirmMessage: String {
        let totals = loggedTotals
        guard totals.sets > 0 else {
            return "You haven't logged any sets. This workout won't be saved."
        }
        var message = "\(totals.sets) \(totals.sets == 1 ? "set" : "sets") logged across "
            + "\(totals.exercises) \(totals.exercises == 1 ? "exercise" : "exercises")."
        let hasUnlogged = todayViewModel.exercises.contains { !(viewModel.pendingSets[$0.id] ?? []).isEmpty }
        if hasUnlogged { message += " Unlogged sets won't be saved." }
        return message
    }

    private func prToast(pr: PersonalRecord) -> some View {
        HStack(spacing: 12) {
            PRStamp()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Personal Record!")
                    .font(AppTheme.playfairItalic(18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(pr.exerciseName): \(String(format: "%.1f", pr.weightLbs)) lbs × \(pr.reps)")
                    .font(AppTheme.caveat(16))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(18)
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

    // MARK: - Add / Reorder

    /// Adds an exercise right after the page being shown and jumps to it.
    private func addExercise(name: String, muscleGroup: String) {
        let pagesBefore = SupersetGroup.pages(from: todayViewModel.exercises)
        let after = min(currentExerciseIndex, max(0, pagesBefore.count - 1))
        guard let newId = todayViewModel.addExerciseManually(
            name: name,
            muscleGroup: muscleGroup,
            afterPageIndex: pagesBefore.isEmpty ? nil : after
        ) else { return }
        if let newExercise = todayViewModel.exercises.first(where: { $0.id == newId }) {
            viewModel.prefillTargets(for: newExercise)
            if let hints = todayViewModel.previousHints[newId] {
                viewModel.applyPreviousSession(hints, to: newExercise)
            }
        }
        let pages = SupersetGroup.pages(from: todayViewModel.exercises)
        currentExerciseIndex = pages.firstIndex { $0.exerciseIds.contains(newId) }
            ?? max(0, pages.count - 1)
        persistSession()
    }

    /// Applies the reorder sheet's result, staying on the exercise that was showing.
    private func applyReorder(_ unitOrder: [[UUID]]) {
        let pages = SupersetGroup.pages(from: todayViewModel.exercises)
        let currentIds = Set(pages[safe: currentExerciseIndex]?.exerciseIds ?? [])
        todayViewModel.reorderExercises(unitOrder: unitOrder)
        let updated = SupersetGroup.pages(from: todayViewModel.exercises)
        if let index = updated.firstIndex(where: { !currentIds.isDisjoint(with: $0.exerciseIds) }) {
            currentExerciseIndex = index
        }
        clampPageIndex()
        persistSession()
    }
}


// MARK: - Rest Banner

/// Rest countdown banner. Drives its own once-a-second refresh so the rest of
/// the workout screen doesn't re-render on each tick.
struct RestBannerView: View {
    let target: Date
    let totalSeconds: Int
    let nextExerciseName: String?
    var onEnd: (() -> Void)? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 11) {
                RestTimerRing(progress: ActiveWorkoutViewModel.restProgress(
                    target: target, total: totalSeconds, now: context.date))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rest Period")
                        .font(AppTheme.caveat(15, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let nextExerciseName {
                        Text("Next: \(nextExerciseName)")
                            .font(AppTheme.plexMono(10))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Spacer()
                Text(ActiveWorkoutViewModel.restText(target: target, now: context.date))
                    .font(AppTheme.plexMono(16, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                if let onEnd {
                    Button(action: onEnd) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: AppTheme.minTouchSize, height: AppTheme.minTouchSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("End rest")
                    .accessibilityIdentifier("endRestButton")
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(AppTheme.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
