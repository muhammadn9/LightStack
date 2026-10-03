# Workout History Import — Implementation Plan

Spec: `docs/superpowers/specs/2026-10-02-history-import-design.md`

Order: Tasks 1 and 2 run in parallel, because they touch no common files. Task 3 runs after both. Subagents never commit or push. Never hand-edit `project.pbxproj`; run `xcodegen generate` after adding files.

Verify with:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lightstack.xcodeproj -scheme Lightstack -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' > /tmp/testN.log 2>&1; echo EXIT=$?; grep -E 'error:|Executed .* tests' /tmp/testN.log | tail -3`

---

## Task 1 — Unknown RIR app-wide

**Files:** `Core/Models/WorkoutSet.swift`, `Core/Services/WorkoutStatsService.swift`, `Features/Today/ViewModels/ActiveWorkoutViewModel.swift`, `Features/Today/ViewModels/TodayViewModel.swift`, `Features/Today/Views/ActiveWorkoutSetRows.swift`, `Features/Today/Views/SetRowView.swift`, `Features/AICoach/Services/CoachPromptService.swift`, `Features/AICoach/ViewModels/CoachChatViewModel.swift`, existing tests that break, `supabase/migrations/` (new file). All Swift paths are under `Lightstack/`.

1. **`WorkoutSet`.**
   - Change `var rir: Int` to `var rir: Int?`, and add `static let unknownRirStorage: Int32 = -1`.
   - Core Data read: `rir = cdEntity.rir < 0 ? nil : Int(cdEntity.rir)`.
   - Core Data write: `entity.rir = rir.map(Int32.init) ?? Self.unknownRirStorage`.
   - Codable: `decodeIfPresent` for reading, and `encode(rir, forKey:)`, which writes `null` for nil.
   - Change the factory and memberwise init parameter to `rir: Int?`.
2. **`PreviousSetHint.rir`** becomes `Int?`.
3. **`resolveStrength`** returns `rir: Int?`.
   - Blank RIR: use `previous?.rir` if there's a hint. With no hint, keep the default of 2.
   - A typed value from 0 to 10 is used as typed. A typed value above 10 becomes nil.
   - Unparseable text: use the hint's value if there is one, otherwise 2.
   - Update `RepeatSetResolutionTests`, and add tests for "11 → nil" and "blank with a nil-RIR hint → nil".
4. **Fallbacks.** Every place that turns a set's RIR into text or a default must handle nil:
   - Pending-row fallbacks such as `last.map { String($0.rir) }` use `$0.rir.map(String.init) ?? ""`.
   - In the `TodayViewModel` hint mapping, nil simply passes through.
5. **Display.**
   - `SetRowView` and `ActiveWorkoutSetRows` (the logged row and the RIR hint prompt) show "—" for nil, e.g. `"RIR —"`.
   - The accessibility label reads "RIR not recorded".
6. **Coach prompts** (`CoachPromptService` lines ~191 and ~274, and `CoachChatViewModel` ~127): when nil, write "RIR not recorded" instead of the number.
7. **`WorkoutStatsService`:** skip sets where `cdSet.rir < 0` in the RIR average.
8. **Migration file.** Add `supabase/migrations/sets_rir_nullable_up_to_10.sql` recording the change already applied to the live database:
   ```sql
   alter table public.sets alter column rir drop not null;
   alter table public.sets drop constraint sets_rir_check;
   alter table public.sets add constraint sets_rir_check check (rir is null or (rir between 0 and 10));
   ```
   Also update the `sets` table in `supabase/supabase_schema.sql` to match.
9. Fix every compile error the type change exposes. `grep -rn '\.rir\b' Lightstack LightstackTests` lists them.

## Task 2 — Import parser and prompt (TDD)

**Files:**
- New: `Lightstack/Features/History/Services/WorkoutImportParser.swift`
- New: `Lightstack/Features/History/Services/WorkoutImportPrompt.swift`
- New: `LightstackTests/WorkoutImportParserTests.swift`
- `Lightstack/Features/Today/Services/WorkoutSessionService.swift`, only to expose muscle-group inference.

Self-contained: do NOT reference `WorkoutSet`, `Workout` or `Exercise`, because Task 1 is changing `WorkoutSet` in parallel.

1. **Expose inference.** Turn `WorkoutSessionService.inferMuscleGroup(_:)` into `static func inferMuscleGroup(_:) -> String` (internal, not private). Update its one internal call site.
2. **Parser types:**
   ```swift
   struct ImportedSet: Equatable { let weightLbs: Double; let reps: Int; let rir: Int? }
   struct ImportedExercise: Equatable { let name: String; let muscleGroup: String; let notes: String?; let sets: [ImportedSet] }
   struct ImportedWorkout: Equatable { let date: Date; let name: String; let notes: String?; let exercises: [ImportedExercise] }
   enum ImportSkipReason: Equatable { case noDate(workoutName: String?), noExercises(workoutName: String?, date: Date?) }
   struct WorkoutImportParseResult: Equatable { let workouts: [ImportedWorkout]; let skipped: [ImportSkipReason] }
   enum WorkoutImportError: Error, Equatable { case noJSONFound, invalidJSON, noWorkouts }
   enum WorkoutImportParser { static func parse(_ text: String) throws -> WorkoutImportParseResult }
   ```
3. **Implementation.**
   - Decode with `JSONSerialization` into `[String: Any]` or `[Any]`, not `Codable`, so loose types are tolerated.
   - Strip code fences. Take the substring from the first `{` or `[` to the matching last `}` or `]`.
   - Accept `{"workouts": [...]}` or a top-level array.
   - Apply the parsing rules table in the spec exactly:
     - Unknown values are `N/A`, empty, `null` or a missing key, case-insensitive.
     - Numbers come from a leading-number regex on strings.
     - A RIR range takes the lower number. RIR above 10 or negative becomes nil.
     - Dates are `yyyy-MM-dd` in the current calendar at local noon, or ISO 8601.
   - If the JSON yields zero importable and zero skipped workouts, throw `noWorkouts`.
   - The parser does not deduplicate; Task 3 does that.
4. **`WorkoutImportPrompt.text`** is a static multi-line string. It instructs the AI to:
   - Read the user's workout records, which the user pastes after the prompt.
   - Output ONLY JSON in the spec's format.
   - Write one entry per workout day, with dates as YYYY-MM-DD.
   - Name each workout from its exercises, e.g. "Push", "Pull", "Legs", "Upper Body".
   - Give each exercise a muscle group (Chest, Back, Shoulders, Arms, Legs, Core).
   - Convert kg to lbs.
   - Use "N/A" for anything not recorded.
   - Keep RIR ranges as written, e.g. "1-2".
   - Include user notes per exercise or per workout, else "N/A".
   - Not invent data.

   End the prompt with "My workout records:" followed by a blank line.
5. **Tests**, at least one per spec table row, plus:
   - Fenced JSON, surrounding prose, and a top-level array.
   - `"135 lbs"` as a string.
   - RIR `"2-3"` gives 2. `"N/A"` gives nil. `"12"` gives nil.
   - A missing name gives "Imported Workout".
   - A set without reps is skipped, and an exercise whose sets are all skipped is skipped.
   - A workout whose exercises are all skipped is reported as `noExercises`.
   - Garbage text throws `noJSONFound`.
   - The prompt contains "N/A" and "YYYY-MM-DD".

## Task 3 — Import service, saving and UI

Depends on Tasks 1 and 2.

**Files:**
- New: `Lightstack/Features/History/Services/WorkoutImportService.swift`
- New: `Lightstack/Features/History/Views/WorkoutImportView.swift`
- New: `LightstackTests/WorkoutImportDedupeTests.swift`
- `Lightstack/Core/Repositories/WorkoutRepository.swift`
- `Lightstack/Features/History/Views/HistoryListView.swift`
- `Lightstack/Features/History/ViewModels/HistoryViewModel.swift`
- The `AppEnvironment` factory, if one is needed to build the service.

1. **`WorkoutRepository.importWorkout(_ workout: Workout, exercises: [Exercise], sets: [UUID: [WorkoutSet]])`.**
   - Save everything locally first, using the existing `localStorage` calls.
   - Then start ONE `Task` that awaits `supabaseService.insertWorkout`, then `insertExercises`, then `insertSet` for each set, in that order. On the first failure, enqueue the remaining items to `offlineQueueManager`, in the same order and with the same enqueue kinds the existing methods use.
2. **`WorkoutImportService`** takes `workoutRepository`, `prRepository` and `userId`.
   - **`static func dedupe(_ incoming: [ImportedWorkout], existing: [(date: Date, name: String)]) -> (toImport: [ImportedWorkout], duplicates: Int)`** is pure and unit tested.
     - A workout is a duplicate when it's on the same calendar day as an existing workout, with the same trimmed, case-insensitive name.
     - This also removes duplicates within `incoming`; the first one wins.
   - **`func preview(_ result: WorkoutImportParseResult) -> ImportPreview`** returns `toImport`, `duplicateCount` and `skipped`. Existing workouts come from `fetchRecentWorkouts(limit: 10_000)`.
   - **`func importWorkouts(_ workouts: [ImportedWorkout])`**, for each workout:
     - Build a `Workout` through the memberwise init with `date` set to the imported date, `workoutType` to the name and `userNote` to the notes. The other fields are as in `Workout.create`, with `durationMinutes` nil.
     - Build `Exercise.create` with the imported name and muscle group, `orderIndex`, `targetSets` equal to the number of sets, and `coachNote` equal to the exercise notes.
     - Build each `WorkoutSet` through the memberwise init with `setNumber` counting from 1, `recordedAt` set to the workout date, and `isPR` false.
     - Call `repository.importWorkout`. Then call `prRepository.recalculatePR(userId:exerciseName:)` once for each distinct exercise name.
3. **`WorkoutImportView`**, a sheet with a `NavigationStack`, AppTheme styling and `lsCard()` sections:
   - **Step 1.** Explains "Copy this prompt into ChatGPT, Gemini, Claude or any AI, then paste your workout notes after it." A **Copy Prompt** button writes to `UIPasteboard.general.string`, briefly shows "Copied ✓", and gives `.sensoryFeedback(.success)`.
   - **Step 2.** A `TextEditor` (min height ~180) and a **Paste** button that reads `UIPasteboard`.
   - **Step 3.** A **Check** button runs `WorkoutImportParser.parse` then `service.preview`.
     - On success, show the summary line "N workouts ready · D already in History · S skipped" and list the skip reasons (e.g. "Workout on Sep 14: no exercises", "Pull: no date").
     - On error, show a friendly message: "Couldn't find workout data — make sure you pasted the AI's whole reply."
   - **Import N workouts** is shown only when N > 0. It calls `importWorkouts`, then `onImported()`, then dismisses.
   - The Cancel toolbar button dismisses.
4. **`HistoryListView`.** Add a toolbar button (`square.and.arrow.down`, accessibilityLabel "Import workouts") that presents `WorkoutImportView`. Also add an "Import past workouts" button in the empty state. `onImported` calls `viewModel.loadWorkouts(userId:)`.
5. **Tests** for `dedupe`:
   - Same day and same name in a different case is a duplicate.
   - A different day is not.
   - A different name is not.
   - Duplicates within the batch are collapsed.
