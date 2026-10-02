# Repeat Last Session — Design

Approved by owner 2026-10-02.

## Goal

From the Today setup screen, start a workout that copies your most recent session of the same type, with no AI step. Last session's numbers appear as grey hints, and a blank field means "same as last time".

## Behaviour

**Entry point.** On `WorkoutSetupView`, once a workout type chip is selected and a previous session of that type exists, a third button appears below "Log Manually": **"Repeat last {Type} · {MMM d}"**.

**"Previous session"** is the most recent workout whose `workoutType` matches the selected type (case-insensitive, trimmed) and that has at least one logged set. The in-progress workout is excluded.

**What loads.** The same exercises in the same order. For strength exercises, the set count is the number of sets actually logged last time, falling back to `targetSets` if none were logged. The flow goes straight to the confirmation phase, the same as History's repeat, and never calls the AI.

**Hints.** Each pending strength set N carries last session's set N (weight, reps, RIR). Its fields start **empty** and show those values as grey placeholder text.

**Logging rules for a set that has a hint:**

| Field  | Blank            | Typed value                                  |
|--------|------------------|----------------------------------------------|
| Weight | last time's weight | number; `0` or `BW` means bodyweight        |
| Reps   | last time's reps   | number; `0` means unable, saved as 0 reps   |
| RIR    | last time's RIR    | number; `0` means failure                   |

The log button is enabled when reps is filled in or the set has a hint.

**Sets without a hint** (an added set beyond last time's count, cardio, or non-repeat sessions) keep today's behaviour, with two general fixes that apply everywhere:
- Typed weight `0` means bodyweight. Today it is rejected.
- Typed reps `0` is accepted and saved as a 0-rep set ("unable").

**PRs.** A 0-rep set is never a PR.

**Persistence.** Hints are saved with the session state, so they survive an app restart mid-workout.

**Cardio.** Cardio exercises are copied, but their set rows get no hints.

## Out of scope

- The workout history import, which gets a separate spec.
- A repeat button on the History list.
