# Supersets — Implementation Plan

Spec: `docs/superpowers/specs/2026-10-03-supersets-design.md`

Order: Task 1 first. Tasks 2 and 3 then run in parallel, because they touch no common files. Subagents never commit or push. Run `xcodegen generate` after adding files.

## Task 1 — Model and migration (foundation)

1. **Core Data:**
   - Create `Lightstack/Lightstack.xcdatamodeld/Lightstack 2.xcdatamodel/contents` as a copy of the current model, plus an optional UUID attribute `supersetGroupId` on `CDExercise`.
   - Set `.xccurrentversion` to `Lightstack 2.xcdatamodel`.
   - Do NOT modify `Lightstack.xcdatamodel`.
   - Make sure XcodeGen picks up the versioned model, and check the generated project.
2. **`Exercise`:**
   - Add `supersetGroupId: UUID?`.
   - Thread it through Core Data read/write, Codable as `superset_group_id` via `decodeIfPresent`, `toSupabase`, `Exercise.create` (defaulted parameter) and the memberwise init.
3. **Migration test:** an XCTest that does the following.
   - Loads the **version 1** model from the compiled bundle: `Lightstack.momd/Lightstack.mom`. Version 2 compiles as `Lightstack 2.mom`.
   - Creates a SQLite store at a temp URL with that model and inserts a workout, an exercise and a set.
   - Closes it, then opens the same URL with an `NSPersistentContainer` that uses the current model and `shouldMigrateStoreAutomatically` / `shouldInferMappingModelAutomatically`.
   - Asserts the store loads with no error, the data is intact and `supersetGroupId` is nil.
4. **Superset helpers**, pure and tested:
   - `SupersetGroup` utilities over `[Exercise]`: group adjacent members into a page model, validate 2–4 members, and dissolve a single-member group.
   - `link(current:withNext:)` and `unlink(groupId:)`, which return the updated exercises.

## Task 2 — Active workout, coach and safety

**Files:**
- `ActiveWorkoutView`, `ExerciseHeaderView`, `ActiveWorkoutSetRows`
- `ActiveWorkoutViewModel`, `TodayViewModel`, `WorkoutSessionService`
- the coach JSON parser and prompt files
- `ConfirmWorkoutView`

**Work:**
- **Pages:** one page per exercise, or one page per superset group.
- **Round rows:** rows interleave members round by round. Add Set adds a round.
- **Rest:** rest starts only after the last member's row in a round is logged, using the longest rest in the group or 90s.
- **Header:** "Superset with next" and "Unlink" in the header, persisted through `workoutRepository.saveExercises`, which is an upsert.
- **AI:** generation and modification support an optional `"superset"` label.
- **Repeat last session:** carries groups over with fresh ids.
- **Confirm-before-remove:** the long-press menu applies only to the exercise name.
- **Finish reconcile:** never delete stored exercises that have logged sets.
- **Tests:** page grouping, round-row ordering, when rest triggers, the label → group mapping, and the reconcile guard.

## Task 3 — History, edit and import

**Files:** `WorkoutDetailView`, `WorkoutEditForm`, `WorkoutEditDraft`, `WorkoutImportParser`, `WorkoutImportPrompt`, `WorkoutImportService`, `HistoryViewModel`.

**Work:**
- **Detail view:** group members under a "Superset" label.
- **Edit draft:** keep the group id. Removing members dissolves the group if only one is left.
- **Import, explicit form:** a `"superset"` label groups exercises into one group.
- **Import, combined form:** the parser splits a combined "A x B" name, but only when the set entries contain " / " splitting into the same number of parts. Otherwise the name is kept as one exercise.
- **Prompt:** asks for the explicit form, gives an example, and allows at most 4 exercises per group.
- **Tests:** both import forms, the edit-draft group rules, and grouping in the detail view if it's extracted as a function.
