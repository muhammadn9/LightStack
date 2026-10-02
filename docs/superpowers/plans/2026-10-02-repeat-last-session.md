# Repeat Last Session — Implementation Plan

Spec: `docs/superpowers/specs/2026-10-02-repeat-last-session-design.md`

Order: Task 1 first. Tasks 2 and 3 then run in parallel, because they touch no common files. Subagents never commit or push.

Verify with:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' > /tmp/test.log 2>&1; echo EXIT=$?; grep -E 'error:|Executed .* tests' /tmp/test.log | tail -3`

---

## Task 1 — Set resolution rules (TDD)

**Files:** `Lightstack/Features/Today/ViewModels/ActiveWorkoutViewModel.swift`, new file `LightstackTests/RepeatSetResolutionTests.swift`. Run `xcodegen generate` after adding the test file.

1. Add a hint type next to `PendingSetInput`:
   ```swift
   /// Last session's numbers for one set, shown as grey hints in a repeat session.
   struct PreviousSetHint: Codable, Equatable {
       let weightLbs: Double   // 0 = bodyweight
       let reps: Int
       let rir: Int
   }
   ```
   Then add `var previous: PreviousSetHint? = nil` to `PendingSetInput`.

2. Add a pure, testable static function on `ActiveWorkoutViewModel`:
   ```swift
   /// Resolves a strength entry to concrete values. Blank fields fall back to
   /// `previous` when present. Returns nil when the entry is not loggable.
   static func resolveStrength(weight: String, reps: String, rir: String,
                               previous: PreviousSetHint?) -> (weight: Double, reps: Int, rir: Int)?
   ```
   Rules, after trimming whitespace:
   - **Weight.** If blank and there's a hint, use `previous.weightLbs`. If blank with no hint, or `BW` (any case), or `0`, use `0`. Any other number ≥ 0 is used as typed. Anything else returns nil.
   - **Reps.** If blank and there's a hint, use `previous.reps`. If blank with no hint, return nil. Any integer ≥ 0 is used as typed, including 0. Anything else returns nil.
   - **RIR.** If blank and there's a hint, use `previous.rir`. If blank with no hint, use 2, which is today's default. Any integer ≥ 0 is used as typed. If it's unparseable, use the hint's value if there is one, otherwise 2.

3. Replace the strength branch of `logPendingSet` with a call to `resolveStrength(…, previous: entry.previous)`.

4. Add `@Published var previousHints: [UUID: [PreviousSetHint]] = [:]`, keyed by exercise id. Then update two functions:
   - **`syncPendingSets`:** for strength exercises with hints, the needed count is `max(targetSets, hints.count) - loggedCount`. Each appended row at overall position `p`, where `p = loggedCount + current.count`, gets `PendingSetInput(weight: "", reps: "", rir: "", previous: hints[safe p])`. If there's no hint at that position, use today's prefill logic. Exercises without hints keep today's behaviour.
   - **`refreshTargets`:** keep the `previous` value on rows that already have one, and skip overwriting their text. The coach can't modify a repeat session before it starts, but rows must not lose their hints.

5. Tests in `RepeatSetResolutionTests`:
   - All fields blank with a hint resolves to the hint's values.
   - Typed values override the hint.
   - `0` weight resolves to 0, both with and without a hint. `BW` resolves to 0.
   - `0` reps resolves to 0 reps.
   - Blank reps with no hint resolves to nil.
   - Blank RIR with no hint resolves to 2.
   - Garbage weight resolves to nil.
   - `syncPendingSets` with 3 hints and `targetSets` of 2 produces 3 rows with blank text and hints at positions 0, 1 and 2.

## Task 2 — Load the last session (TodayViewModel + setup button)

**Files:** `Lightstack/Features/Today/ViewModels/TodayViewModel.swift`, `Lightstack/Features/Today/Services/WorkoutSessionPersistence.swift`, `Lightstack/Features/Today/Views/WorkoutSetupView.swift`, `Lightstack/Features/Today/Views/ActiveWorkoutView.swift`. This task depends on Task 1's `PreviousSetHint` and `previousHints`.

1. In `TodayViewModel`, add:
   - `@Published var previousHints: [UUID: [PreviousSetHint]] = [:]`.
   - `func lastSession(ofType type: String) -> Workout?`. It uses `workoutRepository.fetchRecentWorkouts(userId:limit: 60)`, excludes `sessionService.currentWorkoutId`, matches `workoutType` trimmed and case-insensitive, and requires at least one logged set (check with `fetchExercises` and `fetchSets`). It returns the most recent match.
   - `func repeatLastSession(ofType type: String)`. It loads the source exercises, sorted by `orderIndex`, and their sets, sorted by `setNumber`. It builds new exercises through `Exercise.create`, the same way as `loadExistingWorkout`, with these values:
     - `targetSets` is the logged count if it's above 0, otherwise the source `targetSets`.
     - `targetReps` is the first logged set's reps as a string, falling back to the source value.
     - `targetRir` is copied from the source.
     - `coachNote` is `"Target: {weight} lbs"` from the first logged set, or `"Target: BW"` if that weight is 0, or nil if there are no logged sets.

     For strength exercises, it sets `previousHints[newExercise.id]` from the logged sets. It then creates the workout and starts the session the same way `loadExistingWorkout` does, and sets `phase = .confirmation`.
   - When the session resets to setup, clear `previousHints`.

2. **Persistence.** Add `let previousHints: [UUID: [PreviousSetHint]]?` to `SessionState`. It must be optional so older saved sessions still decode. Pass it through `saveSession` and `saveSessionState`, and restore it in `restoreSessionState`.

3. **PR guard.** In `TodayViewModel.logSet`, skip the PR check when `workoutSet.reps == 0`.

4. **`ActiveWorkoutView`.** In `.onAppear`, before the `prefillTargets` loop, set `viewModel.previousHints = todayViewModel.previousHints`.

5. **`WorkoutSetupView`.** Below the "Log Manually" button, add a secondary `WaxSealButtonStyle(isSecondary: true)` button. It shows only when `viewModel.selectedWorkoutType` is non-empty and `viewModel.lastSession(ofType:)` returns a workout. Its label is `"Repeat last \(type) · \(date formatted .abbreviated month + day)"`, and its action is `viewModel.repeatLastSession(ofType:)`. Compute the session once per selection change, for example with `@State` and `.onChange(of: viewModel.selectedWorkoutType)`, not on every redraw. Add an `accessibilityHint` of "Starts with the same exercises as last time, no AI coaching".

## Task 3 — Grey hint UI on set rows

**File:** `Lightstack/Features/Today/Views/ActiveWorkoutSetRows.swift` (`StrengthPendingSetRow` only). This task depends on Task 1's `previous` field.

1. Let `hint = pendingSets[index].previous`. For each of the weight, reps and RIR `TextField`s, use the `prompt:` initializer:
   - The prompt text is the hint's value. Weight shows `"BW"` when it's 0, otherwise `%g`. Reps and RIR show their numbers.
   - With no hint, keep the current prompts: "lbs", "reps" and "RIR".
   - Style the prompt with `.foregroundStyle(AppTheme.textSecondary.opacity(0.6))`.
2. The log button's enabled and filled state is `!reps.isEmpty || hint != nil`. Replace all three `pendingSets[index].reps.isEmpty` checks on the button with a computed `canLog`.
3. When a hint exists, give each field an accessibility label that includes it, for example "Weight, last time 135".
