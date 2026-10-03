# Edit Past Workouts — Implementation Plan

Spec: `docs/superpowers/specs/2026-10-03-edit-past-workouts-design.md`

Order: Tasks 1 and 2 run in parallel, because they touch no common files. Task 3 runs after both. Subagents never commit or push, never change the Core Data model, and run `xcodegen generate` after adding files.

Verify with:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' > /tmp/testN.log 2>&1; echo EXIT=$?; grep -E 'error:|Executed .* tests' /tmp/testN.log | tail -3`

## Task 1 — Data layer

**Files:** `Core/Services/SupabaseService.swift`, `Core/Utilities/OfflineQueueManager.swift`, `Core/Repositories/WorkoutRepository.swift`, `Core/Services/LocalStorageService.swift` (only if a helper is needed), and a new `LightstackTests/WorkoutReplaceTests.swift`.

1. **`SupabaseService.deleteExercise(id:)`.** Follow the style of `deleteWorkout` and `deleteExercises(workoutId:)`, which already exists.
2. **Offline queue.** Add two kinds, `deleteExercise` and `deleteExercises`:
   - Handle both in `execute` the same way `deleteSet` and `deleteWorkout` are handled.
   - The `deleteExercises` payload carries the workout id. Use a small Codable struct or the `Workout`, whichever matches the existing patterns.
   - Make sure the processing order keeps deletes from running before the inserts they depend on. If the queue sorts by kind, check that a replace (update, then deleteExercises, then insertExercises, then insertSet) queued in that order still replays correctly. If sorting would break it, process those kinds in FIFO order and explain why.
3. **`WorkoutRepository.deleteExercise(_:)`.** Keep the local delete, and add the Supabase delete with an offline fallback.
4. **`WorkoutRepository.replaceWorkoutContents(_ workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]])`.**
   - **Local:** `updateWorkout` (the local part), then `deleteExercises(workoutId:)`, then save the exercises and sets.
   - **Remote:** one `Task` that runs `updateWorkout`, then `deleteExercises`, then `insertExercises`, then `insertSet` for each set. On the first failure, enqueue that step and every later step, in order. Use the same pattern as `importWorkout`.
5. **Tests:** use the in-memory `LocalStorageService(inMemory: true)` from `PRRecalculationTests`. Check that after a replace, the local store holds exactly the new exercises and sets for that workout, and that other workouts are untouched.

## Task 2 — Edit draft model (TDD)

**Files:** new `Lightstack/Features/History/Models/WorkoutEditDraft.swift` and new `LightstackTests/WorkoutEditDraftTests.swift`. This task is pure Swift and must not call repositories or services.

1. **Types.**
   - `struct WorkoutEditDraft { var name: String; var date: Date; var notes: String; var exercises: [DraftExercise] }`
   - `DraftExercise` has an `id`, a `name`, a `muscleGroup` and `var sets: [DraftSet]`.
   - `DraftSet` has an `id` and string fields `weight`, `reps` and `rir`.
2. **`init(workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]])`.**
   - Order exercises by `orderIndex` and sets by `setNumber`.
   - Format weight 0 as `"BW"`, other weights with `%g`, and a nil RIR as `""`.
3. **Mutations:** `addSet(to:)` copies the last set's text, or uses empty strings if the exercise has no sets. Also add `removeSet`, `addExercise(name:muscleGroup:)` (which starts with one empty set) and `removeExercise`.
4. **`func validate() -> [DraftFieldError]`.** Each error identifies the exercise id, the set id and the field. Apply the spec's validation table.
5. **`func build(for original: Workout) -> (workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]])?`.**
   - Return nil if `validate()` isn't empty.
   - Drop exercises that have no sets.
   - Copy the original workout, replacing `workoutType` (a blank name becomes "Workout"), `date` and `userNote` (blank becomes nil).
   - Give exercises and sets fresh ids. Set `orderIndex` by position, `targetSets` to the set count, and `setNumber` counting from 1.
   - Set `recordedAt` to the workout date and `isPR` to false.
6. **`var isEmpty: Bool`** is true when no exercise has any sets. Task 3 uses it to trigger the delete-workout confirmation.
7. **Tests** cover the round trip, each validation rule, dropping empty exercises, add and remove for sets and exercises, BW formatting, and a nil RIR.

## Task 3 — Edit UI and save

Depends on Tasks 1 and 2.

**Files:** `Features/History/Views/WorkoutDetailView.swift`, `Features/History/ViewModels/HistoryViewModel.swift`, and new view files if the detail view gets too big, e.g. `WorkoutEditForm.swift`.

1. **`HistoryViewModel.saveEdits(original: Workout, draft: WorkoutEditDraft, userId: UUID) -> Workout?`.**
   - Calls `draft.build`, then `workoutRepository.replaceWorkoutContents`.
   - Recalculates PRs with `prRepository.recalculatePR` for the union of the old exercise names (fetch them before replacing) and the new ones.
   - Reloads workouts and returns the updated workout.
   - If the draft `isEmpty`, the view handles it by confirming and then calling the existing `deleteWorkout`.
2. **`WorkoutDetailView`:**
   - Hold the displayed workout in `@State` so it refreshes after a save.
   - Add an Edit toolbar button. It is hidden when this workout is the in-progress session. Detect that through the environment or the saved session (check `WorkoutSessionPersistence` and `AppEnvironment` for the cleanest way).
   - In edit mode, show the form described in the spec using `AppTheme`, `lsCard` and the existing input styles.
   - Field errors are highlighted with `AppTheme.warning`.
   - Cancel and Save replace the toolbar while editing.
   - Use `ExerciseCatalogPicker` for adding exercises.
   - Make sure VoiceOver labels are present and Dynamic Type works.
3. Hide or disable the repeat button while editing.
