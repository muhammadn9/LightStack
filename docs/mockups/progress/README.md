# Progress tab redesign: mockups

Each concept shows dark and light side by side (iPhone 17 Pro, 402x874pt, AppTheme colors). Sample numbers are invented.

Today's tab (`ProgressTabView`, `ProgressStatsService`): Overview/Lifts/Equipment segments, streak and weekly stat cards, 13-week heatmap, top-3 lift e1RM sparklines, month-vs-last best set, equipment sets.

**Concept A: Dashboard (`concept-a`).** Keeps the Overview segment but leads with four key-lift e1RM sparklines (with deltas), a headline row (streak, days this week, PRs in 30 days) and a new weekly-volume bar chart. Why: the closest evolution of today's screen, so it carries the least risk and answers "am I getting stronger and doing enough work?". Data: `ProgressSnapshot.lifts`/`streak` already exist; volume is sum(weight x reps) over `CDWorkoutSet`; PR count from `CDPersonalRecord`. Effort: S-M.

**Concept B: Per-exercise drill-down (`concept-b`).** An exercise chip row sits above one large e1RM chart with range toggles (4W/12W/6M/1Y/All), best set, session and set counts, and a PR timeline. Why: lifters mostly ask about one lift at a time, and the current 8-week sparkline is too short to show a real trend. Data: `CDWorkoutSet` grouped by exercise name (e1RM already computed in `liftTrends`), PR timeline from `CDPersonalRecord` (weight, reps, dateAchieved). Effort: M-L (new per-exercise query with longer windows, Swift Charts, picker state).

**Concept C: Balance and consistency (`concept-c`).** A streak/week-completion header, sets per muscle group over 4 weeks with a "neglected group" nudge into Coach, and the 13-week training-day heatmap. Why: it fits the app's AI-coach angle (coach can act on imbalances) and rewards showing up. Data: `CDExercise.muscleGroup` joined to `CDWorkoutSet`; streak/heatmap already exist; "best streak" and the planned-day marker need `CDPlannedSession`. Effort: M.

## Recommendation

Build **A first** (low risk, mostly existing data), then add **B as the destination of tapping a lift** in A (this replaces the Lifts segment). Fold C's muscle-balance card into the Equipment segment or A later. Together these give a dashboard on top and drill-down below.

## Data gaps

- No volume aggregate today; needs a new computation (cheap, from sets). Bodyweight/duration exercises and `isPerArm` need a volume rule.
- e1RM history is capped at 8 weeks (`liftTrends`); B needs a longer window and per-exercise query.
- `CDPersonalRecord` stores weight/reps only, with no e1RM or PR type (rep PR vs e1RM PR); the timeline would show whichever was saved.
- `muscleGroup` is a free String set by AI/user, so values need normalizing into ~6 groups. Core/finisher exercises may be inconsistently labeled.
- "Best streak" is not stored; derive from `workoutDays` and `restDays`.
- No bodyweight log (only the profile's single `weightLbs`), so no bodyweight trend.
- Unknown RIR is stored as -1, so any effort/RIR view must exclude it.
