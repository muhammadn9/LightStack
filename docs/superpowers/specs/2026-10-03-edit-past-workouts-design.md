# Edit Past Workouts — Design

Approved by owner 2026-10-03.

## Goal

Let the user edit any finished workout from History: its name, date and notes; set weight, reps and RIR; adding and removing sets; adding and removing exercises.

The same PR closes a sync gap. Exercises removed mid-workout are currently deleted only on the phone. After this change they are deleted from the Supabase backup too.

## Behaviour

**Edit mode.** `WorkoutDetailView` gets an **Edit** button in the toolbar, which turns the screen into a form:

- **Workout details:** the name is a text field, the date uses a `DatePicker` (date only), and the notes field edits `userNote`.
- **Sets:** each set has weight, reps and RIR text fields and a delete button. Each exercise has an **Add Set** button. A new set is pre-filled from the exercise's last set.
- **Exercises:** each exercise has a remove button. **Add Exercise** opens `ExerciseCatalogPicker`, and the new exercise starts with one empty set.
- **Cancel / Save.** Cancel throws away every change. Save applies them all at once. Nothing touches storage until Save.

**Validation on Save.** These rules match live logging:

| Field | Rule |
|---|---|
| Weight | Blank, `BW` or `0` means bodyweight (0). Otherwise it must be a number of 0 or more. |
| Reps | Required, and must be an integer of 0 or more. 0 means unable. |
| RIR | Blank means unknown (nil). Otherwise it must be an integer from 0 to 10. |
| Name | Blank becomes "Workout". |

- A set with invalid input blocks Save, and the field is highlighted.
- An exercise with no sets left is dropped on Save.
- If no exercises remain, Save asks "Delete this workout?". Confirming uses the existing History delete path.

**In-progress workout.** The workout that is currently active on the Today tab cannot be edited, so it shows no Edit button.

## Save mechanics

The approach is replace, not diff.

- **Phone:** delete the workout's exercises, which removes their sets by cascade. Then save the edited exercises and sets with fresh ids, and update the workout row.
- **Supabase**, one ordered task: `updateWorkout`, then `deleteExercises(workoutId)` (sets are removed by FK cascade), then `insertExercises`, then `insertSet` for each set.
  - On the first failure, that step and every later step go to the offline queue in the same order.
  - This needs a new `deleteExercises` offline operation kind.
- **PRs:** recalculated for the union of exercise names from before and after the edit.
- **Refresh:** History reloads, and the detail screen shows the saved version.

## Cloud gap fix

`WorkoutRepository.deleteExercise` also deletes the exercise in Supabase, using a new `SupabaseService.deleteExercise(id:)` and a new `deleteExercise` offline kind. Sets are removed by FK cascade.
