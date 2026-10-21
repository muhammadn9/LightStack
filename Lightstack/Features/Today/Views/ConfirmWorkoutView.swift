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
    @State private var swapTarget: Exercise?
    @State private var showDiscardConfirm = false
    @State private var showCoachSaw = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                cancelRow
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
        .sheet(isPresented: $showCoachSaw) {
            if let userId = todayViewModel.userId { CoachSawView(userId: userId) }
        }
        .sheet(item: $swapTarget) { exercise in
            ExerciseSwapSheet(todayViewModel: todayViewModel, exercise: exercise, onFinish: {})
        }
        .alert("Discard this workout plan?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) { todayViewModel.discardPlanPreview() }
                .accessibilityIdentifier("previewDiscardConfirmButton")
            Button("Keep", role: .cancel) {}
                .accessibilityIdentifier("previewKeepButton")
        } message: {
            Text("Nothing will be saved. You will go back to setup.")
        }
    }

    // MARK: - Cancel

    /// A way out of the preview, in case "Create workout" was tapped by accident.
    private var cancelRow: some View {
        HStack {
            Button(action: { showDiscardConfirm = true }) {
                Text("Cancel")
                    .font(AppTheme.caveat(17, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minWidth: AppTheme.minTouchSize, minHeight: AppTheme.minTouchSize, alignment: .leading)
            }
            .accessibilityIdentifier("previewCancelButton")
            .accessibilityHint("Discards this workout plan")
            Spacer()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(.title, design: .default, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Workout Ready")
                .font(AppTheme.playfairItalic(20, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Your coach prepared \(todayViewModel.exercises.count) exercises")
                .font(AppTheme.caveat(15))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button { showCoachSaw = true } label: {
                Text("What the coach saw")
                    .font(AppTheme.caveat(14, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: AppTheme.minTouchSize)
            }
            .accessibilityIdentifier("plan.coachSaw")
        }
        .frame(maxWidth: .infinity)
        .lsCard()
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

            let supersetIds = Set(SupersetGroup.pages(from: todayViewModel.exercises)
                .filter(\.isSuperset).flatMap(\.exerciseIds))
            ForEach(todayViewModel.exercises) { exercise in
                exerciseCard(exercise, isInSuperset: supersetIds.contains(exercise.id))
            }
        }
        .lsCard()
    }

    private func exerciseCard(_ exercise: Exercise, isInSuperset: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: name + muscle group on the left, swap / remove on the right.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(AppTheme.playfair(14, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(exercise.muscleGroup)
                        .font(AppTheme.caveat(11))
                        .foregroundStyle(AppTheme.accentSecondary)
                }

                Spacer(minLength: 8)

                Button(action: { swapTarget = exercise }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(.title3, design: .default, weight: .regular))
                        .foregroundStyle(AppTheme.accent)
                        .frame(minWidth: AppTheme.minTouchSize, minHeight: AppTheme.minTouchSize)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("previewSwap.\(todayViewModel.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0)")
                .accessibilityLabel("Swap \(exercise.name)")
                .accessibilityHint("Shows other exercises you could do instead")

                Button(action: {
                    todayViewModel.applyModification(
                        .removeExercise(name: exercise.name),
                        preserveLoggedSets: false
                    )
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.title3, design: .default, weight: .regular))
                        .foregroundStyle(AppTheme.warning)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(exercise.name)")
                .accessibilityHint("Removes this exercise from the workout plan")
            }

            // Coach's message, shown once per exercise, full card width
            if let message = exercise.coachNoteParts.message {
                Text(message)
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let evidence = todayViewModel.evidence[exercise.id] {
                PlanEvidenceBlock(
                    evidence: evidence,
                    exerciseIndex: todayViewModel.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0)
            }

            // Per-set rows, full card width
            setRows(for: exercise)

            supersetControls(for: exercise, isInSuperset: isInSuperset)
        }
        .padding(12)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    /// "Superset" tag plus link/unlink actions for one exercise card.
    private func supersetControls(for exercise: Exercise, isInSuperset: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { supersetControlItems(for: exercise, isInSuperset: isInSuperset) }
            VStack(alignment: .leading, spacing: 4) { supersetControlItems(for: exercise, isInSuperset: isInSuperset) }
        }
    }

    @ViewBuilder
    private func supersetControlItems(for exercise: Exercise, isInSuperset: Bool) -> some View {
        if isInSuperset {
            Label("Superset", systemImage: "link")
                .font(AppTheme.caveat(13, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            if let gid = exercise.supersetGroupId {
                Button("Unlink") { todayViewModel.unlinkSuperset(groupId: gid) }
                    .font(AppTheme.caveat(13, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(minHeight: AppTheme.minTouchSize)
                    .accessibilityIdentifier("confirm.unlink")
                    .accessibilityLabel("Unlink \(exercise.name) from its superset")
            }
        }
        if todayViewModel.canLinkWithNext(exercise.id) {
            Button(isInSuperset ? "Add next" : "Superset with next") {
                todayViewModel.linkWithNext(exercise.id)
            }
            .font(AppTheme.caveat(13, weight: .bold))
            .foregroundStyle(AppTheme.accent)
            .frame(minHeight: AppTheme.minTouchSize)
            .accessibilityIdentifier("confirm.supersetWithNext")
            .accessibilityLabel("Superset \(exercise.name) with the next exercise")
        }
    }

    /// Renders one row per target set showing weight × reps @ RIR.
    @ViewBuilder
    private func setRows(for exercise: Exercise) -> some View {
        let count = max(1, exercise.targetSets ?? 1)
        let weight = exercise.coachNoteParts.weight ?? ""
        let reps = exercise.targetReps ?? "—"
        let rir: String = {
            guard let r = exercise.targetRir,
                  let range = r.range(of: #"\d+"#, options: .regularExpression)
            else { return "—" }
            return String(r[range])
        }()

        let perSet = todayViewModel.setTargets[exercise.id] ?? []

        let exerciseIndex = todayViewModel.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0

        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            ForEach(1...count, id: \.self) { setNum in
                // A swapped-in lift can carry different numbers per set.
                let target: SetTarget? = perSet.indices.contains(setNum - 1) ? perSet[setNum - 1] : nil
                let rowWeight = target.map { $0.prefillWeight }.flatMap { $0.isEmpty ? nil : $0 } ?? weight
                let rowReps = target.map { $0.prefillReps }.flatMap { $0.isEmpty ? nil : $0 } ?? reps
                let rowRir = target.map { $0.prefillRir }.flatMap { $0.isEmpty ? nil : $0 } ?? rir
                let isWarmup = target?.isWarmup == true
                let weightText = Self.compactWeight(rowWeight)
                let repsText = "× \(rowReps)"
                let rirText = rowRir == "—" ? "" : "@ RIR \(rowRir)"
                GridRow {
                    HStack(spacing: 4) {
                        Text("Set \(setNum)")
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                        if isWarmup {
                            Text("W")
                                .font(AppTheme.caveat(10, weight: .bold))
                                .foregroundStyle(AppTheme.warning)
                                .padding(.horizontal, 4)
                                .background(AppTheme.warning.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .fixedSize()
                                .accessibilityIdentifier("plan.warmup.\(exerciseIndex).\(setNum - 1)")
                        }
                    }
                    Text(weightText)
                        .opacity(isWarmup ? 0.6 : 1)
                        .lineLimit(1)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                    Text(repsText)
                        .lineLimit(1)
                        .fixedSize()
                    Text(rirText)
                        .foregroundStyle(AppTheme.accent.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(AppTheme.caveat(12).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.rowLabel(setNum, isWarmup ? "warm-up" : "", weightText, repsText, rirText))
                .accessibilityIdentifier("plan.setRow.\(exerciseIndex).\(setNum - 1)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "140 lb" for numbers (any trailing "lbs"/"lb" normalised), "BW" kept, "—" when empty.
    private static func compactWeight(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "—" }
        if t.uppercased().contains("BW") || t.lowercased().contains("bodyweight") { return "BW" }
        guard let r = t.range(of: #"^\d+(\.\d+)?"#, options: .regularExpression) else { return t }
        let num = String(t[r])
        if t.lowercased().contains("kg") { return "\(num) kg" }
        return "\(num) lb"
    }

    private static func rowLabel(_ setNum: Int, _ tag: String, _ weight: String, _ reps: String, _ rir: String) -> String {
        [ "Set \(setNum)", tag, weight, reps, rir ].filter { !$0.isEmpty }.joined(separator: " ")
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
                        .font(.system(.caption, design: .default, weight: .regular))
                    Text("Start Workout")
                }
            }
            .buttonStyle(WaxSealButtonStyle(isSecondary: false))
            .accessibilityIdentifier("startWorkoutButton")
        }
        .padding(.horizontal, 4)
    }
}
