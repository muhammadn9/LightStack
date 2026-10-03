# Workout History Import — Design

Approved by owner 2026-10-02.

## Goal

Let users bring past workouts into History. The app gives them a prompt to copy into any AI along with their own records. The AI returns JSON, which the user pastes back into the app. The app validates it, shows a summary, and imports on confirmation. The app makes no AI call of its own.

## Entry point and flow

An **Import** button (`square.and.arrow.down`) in the History tab's top bar opens a sheet with three steps:

1. **Copy prompt.** Copies `WorkoutImportPrompt.text` to the clipboard and confirms with "Copied".
2. **Paste.** A text editor plus a **Paste** button.
3. **Check.** Parses the pasted text and shows a summary, e.g. "14 workouts ready · 2 already in History · 1 skipped (no date)", with a short list of skip reasons. **Import N workouts** saves. Nothing is saved before this tap.

The empty History state also shows the Import button.

## JSON format, which the prompt asks for

```json
{"workouts": [
  {"date": "2026-09-14", "name": "Pull", "notes": "N/A",
   "exercises": [
     {"name": "Barbell Row", "muscle_group": "Back", "notes": "N/A",
      "sets": [{"weight_lbs": 135, "reps": 8, "rir": "1-2"}]}
   ]}
]}
```

The prompt tells the AI to:
- Name each workout from its exercises.
- Convert kg to lbs.
- Write "N/A" for anything not recorded.
- Keep RIR ranges as written.
- Output only the JSON.

## Parsing rules

- **Extracting the JSON.** Code fences and any text around the outermost JSON object are ignored. A top-level array of workouts is also accepted.
- **Unknown values.** `"N/A"`, `""`, `null` and a missing key are all treated as unknown, case-insensitive.
- **Numbers.** Numbers may arrive as numbers or strings, e.g. `135`, `"135"` or `"135 lbs"`. The leading number is used.

| Situation | Result |
|---|---|
| Date unknown or unparseable | Workout skipped ("no date"). Accepts `yyyy-MM-dd` or ISO 8601. |
| No usable exercises | Workout skipped ("no exercises"). |
| Workout name unknown | "Imported Workout". |
| Exercise name unknown | Exercise skipped. |
| Muscle group unknown | Inferred from the exercise name, using the app's existing inference. |
| Weight unknown | 0, meaning bodyweight. |
| Reps unknown or unparseable | Set skipped. |
| RIR unknown | Unknown (nil). |
| RIR range like "1-2" | Lower number. |
| RIR above 10 or negative | Unknown (nil). |
| Notes unknown | nil. |

## Duplicates

An imported workout is skipped if History already has a workout on the same calendar day with the same name (trimmed, case-insensitive). The same rule removes duplicates within the pasted batch itself.

## Saving

Each workout is saved locally and synced the same way as a normal session. Its `date` and each set's `recordedAt` are set to the imported date. Supabase inserts for one workout run in order (workout, then exercises, then sets) so foreign keys never fail; failures go to the existing offline queue. After the import, PRs are recalculated for every imported exercise name and History reloads.

## Unknown RIR, app-wide

- **Swift model.** `WorkoutSet.rir` becomes `Int?`.
- **Supabase.** Sends `null`. The `sets.rir` column has already been changed to allow NULL and values 0–10, and this change is recorded in `supabase/migrations/`.
- **Core Data.** `rir` stays a non-optional Int32. `-1` means unknown, and the conversion lives only in `WorkoutSet`'s Core Data mapping. This avoids a model migration; the store loader treats a failed load as fatal.
- **Display.** Unknown shows as "—".
- **Coach context.** Unknown RIR is omitted or written as "RIR not recorded".
- **Stats.** RIR averages skip unknowns.
- **Repeat hints.** An unknown RIR in a hint shows "—", and leaving the field blank keeps it unknown.
- **Typing in the app.** A typed RIR above 10 is treated as unknown.

## Out of scope

- Storing RIR ranges exactly; the lower number is used.
- Exporting data.
- Cardio import.
