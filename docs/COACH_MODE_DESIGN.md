# Coach Mode — Design (draft for owner review)

Status: proposal. No code written. "Coach mode" is not yet defined, so this lists interpretations, recommends one and designs it.

## 1. Interpretations

| # | Interpretation | Builds on | Cost / risk |
|---|---|---|---|
| A | **Guided session**: a focused in-workout mode where the coach drives each set (target, cue, rest, next-set adjustment), hands-free capable | `ProgressionEngine`, `InSessionAdjuster`, rest timer, Live Activity | Mostly on-device and deterministic; ~0 extra AI calls |
| B | **Program / periodisation**: multi-week blocks, auto deloads, mesocycle review | `MonthPlan`, `PlanGuardrails`, `CoachReviewDocument` | Needs new data model, heavy AI plan calls, validation of long plans |
| C | **Trainer-client sharing**: a human trainer sees and edits a client's plan and logs | Supabase RLS | Needs roles, invites, privacy, moderation; biggest scope |

**Recommendation: A (Guided Session), then feed B later.** It uses what Coach v2 already computes, works offline, and fits the Gemini free tier (10/min, 100/day via `check_rate_limit`) because per-set guidance comes from the deterministic engine, not the model. B reuses A's per-session signals (adherence, fatigue); C is a separate product decision.

## 2. Guided Session: what it is

A toggle on the Today tab ("Start with Coach") that opens a full-screen, one-set-at-a-time view. The coach shows the exact target for the current set (from `ProgressionEngine` set targets), the athlete logs it in two taps, rest runs automatically, and the next target is adjusted by `InSessionAdjuster` if they missed. Normal list logging stays available; guided mode is a different presentation of the same `ActiveWorkoutViewModel` state, not a second workout engine.

## 3. User flows

1. **Start**: Today -> "Start with Coach" (or setting "Always guide me"). Pre-flight card: today's plan, estimated time, equipment check. Existing plan generation is unchanged.
2. **Set loop**: Set card (exercise, set N of M, target weight x reps @RIR, last-time reference, one cue line) -> athlete taps "Done as planned" (logs target) or adjusts weight/reps/RIR with steppers -> RIR picker (skippable, stores nil as today) -> rest screen.
3. **Rest**: countdown (rest from `ProgressionEngine`/`RestPreference`), preview of the next set, coach line ("Last set felt hard, dropping 5 lb"). Skip/extend buttons. Live Activity already advances to the next set when rest ends; guided mode reuses that.
4. **Miss handling**: shortfall >= `InSessionAdjuster.repShortfall` shows the existing banner inline as a single "Lower remaining sets?" prompt; accept updates the pending set targets.
5. **Exercise swap / skip**: bottom sheet reusing the existing chat modification path (`LocalChatCommandParser` first, AI second).
6. **Finish**: hands off to existing `PostWorkoutView` and the one post-workout AI call. Optional adherence line: "You hit 14 of 16 planned sets."
7. **Interrupt/resume**: leaving the app or killing it resumes on the same set (session persistence already exists in Today).

Optional voice cues (phase 3): `AVSpeechSynthesizer` reads target and rest end; no speech recognition in v1.

## 4. Screens

- `GuidedSessionView` (container, full-screen cover via `fullScreenCover(item:)`).
- `GuidedSetCard`, `GuidedRestView`, `GuidedSummaryStrip` (progress dots per exercise).
- `CoachModeSettingsSection` in Settings (always-guide, voice cues, auto-start rest, haptics).
- Uses AppTheme only; Dynamic Type must not truncate the target line (scrolls instead).

## 5. Data model

**Core Data**: create a NEW model version `Lightstack 5.xcdatamodel` (never edit v4), set it current, lightweight migration with defaults, and add a case to `CoreDataMigrationTests`.

`Workout` additions (all optional or defaulted):
- `coachModeUsed: Bool` default false
- `plannedSetCount: Int16` default 0, `coachAdjustCount: Int16` default 0 (for adherence and the review prompt)

`WorkoutSet` additions:
- `wasCoachTarget: Bool` default false (logged as prescribed) and `coachTargetWeight: Double` / `coachTargetReps: Int16` optional (what was prescribed, to compute adherence without re-deriving)

**Supabase** migration `2026MMDDHHMMSS_coach_mode.sql`:
```sql
ALTER TABLE workouts ADD COLUMN coach_mode_used BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE workouts ADD COLUMN planned_set_count INT NOT NULL DEFAULT 0;
ALTER TABLE workouts ADD COLUMN coach_adjust_count INT NOT NULL DEFAULT 0;
ALTER TABLE sets ADD COLUMN was_coach_target BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE sets ADD COLUMN coach_target_weight NUMERIC;   -- nullable
ALTER TABLE sets ADD COLUMN coach_target_reps INT;         -- nullable
```
Lesson from the `is_per_arm` incident: always send the NOT NULL columns in every insert/bulk payload (`SyncService` / `OfflineQueueManager`), and ship the migration before the app build. Add a rollback file under `supabase/migrations/rollback`.

Preferences (voice, always-guide, auto-rest) go in `CoachPreferences` (UserDefaults), no schema.

## 6. AI prompt and cost impact

- **Per-set guidance: no AI.** Targets, rest and miss adjustments are deterministic (`ProgressionEngine`, `InSessionAdjuster`). Cue lines come from `ExerciseGuideLibrary` and static templates.
- **Unchanged AI calls**: plan generation (1), post-workout review (1), optional chat. Net new calls per session: 0 baseline.
- **Optional**: one extra "coach line" call only when a set is missed by a wide margin and the athlete taps "Why?"; capped at 3 per session client-side, so worst case about 5 calls per session against 100/day and 10/min.
- **Prompt change**: post-workout prompt gains one line with adherence (`coach_adjust_count`, planned vs completed sets) so `CoachReviewDocument` can comment on it. Update `docs/COACH_PROMPT.md` and `CoachPromptServiceTests`.
- On rate-limit or 503 the session continues unaffected (AI is never in the set loop); the post-workout call keeps its existing fallback and "no auto-save on AI failure" rule.

## 7. Offline behaviour

The whole loop is local (targets already computed and stored on pending sets), so airplane mode works end to end. Sets, workout flags and adherence sync through the existing `OfflineQueueManager` in FK order; the new columns ride on the same operations. Only the "Why?" line and post-workout review need network; both degrade to a canned message and the existing retry path.

## 8. Accessibility and tests

Identifiers (stable): `coachMode.startButton`, `coachMode.setCard`, `coachMode.target`, `coachMode.doneButton`, `coachMode.weightStepper`, `coachMode.repsStepper`, `coachMode.rirPicker`, `coachMode.restTimer`, `coachMode.skipRest`, `coachMode.extendRest`, `coachMode.nextPreview`, `coachMode.missPrompt.accept`, `coachMode.exit`, `coachMode.finish`, `coachMode.settings.alwaysGuide`.

VoiceOver: set card is one combined element reading "Bench press, set 2 of 4, 155 pounds, 8 reps, 2 in reserve"; rest announces remaining time at 10 s and 0; large tap targets (>= 44 pt, primary button full width); reduce-motion respected; haptics optional.

**Unit tests**: migration v4 -> v5 defaults; adherence math; target carry-over after a miss; sync payload includes new NOT NULL fields.
**UI tests** (`LightstackUITests/CoachModeTests.swift`, from `launchApp()` with the fake AI provider): start guided session; log all sets as planned; log a miss and accept the lowered prompt; rest skip/extend; kill and resume on the same set; finish reaches the review card; run in light and dark (`-appColorScheme`). Per the Bug Workflow, add a reproducing test before any fix.

## 9. Phased rollout (each phase shippable)

1. **P1 Guided set loop (core)**: v5 model + migration, `GuidedSessionView` set and rest screens, "Done as planned", reuse miss banner. Behind a Settings toggle, off by default. TestFlight to owner.
2. **P2 Adherence and review**: persist prescribed vs actual, feed one line to the post-workout prompt, History shows an "as planned" badge.
3. **P3 Voice and hands-free**: TTS cues, Live Activity "Done as planned" action (via `LiveActivityActions`), haptic patterns.
4. **P4 Defaults**: make guided the default for coach-generated plans if usage and feedback are good; groundwork for Interpretation B (deload suggestions from adherence trends).

## 10. Risks

- Two UIs over one state: divergence bugs (mitigation: view-only layer, single `ActiveWorkoutViewModel`, shared tests).
- Migration/sync wedge from new NOT NULL columns (mitigation: defaults, send in all payloads, migrate Supabase first, rollback script).
- Over-trust in targets: bad history yields bad prescriptions (mitigation: `PlanGuardrails` stay in the path; always allow override).
- Background audio/TTS interrupting music; battery from screen-on (mitigation: ducking, no keep-awake unless in guided mode).
- Scope creep into B/C; keep out of v1.

## 11. Open questions for the owner

1. Which interpretation did you mean (A, B or C)? If B or C, this doc needs rewriting.
2. Should guided mode replace the list view as default, or stay opt-in?
3. Voice: spoken cues in v1, or silent first?
4. Should a missed set auto-lower the remaining sets, or always ask first (current design: ask)?
5. Any "Why?" AI line at all, given the free-tier budget?
6. Apple Watch / lock-screen logging in scope for phase 3?
7. Should adherence ("as planned") be visible in History and Progress, or kept private to the review?
