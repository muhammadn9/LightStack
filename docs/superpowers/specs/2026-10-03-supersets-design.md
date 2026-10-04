# Supersets — Design

Approved by owner 2026-10-03.

## Goal

Log supersets properly. A superset is 2–4 exercises done back to back: one round is one set of each exercise. Each exercise keeps its own sets, PRs and "last time" hints.

## Model

- **`Exercise.supersetGroupId: UUID?`.** Exercises that share a group id form a superset. Members are ordered by `orderIndex` and must be adjacent. A group has 2–4 members. A group with only one member left is treated as no superset.
- **Core Data.** Add a **new model version** (`Lightstack 2.xcdatamodel`) with an optional `supersetGroupId` UUID attribute on `CDExercise`, and make it the current version. The existing version stays byte-for-byte unchanged, so the automatic lightweight migration can infer the mapping. Never edit the existing version in place: `LocalStorageService` calls `fatalError` when the store fails to load.
- **Supabase.** Add a nullable `exercises.superset_group_id uuid` column, recorded in `supabase/migrations/`.

## Active workout

- **One page per superset.** All members appear on one page, with the header showing "Superset · A + B (+ C…)". Rows are grouped by round: Round 1 has A's row then B's row, then Round 2, and so on. Each row keeps today's weight / reps / RIR fields and log button.
- **Rest timer.** It starts when the **last member's row in a round** is logged. Logging an earlier member's row starts no rest. The rest length is the group's longest `restSeconds`, or 90s if none is set.
- **Linking.** "Superset with next" in the exercise header links the current exercise (or group) with the next exercise. The group can't go over 4 members. "Unlink" splits the group back into separate exercises.
- **Add Set.** On a superset page this adds a round, meaning one row for each member.

## Safety (from the deleted-superset incident)

- Removing an exercise mid-workout asks for confirmation first. The long-press menu applies only to the exercise name, not the whole header.
- Finish no longer deletes stored exercises that have logged sets, even if they're missing from the in-memory list.

## Other surfaces

- **Coach / generation.** The generation and modification JSON gains an optional `"superset": "<label>"` per exercise. Exercises with the same label in one plan become one group. The prompt says to use it only when the user asks or it suits the goal, with a maximum of 4 per group.
- **History detail.** Grouped exercises appear together under a "Superset" label. Editing keeps the group: removing a member keeps the others grouped, unless only one is left.
- **Repeat last session.** Carries the groups over, with new group ids.
- **Import.**
  - The prompt describes supersets.
  - The parser accepts an exercise entry with an optional `"superset"` label.
  - It also accepts a combined name like "A x B" whose set entries are written "a / b". For example, "50 x 15 abt 2 rir / 50 x 10 abt 1 rir" becomes linked exercises A and B with one set each per round.
  - The prompt asks the AI to output the explicit form: separate exercises that share a `"superset"` label.

## Out of scope

- Giant sets with more than 4 members.
- Supersets for cardio.
