# LightStack Bug Fixes Round 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **CRITICAL:** Any new `.swift` file MUST be added to `Lightstack.xcodeproj/project.pbxproj` (PBXFileReference + PBXGroup + PBXBuildFile + Sources phase). The project will not compile otherwise.

**Goal:** Fix six bugs across Today, History, Month Plan, and Profile tabs, plus replace the app icon.

**Architecture:** SwiftUI + ObservableObject ViewModels, AppEnvironment DI, local-first Core Data + Supabase. `HistoryListView` stores its VM as `@State` (reference type not observed — root cause of filter bug). `EditProfileView` renders only preset goal chips (missing dynamic custom chips — root cause of profile bug). Month tab "Start This Workout" just switches tabs without triggering generation.

**Tech Stack:** Swift/SwiftUI iOS 17+, Core Data, AppEnvironment DI container, Python/Pillow for icon conversion.

---

## Task 1: Today Tab — Richer Confirmation Screen with Exercise Removal

**Files:**
- Modify: `Lightstack/Features/Today/Views/ConfirmWorkoutView.swift`

### Problem
`ConfirmWorkoutView` shows exercise name + target sets/reps in a static read-only list. Users need to see full exercise details (target weight, RIR, rest) and be able to remove exercises they don't want before starting.

### Root Cause
The `exerciseList` renders static `HStack` rows with no interaction. No delete action is wired. `TodayViewModel.applyModification(.removeExercise(name:))` already exists and works — it just isn't called from here.

### Fix Steps

- [ ] **Step 1: Read the current file**

Read `Lightstack/Features/Today/Views/ConfirmWorkoutView.swift` in full.

- [ ] **Step 2: Expand exercise rows to show full details**

In `exerciseList`, replace the `HStack` row with a richer card. Each row shows: exercise name (headline), muscle group (caption), and a row of detail badges (sets, reps, weight target, RIR, rest). Extract weight from `exercise.coachNote` (format: `"Target: 135 lbs"`).

Replace the entire `exerciseList` computed var with:

```swift
private var exerciseList: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("Exercise Plan")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text("Swipe left to remove")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }

        ForEach(todayViewModel.exercises) { exercise in
            exerciseConfirmRow(exercise)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        todayViewModel.applyModification(
                            .removeExercise(name: exercise.name),
                            preserveLoggedSets: false
                        )
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
        }
    }
    .cardStyle()
}

private func exerciseConfirmRow(_ exercise: Exercise) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(exercise.muscleGroup)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accentSecondary)
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(AppTheme.textSecondary)
        }

        HStack(spacing: 8) {
            if let sets = exercise.targetSets {
                confirmBadge("\(sets) sets", color: AppTheme.accent)
            }
            if let reps = exercise.targetReps {
                confirmBadge(reps, color: AppTheme.accentSecondary)
            }
            if let note = exercise.coachNote {
                let weight = note.replacingOccurrences(of: "Target: ", with: "")
                confirmBadge(weight, color: AppTheme.textSecondary)
            }
            if let rir = exercise.targetRir {
                confirmBadge("RIR \(rir)", color: AppTheme.textSecondary)
            }
        }
    }
    .padding(12)
    .background(AppTheme.surfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: 10))
}

private func confirmBadge(_ text: String, color: Color) -> some View {
    Text(text)
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
}
```

Note: `ForEach` with `.swipeActions` requires the parent to be a `List` OR the items to not be inside `LazyVStack`. Since this is a `VStack` inside `ScrollView`, `.swipeActions` won't render as a swipe gesture — instead, add a trailing delete button inline:

Actually `.swipeActions` does NOT work on `VStack` rows — it only works on `List` rows. Use a long-press context menu or inline delete button instead. Use a trailing red `xmark.circle.fill` button:

```swift
private func exerciseConfirmRow(_ exercise: Exercise) -> some View {
    HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(exercise.muscleGroup)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if let sets = exercise.targetSets {
                    confirmBadge("\(sets) sets", color: AppTheme.accent)
                }
                if let reps = exercise.targetReps {
                    confirmBadge(reps, color: AppTheme.accentSecondary)
                }
                if let note = exercise.coachNote {
                    let weight = note.replacingOccurrences(of: "Target: ", with: "")
                    confirmBadge(weight, color: AppTheme.textSecondary)
                }
                if let rir = exercise.targetRir {
                    confirmBadge("RIR \(rir)", color: AppTheme.textSecondary)
                }
            }
        }

        Button(action: {
            todayViewModel.applyModification(
                .removeExercise(name: exercise.name),
                preserveLoggedSets: false
            )
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.warning.opacity(0.8))
                .padding(.leading, 12)
        }
    }
    .padding(12)
    .background(AppTheme.surfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: 10))
}
```

- [ ] **Step 3: Commit**

```bash
git add Lightstack/Features/Today/Views/ConfirmWorkoutView.swift
git commit -m "feat: expand confirmation screen with exercise details and removal"
```

---

## Task 2: Today Tab — All Sets Visible Upfront + Swipe-to-Delete + Last-Weight Prefill

**Files:**
- Modify: `Lightstack/Features/Today/Views/ExerciseTableView.swift`
- Modify: `Lightstack/Features/Today/ViewModels/ActiveWorkoutViewModel.swift`
- Modify: `Lightstack/Features/Today/Views/ActiveWorkoutView.swift`

### Problem
1. Only logged sets appear in `ExerciseTableView`. User expects to see all N target sets upfront as rows to fill in.
2. Can't delete a logged set if accidentally added.
3. After logging set 1 at 135 lbs, prefill resets to AI target instead of carrying the last-logged weight forward.

### Root Cause
- `loggedSetsList` renders only `loggedSets` (which is empty until the user logs). Target set count comes from `exercise.targetSets`.
- `resetToTargets(for:)` calls `prefillTargets(for:)` which reads from AI target (coachNote), not last-logged set.
- No delete callback exists in `ExerciseTableView`.

### Fix Steps

- [ ] **Step 1: Add delete callback and onDeleteSet to ExerciseTableView signature**

In `ExerciseTableView.swift`, add an optional delete callback parameter:

```swift
struct ExerciseTableView: View {
    let exercise: Exercise
    let loggedSets: [WorkoutSet]
    @Binding var editingWeight: String
    @Binding var editingReps: String
    @Binding var editingRir: String
    @Binding var editingNote: String
    let restTimeRemaining: String?
    let onLogSet: () -> Void
    let onDeleteSet: ((WorkoutSet) -> Void)?   // ADD THIS
```

- [ ] **Step 2: Update loggedSetsList to include delete gesture**

Replace `loggedSetsList` with a version that shows set number and allows deletion:

```swift
private var loggedSetsList: some View {
    ForEach(Array(loggedSets.enumerated()), id: \.element.id) { index, workoutSet in
        HStack {
            Text("Set \(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, alignment: .leading)
            SetRowView(workoutSet: workoutSet)
            Spacer()
            if let onDelete = onDeleteSet {
                Button(action: { onDelete(workoutSet) }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(AppTheme.warning.opacity(0.7))
                        .font(.body)
                }
            }
        }
        .opacity(index.isMultiple(of: 2) ? 1.0 : 0.9)
    }
}
```

- [ ] **Step 3: Show pending (unlogged) set rows**

After `loggedSetsList`, add rows for remaining target sets (those not yet logged). A pending row is a lighter-styled placeholder showing the set number and expected targets:

```swift
// In body, after loggedSetsList:
pendingSetRows
```

```swift
private var pendingSetRows: some View {
    let target = exercise.targetSets ?? 0
    let logged = loggedSets.count
    guard target > logged else { return AnyView(EmptyView()) }
    return AnyView(
        ForEach((logged + 1)...target, id: \.self) { setNumber in
            HStack {
                Text("Set \(setNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                    .frame(width: 44, alignment: .leading)
                HStack(spacing: 8) {
                    if let note = exercise.coachNote {
                        Text(note.replacingOccurrences(of: "Target: ", with: ""))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                    }
                    if let reps = exercise.targetReps {
                        Text("× \(reps)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.surfaceElevated, lineWidth: 1)
            )
        }
    )
}
```

- [ ] **Step 4: Update body to include pendingSetRows in correct order**

In `body`, update the VStack to include `pendingSetRows` between `loggedSetsList` and the rest timer banner:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        headerRow
        targetInfoRow
        loggedSetsList
        pendingSetRows    // ADD after logged sets
        if let restTime = restTimeRemaining {
            restTimerBanner(restTime)
        }
        inputRow
    }
    .glowingCard()
}
```

- [ ] **Step 5: Fix weight prefill to use last-logged weight, not AI target**

In `ActiveWorkoutViewModel.swift`, update `resetToTargets(for:)` to use the last logged set's weight/reps/RIR as the prefill for the next set (carry-forward from previous set):

```swift
/// Reset fields after logging — carry forward last-logged values (not AI targets).
func resetToTargets(for exercise: Exercise) {
    // Use last logged set's values as the starting point for next set
    if let lastSet = loggedSets[exercise.id]?.last {
        editingWeight[exercise.id] = String(format: "%g", lastSet.weightLbs)
        editingReps[exercise.id] = String(lastSet.reps)
        editingRir[exercise.id] = String(lastSet.rir ?? 2)
        editingNote[exercise.id] = nil
    } else {
        // No sets logged yet — fall back to AI targets
        editingWeight[exercise.id] = nil
        editingReps[exercise.id] = nil
        editingRir[exercise.id] = nil
        editingNote[exercise.id] = nil
        prefillTargets(for: exercise)
    }
}
```

Note: `WorkoutSet` may not have a `rir` property directly — check the model. If `rir` is `Int?` on the model, use `lastSet.rir ?? 2`. If it doesn't exist, just carry weight and reps.

Check `WorkoutSet` model: look in `Lightstack/Core/Models/WorkoutSet.swift` before implementing.

- [ ] **Step 6: Add deleteSet method to ActiveWorkoutViewModel**

```swift
func deleteSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
    loggedSets[exerciseId]?.removeAll { $0.id == workoutSet.id }
}
```

- [ ] **Step 7: Wire onDeleteSet in ActiveWorkoutView**

In `ActiveWorkoutView.swift`, update `ExerciseTableView` call in `exerciseList` to pass `onDeleteSet`:

```swift
ExerciseTableView(
    exercise: exercise,
    loggedSets: viewModel.loggedSets[exercise.id] ?? [],
    editingWeight: binding(for: exercise.id, in: \.editingWeight),
    editingReps: binding(for: exercise.id, in: \.editingReps),
    editingRir: binding(for: exercise.id, in: \.editingRir),
    editingNote: noteBinding(for: exercise.id),
    restTimeRemaining: viewModel.formattedRestTime(for: exercise.id),
    onLogSet: { logSetForExercise(exercise.id) },
    onDeleteSet: { workoutSet in
        viewModel.deleteSet(workoutSet, exerciseId: exercise.id)
    }
)
```

- [ ] **Step 8: Commit**

```bash
git add Lightstack/Features/Today/Views/ExerciseTableView.swift \
        Lightstack/Features/Today/ViewModels/ActiveWorkoutViewModel.swift \
        Lightstack/Features/Today/Views/ActiveWorkoutView.swift
git commit -m "feat: show all target sets upfront, add delete set, carry forward last weight"
```

---

## Task 3: Today Tab — Keyboard Dismiss Button for Numeric Fields

**Files:**
- Modify: `Lightstack/Features/Today/Views/ExerciseTableView.swift`

### Problem
`.numberPad` and `.decimalPad` keyboards have no "Done" button to dismiss them. The user can't dismiss the keyboard after entering weight/reps/RIR.

### Root Cause
The `inputField` helper in `ExerciseTableView` uses `.keyboardType(.decimalPad)` / `.keyboardType(.numberPad)` but does not attach a keyboard toolbar.

### Fix Steps

- [ ] **Step 1: Add a keyboard toolbar Done button to inputRow**

In `ExerciseTableView.swift`, add a `.toolbar` on `inputRow`'s VStack:

```swift
private var inputRow: some View {
    VStack(spacing: 6) {
        HStack(spacing: 8) {
            inputField("lbs", text: $editingWeight, width: 70, keyboard: .decimalPad)
            inputField("reps", text: $editingReps, width: 60, keyboard: .numberPad)
            inputField("RIR", text: $editingRir, width: 50, keyboard: .numberPad)

            Button(action: onLogSet) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 4)
            }
            .disabled(editingWeight.isEmpty || editingReps.isEmpty)
        }
        TextField("Set note (optional)...", text: $editingNote)
            .font(.caption)
            .padding(8)
            .background(AppTheme.surfaceElevated)
            .foregroundStyle(AppTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
```

- [ ] **Step 2: Commit**

```bash
git add Lightstack/Features/Today/Views/ExerciseTableView.swift
git commit -m "fix: add keyboard Done button to numeric input fields"
```

---

## Task 4: Month Tab — Inline Workout Session Sheet on "Start This Workout"

**Files:**
- Modify: `Lightstack/Features/MonthPlan/Views/MonthPlanView.swift`

### Problem
Tapping "Start This Workout" on a planned session switches to the Today tab but does not load any workout. The user wants the workout to be generated and shown without leaving the Month tab (in case Today has a different workout loaded).

### Root Cause
`onStartWorkout` in `MonthPlanView` only sets `selectedTab = 0`. No workout generation is triggered. `TodayViewModel.generatePlan(...)` needs to be called with the session's workout type.

### Approach
Instead of switching to the Today tab, present a full-screen sheet within the Month tab that runs the same `TodayView` workflow (generating → confirmation → active → postWorkout). Use a fresh `TodayViewModel` (via `environment.makeTodayViewModel()`) scoped to this sheet, so it doesn't interfere with an existing Today tab session.

### Fix Steps

- [ ] **Step 1: Read MonthPlanView.swift in full**

Read `Lightstack/Features/MonthPlan/Views/MonthPlanView.swift`.

- [ ] **Step 2: Add inline workout sheet state to MonthPlanView**

Add two `@State` properties to `MonthPlanView`:

```swift
@State private var activeSessionWorkoutType: String? = nil
@State private var inlineWorkoutViewModel: TodayViewModel? = nil
```

- [ ] **Step 3: Replace onStartWorkout with sheet trigger**

In `calendarContent`'s `.sheet(item: $selectedSession)`, update the `onStartWorkout` closure:

```swift
onStartWorkout: {
    let workoutType = session.workoutType
    let vm = environment.makeTodayViewModel()
    // Set the userId so the VM is ready
    if let userId = environment.authService.currentUser()?.userId {
        vm.setUserId(userId)
    }
    selectedSession = nil
    inlineWorkoutViewModel = vm
    activeSessionWorkoutType = workoutType
},
```

- [ ] **Step 4: Present the inline workout sheet**

Add a `.fullScreenCover` (or `.sheet`) triggered by `inlineWorkoutViewModel`:

```swift
.fullScreenCover(item: $inlineWorkoutViewModel) { vm in
    InlineWorkoutSheet(
        todayViewModel: vm,
        workoutType: activeSessionWorkoutType ?? "",
        onDismiss: {
            inlineWorkoutViewModel = nil
            activeSessionWorkoutType = nil
        }
    )
    .environmentObject(environment)
}
```

`TodayViewModel` must conform to `Identifiable` for `.fullScreenCover(item:)` to work. Check if it does — if not, use a `@State private var showInlineWorkout = false` Bool trigger instead:

```swift
// Alternative using Bool:
@State private var showInlineWorkout = false

// In onStartWorkout:
onStartWorkout: {
    let vm = environment.makeTodayViewModel()
    if let userId = environment.authService.currentUser()?.userId {
        vm.setUserId(userId)
    }
    inlineWorkoutViewModel = vm
    activeSessionWorkoutType = session.workoutType
    selectedSession = nil
    showInlineWorkout = true
},

// Attach:
.fullScreenCover(isPresented: $showInlineWorkout) {
    if let vm = inlineWorkoutViewModel {
        InlineWorkoutSheet(
            todayViewModel: vm,
            workoutType: activeSessionWorkoutType ?? "",
            onDismiss: {
                showInlineWorkout = false
                inlineWorkoutViewModel = nil
                activeSessionWorkoutType = nil
            }
        )
        .environmentObject(environment)
    }
}
```

- [ ] **Step 5: Create InlineWorkoutSheet view**

This is a self-contained view that:
1. On appear, auto-triggers `generatePlan` with the given workout type, default energy/time
2. Shows the same phase-based flow as `TodayView` (generating → confirmation → active → postWorkout)
3. Has a dismiss/close button in the nav bar
4. On `phase == .setup` after a workout is saved (reset), auto-dismisses

Since we're NOT adding a new file (to avoid pbxproj complexity), add `InlineWorkoutSheet` as a private struct at the bottom of `MonthPlanView.swift`:

```swift
// MARK: - Inline Workout Sheet (added at bottom of MonthPlanView.swift)

private struct InlineWorkoutSheet: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var todayViewModel: TodayViewModel
    let workoutType: String
    let onDismiss: () -> Void

    @State private var activeWorkoutViewModel: ActiveWorkoutViewModel?
    @State private var chatViewModel: CoachChatViewModel?
    @State private var hasTriggeredGeneration = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                Group {
                    switch todayViewModel.phase {
                    case .setup, .generating:
                        generatingView
                    case .confirmation:
                        ConfirmWorkoutView(todayViewModel: todayViewModel)
                    case .active:
                        if let activeVM = activeWorkoutViewModel {
                            ActiveWorkoutView(
                                viewModel: activeVM,
                                todayViewModel: todayViewModel,
                                chatViewModel: chatViewModel ?? environment.makeCoachChatViewModel()
                            )
                        }
                    case .postWorkout:
                        PostWorkoutView(todayViewModel: todayViewModel)
                    }
                }
            }
            .navigationTitle(workoutType)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onDismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .onAppear {
                if chatViewModel == nil {
                    chatViewModel = environment.makeCoachChatViewModel()
                }
                if !hasTriggeredGeneration {
                    hasTriggeredGeneration = true
                    // Auto-trigger generation with the planned session's workout type
                    todayViewModel.generatePlan(
                        workoutType: workoutType,
                        time: 60,       // default 60 min
                        energy: 3,      // default medium energy
                        notes: nil
                    )
                }
            }
            .onChange(of: todayViewModel.phase) { _, newPhase in
                if newPhase == .active, activeWorkoutViewModel == nil {
                    let vm = environment.makeActiveWorkoutViewModel()
                    vm.onRestTimerStart = { name, seconds in
                        environment.notificationService.scheduleRestTimerAlert(
                            exerciseName: name, totalRestSeconds: seconds
                        )
                    }
                    vm.onRestTimerCancel = {
                        environment.notificationService.cancelPendingRestAlerts()
                    }
                    activeWorkoutViewModel = vm
                } else if newPhase == .setup {
                    // Workout was saved — dismiss the sheet
                    onDismiss()
                }
            }
            .alert("Error", isPresented: .init(
                get: { todayViewModel.errorMessage != nil },
                set: { if !$0 { todayViewModel.errorMessage = nil } }
            )) {
                Button("OK") { todayViewModel.errorMessage = nil }
            } message: {
                Text(todayViewModel.errorMessage ?? "")
            }
        }
    }

    private var generatingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.pulse, options: .repeating)
            Text("Generating \(workoutType) workout...")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Your AI coach is building a plan")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Lightstack/Features/MonthPlan/Views/MonthPlanView.swift
git commit -m "feat: inline workout sheet from month plan Start This Workout button"
```

---

## Task 5: History Tab — Fix Filter Chips Not Filtering

**Files:**
- Modify: `Lightstack/Features/History/Views/HistoryListView.swift`

### Problem
Tapping a filter chip appears to select it (UI highlight changes) but the workout list does not update.

### Root Cause
`HistoryListView` declares `@State private var viewModel: HistoryViewModel?`. `@State` holds a reference to the `ObservableObject` but does NOT subscribe to its `@Published` property changes — so when `vm.filterType` or `vm.workouts` change, the view does not re-render.

The fix: extract the list content into an inner view that declares `@ObservedObject var viewModel: HistoryViewModel`. This inner view re-renders on every `@Published` change.

### Fix Steps

- [ ] **Step 1: Read HistoryListView.swift in full**

Read `Lightstack/Features/History/Views/HistoryListView.swift`.

- [ ] **Step 2: Extract HistoryContentView**

Add a private inner struct `HistoryContentView` at the bottom of the file that takes the view model as `@ObservedObject`. Move all list-rendering logic into it:

```swift
private struct HistoryContentView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterChips
                .padding(.top, 16)
            List {
                ForEach(viewModel.workouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout, viewModel: viewModel)) {
                        workoutCard(workout: workout)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteWorkout(workout)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: viewModel.filterType == nil) {
                    if let userId = environment.authService.currentUser()?.userId {
                        viewModel.setFilter(nil, userId: userId)
                    }
                }
                ForEach(viewModel.availableTypes, id: \.self) { type in
                    filterChip(label: type, isSelected: viewModel.filterType == type) {
                        if let userId = environment.authService.currentUser()?.userId {
                            viewModel.setFilter(type, userId: userId)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        AppTheme.accentGradient
                    } else {
                        AppTheme.surfaceElevated
                    }
                }
                .clipShape(Capsule())
        }
    }

    private func workoutCard(workout: Workout) -> some View {
        let summary = viewModel.workoutSummary(workout)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(spacing: 2) {
                    Text(DateFormatter.dayAbbreviation.string(from: workout.date).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(DateFormatter.dayNumber.string(from: workout.date))
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutType)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    HStack(spacing: 12) {
                        Label("\(summary.exerciseCount) exercises", systemImage: "figure.strengthtraining.traditional")
                        if let duration = workout.durationMinutes {
                            Label("\(duration) min", systemImage: "clock")
                        }
                        Label(formatVolume(summary.totalVolume), systemImage: "scalemass")
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .cardStyle()
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 { return String(format: "%.1fM lbs", volume / 1_000_000) }
        if volume >= 1_000 { return String(format: "%.0fK lbs", volume / 1_000) }
        return String(format: "%.0f lbs", volume)
    }
}
```

- [ ] **Step 3: Simplify HistoryListView to delegate to HistoryContentView**

Update `HistoryListView.body` to use `HistoryContentView` when the vm is loaded. Remove the duplicated `workoutList(vm:)`, `filterChips(vm:)`, `filterChip(...)`, `workoutCard(...)`, `formatVolume` from `HistoryListView` (they're now in the inner view):

```swift
struct HistoryListView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var viewModel: HistoryViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                if let vm = viewModel {
                    if vm.workouts.isEmpty && !vm.isLoading {
                        emptyState
                    } else {
                        HistoryContentView(viewModel: vm)
                    }
                } else {
                    ProgressView().tint(AppTheme.accent)
                }
            }
            .navigationTitle("History")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { loadHistory() }
        }
    }

    // keep emptyState and loadHistory, deleteWorkout, dayAbbrev, dayNumber helpers
    // remove workoutList(vm:), filterChips(vm:), filterChip, workoutCard, formatVolume
    // (they moved to HistoryContentView)
}
```

Important: `deleteWorkout` in `HistoryListView` was calling `vm.deleteWorkout(workout)`. Move the delete action fully into `HistoryContentView` (already done in Step 2 above — uses `viewModel.deleteWorkout(workout)` inline).

Remove the old `dayAbbrev(_:)` and `dayNumber(_:)` instance methods from `HistoryListView` — they're not needed there anymore (moved into `workoutCard` in `HistoryContentView` via `DateFormatter.dayAbbreviation`).

Keep `loadHistory()` in `HistoryListView`:
```swift
private func loadHistory() {
    guard let userId = environment.authService.currentUser()?.userId else { return }
    if viewModel == nil {
        let vm = environment.makeHistoryViewModel()
        vm.loadWorkouts(userId: userId)
        viewModel = vm
    }
}
```

Note the added `if viewModel == nil` guard — prevents recreating the VM (and losing filter state) on every `.onAppear` (e.g., tab switch back).

- [ ] **Step 4: Commit**

```bash
git add Lightstack/Features/History/Views/HistoryListView.swift
git commit -m "fix: history filter chips now re-render list via @ObservedObject inner view"
```

---

## Task 6: Profile Tab — Custom Goals Not Showing After Adding

**Files:**
- Modify: `Lightstack/Features/Profile/Views/EditProfileView.swift`

### Problem
Hitting the "+" button after typing a custom goal doesn't visibly add the goal. The goal IS inserted into `viewModel.editGoals` (a `Set<String>`), but the `FlowLayout` only renders `goalOptions` (the static preset list). Custom goals that aren't in `goalOptions` are never rendered as chips.

### Root Cause
`goalsSection` renders:
```swift
FlowLayout(spacing: 8) {
    ForEach(goalOptions, id: \.self) { goal in goalChip(goal) }
}
```
Custom goals go into `viewModel.editGoals` but there's no `ForEach` over them. The preset chips show as selected/unselected based on `viewModel.editGoals.contains(goal)`, but custom-typed goals are invisible.

### Fix Steps

- [ ] **Step 1: Read EditProfileView.swift lines 91-134 (goalsSection)**

Read `Lightstack/Features/Profile/Views/EditProfileView.swift`, lines 91–135.

- [ ] **Step 2: Add custom goals rendering after preset chips**

In `goalsSection`, after the `FlowLayout` for preset goals, add a `FlowLayout` for custom goals (those in `editGoals` not in `goalOptions`):

```swift
private var goalsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Goals")
            .font(.headline)
            .foregroundStyle(AppTheme.textPrimary)

        // Preset goal chips
        FlowLayout(spacing: 8) {
            ForEach(goalOptions, id: \.self) { goal in
                goalChip(goal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Custom goals (those added by the user, not in the preset list)
        let customGoals = viewModel.editGoals.filter { !goalOptions.contains($0) }.sorted()
        if !customGoals.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(customGoals, id: \.self) { goal in
                    customGoalChip(goal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Text field + add button
        HStack {
            TextField("Add custom goal", text: $newCustomGoal)
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onSubmit { addCustomGoal() }
            Button(action: addCustomGoal) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(
                        newCustomGoal.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AppTheme.textSecondary : AppTheme.accent
                    )
            }
            .disabled(newCustomGoal.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    .cardStyle()
}

private func addCustomGoal() {
    let trimmed = newCustomGoal.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    viewModel.editGoals.insert(trimmed)
    newCustomGoal = ""
}
```

- [ ] **Step 3: Add customGoalChip helper**

Add a new helper that renders a custom goal chip with a remove (×) button:

```swift
private func customGoalChip(_ goal: String) -> some View {
    HStack(spacing: 4) {
        Text(goal)
            .font(.subheadline)
        Button(action: { viewModel.editGoals.remove(goal) }) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(AppTheme.accent)
    .foregroundStyle(.white)
    .clipShape(Capsule())
}
```

- [ ] **Step 4: Remove the old inline add logic from Button(action:) (now delegated to addCustomGoal())**

Ensure the `Button(action: addCustomGoal)` call is present (from Step 2). The old anonymous Button closure can be removed since we extracted `addCustomGoal()`.

- [ ] **Step 5: Commit**

```bash
git add Lightstack/Features/Profile/Views/EditProfileView.swift
git commit -m "fix: show custom goal chips after adding in Edit Profile"
```

---

## Task 7: Replace App Icon

**Files:**
- Replace: `Lightstack/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

### Problem
The app icon needs to be replaced with a new image provided at `/Users/muhammadnaseem/Downloads/IOS APP TEMP LOGO.png`.

### Fix Steps

- [ ] **Step 1: Check source image dimensions**

```bash
python3 -c "
from PIL import Image
img = Image.open('/Users/muhammadnaseem/Downloads/IOS APP TEMP LOGO.png')
print('Size:', img.size)
print('Mode:', img.mode)
"
```

- [ ] **Step 2: Resize to 1024×1024 and save as AppIcon.png**

```bash
python3 -c "
from PIL import Image
img = Image.open('/Users/muhammadnaseem/Downloads/IOS APP TEMP LOGO.png').convert('RGBA')
resized = img.resize((1024, 1024), Image.LANCZOS)
# Convert to RGB (App Store requires no alpha channel for app icons)
final = Image.new('RGB', (1024, 1024), (255, 255, 255))
final.paste(resized, mask=resized.split()[3] if resized.mode == 'RGBA' else None)
final.save('Lightstack/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png', 'PNG')
print('Saved.')
"
```

Run from `/Users/muhammadnaseem/IdeaProjects/LightStack/`.

- [ ] **Step 3: Verify**

```bash
python3 -c "
from PIL import Image
img = Image.open('Lightstack/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
print('Size:', img.size)
print('Mode:', img.mode)
"
```

Expected: `Size: (1024, 1024)`, `Mode: RGB`

- [ ] **Step 4: Commit**

```bash
git add Lightstack/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
git commit -m "feat: replace app icon with new logo"
```

---

## Verification Checklist

After all tasks:

- [ ] Build succeeds with zero compilation errors
- [ ] **Today Confirmation**: Exercise rows show weight/reps/RIR/rest detail; tapping × removes exercise from list
- [ ] **Today Sets**: All target set rows visible upfront as pending rows; delete (−) button removes a logged set; after logging a set the weight/reps pre-fill matches the last logged set (not AI target)
- [ ] **Today Keyboard**: Numeric fields show a "Done" button in the keyboard toolbar
- [ ] **Month Start Workout**: Tapping "Start This Workout" opens a full-screen sheet that generates and runs the workout inline (no tab switch); sheet auto-dismisses after save
- [ ] **History Filter**: Tapping a filter chip updates the workout list immediately
- [ ] **Profile Custom Goals**: Adding a custom goal via "+" shows it as a chip immediately; custom goal chips have × to remove them
- [ ] **App Icon**: New icon visible in Assets catalog
