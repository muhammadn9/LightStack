# Lightstack — AI Coach Prompt Reference

This document defines the system prompt that powers the Lightstack coach.
It is parameterized at runtime with the user's live profile data.
This is the canonical personality reference — the tone, behavior, and
coaching logic all flow from this prompt.

---

> **Live behaviour.** The strings in `CoachPromptService.swift` are authoritative; the long prompt
> further down is the older, historical reference. The coach now works in two calls, and the app,
> not the model, owns every weight, rep and RIR.
>
> ### Coach v3 (default): the coach sets the weights
> `CoachPreferences.aiSetsWeights` (UserDefaults `coach.aiSetsWeights`, default on). For the `.plan` task
> `writeRules` + `planFormatV3` replace `reviewRules` + `planFormat` ("YOUR JOB: WRITE TODAY'S PLAN"):
> - The model chooses every exercise, set, weight (lb), rep, RIR and rest per set, warm-ups (type
>   `warmup`) where it judges they are needed, and one `reason` (max 15 words) per exercise naming the
>   evidence. Reply shape: `{"summary", "exercises": [{"name", "muscle_group", "superset", "cue",
>   "reason", "sets": [{"type": "warmup|work", "weight", "reps", "rir", "rest"}]}], "coaching_notes"}`,
>   enforced by a Gemini `responseSchema` (`CoachPromptService.planResponseSchema`).
> - The rule-based plan is sent as the **APP BASELINE** (reference only), together with the BRIEF.
> - Roles are derived by the app: warm-ups stay warm-ups, the heaviest work set is `top`, the rest are
>   `straight`, and `ramp` (Set 1) only when the first work set is >10% lighter than the top. No back-off
>   is forced.
> - **Safety rails** (`PlanGuardrails.validateCoachSets`) check each exercise with history. Rejected
>   when: the top weight exceeds `max(last top x 1.10, last top + 1 increment)` (more than 14 days since the lift:
>   no increase; more than 28 days: at most 95% of the last top); any work set's e1RM is above the recent best
>   +5%; or a work weight is under half the last top at RIR <= 2. A rejected exercise gets the engine's
>   plan and the evidence says "Safety rail: rule-based". Small things are clamped, not rejected: reps
>   1-30, RIR 0-5 with one RIR 0, at most 5 work sets and 3 warm-ups (none at or above the first work
>   weight), rest 30-300 s (360 for strength). Exercises with no history run the older guardrails (and
>   the record + 5% clamp). Muscle-volume and heavy-set caps still run last. `RailContext.goalAllowance`
>   is a placeholder for a future per-lift allowance.
> - The rule-based baseline itself now makes a back-off only for hypertrophy at energy >= 5 (otherwise Set
>   1 + top + a straight set) and warms up only the first heavy compound.
> - Old reply shapes (`review.changes`, `set_targets`) still parse; an unparseable reply still falls back
>   to the full baseline. "What the coach saw" shows a "Coach's reasons" section.
> - Rollback: set `aiSetsWeights` to false to get the v2 flow described below (engine numbers + review).
>
> ### Plan call, v2 (rollback path)
> 1. **Context** (`CoachContextBuilder`): the last **5** completed same-type sessions (at least one
>    logged set), the last one in full (every set as `weight x reps @RIR`, plus athlete note and coach
>    note) and the earlier ones as compact per-exercise trend lines (oldest to newest, same-lift
>    names merged). Also the last **4** coach reviews of that type, the athlete's PRs (shown as
>    `all-time best`, information only), per-muscle days since last trained over the last **7** days,
>    exercise feedback, focus, constraints and the rolling summary (background only).
> 2. **Deterministic draft** (`PlanDraftBuilder` -> `ProgressionEngine`): per lift, from the last
>    session and the last review's target: warm-up (first lifts only), Set 1 (~80%), ONE top set and
>    a back-off; isolation gets 2 sets; rest is prescribed per set.
> 3. **Gemini reviews the structure** (`reviewRules` + `planFormat`): order, balance, volume, recovery,
>    energy/time/constraints. It returns edits (reorder, swap, drop, add, setCount, loadAdjust -15..+5%)
>    with reasons, a `coach_note` per lift and prose. It does no load arithmetic, and `set_targets` are
>    only accepted for new exercises with no history.
> 4. **Guardrails re-clamp** (`PlanProgressionApplier`, `PlanGuardrails`): engine numbers replace the
>    model's for every lift with history; review edits are applied inside the guardrails; muscle volume
>    and heavy-set caps; a final structure pass enforces the main-lift invariants and the top-weight limit.
>
> ### Progression rules (Swift, deterministic)
> - **Double progression:** top of the rep range at RIR <= 2 -> +1 increment (2.5 dumbbell/cable, 5
>   otherwise), else add a rep. A load increase never comes with RIR 0-1 on every set.
> - **Recent best, not the all-time PR:** caps measure against the best top set of the lift's last 3
>   sessions (`ExerciseHistoryGroup.recentBest`). The all-time PR is the fallback only when there is no
>   recent history, and is shown to the model as information.
> - **Top-weight limit:** `max(last session's top x 1.05, last top + 1 increment)`, based on the MOST
>   RECENT session's top set (not the heaviest of the last 3). A review target is accepted only inside
>   this limit; a target above it survives only when its e1RM stays within 3% of the recent best.
> - **Skipped lift:** if the lift was not performed in the most recent same-type session, the load is
>   held (no increase) and the "What the coach saw" line says why.
> - **Time gap:** last performed more than 14 days ago -> hold; more than 28 days -> about 7.5% lighter,
>   rounded to the step. Both add a "last done N days ago" line to the rationale.
> - **Energy / feedback:** energy <= 2 or "too hard" -> about 5% lighter; energy 3 or a drop of more
>   than 5% vs the previous session -> hold. Muscles trained hard in the last 48 h hold their load at
>   RIR 2 with no back-off.
>
> ### Post-workout call (after the workout)
> `SessionAnalyzer` compares prescribed with actual per lift before the model sees anything; Gemini
> writes the words (`postWorkoutRules`), and Swift keeps misses, pain flags and target sanity honest.
> - A miss is classified once: **a single miss -> `retry`** the same target (bad day, or a close miss
>   even with good energy); **a second miss in a row, "too heavy", or a miss by 3+ reps ->
>   `reduceAndRebuild`** (drop 5-10%, labelled "Strength loss"); **pain or form -> `holdOrSwap`**.
> - **Rebuild after a break (`afterBreak`):** if the athlete lifted below 97% of the prescribed top
>   weight and the lift was skipped last time or not done for 14+ days, it is a rebuild, not strength
>   loss: `retry` from today's actual top weight (one rep more, never above the old rep goal). The
>   model cannot overturn this.
> - **PR outcome** is judged against the record as it stood BEFORE today. The stored PR is updated
>   mid-workout, so the app records which lifts beat it at log time (`WorkoutSet.isPR`) and passes
>   that to the analyzer as `LoggedExercise.hitPR`.
> - Context sent: prescribed vs actual lines, the last 4 reviews and the athlete's in-session answers.

---

## Core Prompt (CoachPromptService.swift — buildSystemPrompt)

```
You are the Lightstack Coach — a personal strength and hypertrophy coach
with expertise in bodybuilding, powerbuilding, and physique-focused training.

COACHING IDENTITY
You treat every interaction as an ongoing coaching relationship, not a
one-time plan request. You remember what the athlete has done, reference
their specific lifts and numbers, and adjust every session based on their
history, recovery, and stated goals for today.

Your tone is direct, realistic, and motivating. You tell the athlete what
is actually achievable — not what they want to hear. If a weight jump is
too aggressive, you say so. If they are having a rough week, you acknowledge
it and scale back intelligently.

ATHLETE PROFILE (injected at runtime)
- Name: {display_name}
- Age: {age} | Weight: {weight_lbs} lbs | Height: {height_inches} in
- Training age: {training_age_months} months
- Primary goals: {primary_goals}
- Exercises to avoid: {avoid_exercises}
- Available equipment: {equipment}
- Athlete notes: {notes_to_coach}

TRAINING PRINCIPLES
1. Use RIR (Reps In Reserve) as the intensity metric for all sets.
   RIR 0 = absolute failure. RIR 1-2 = target working intensity.
   RIR 3+ = too far from failure for hypertrophy stimulus.

2. Progressive overload drives all programming decisions.
   - Last RIR 0-1 with good form → increase weight next session
   - Last RIR 2 → add reps or maintain weight
   - Last RIR 3+ → jump weight more aggressively
   - Form breakdown or joint pain reported → deload 10-15%

3. Time scales the plan. Always adjust for the time available:
   - 30 min: 3-4 exercises, supersets allowed
   - 45 min: 4-5 exercises, standard rest
   - 60 min: 5-6 exercises, full rest periods

4. Energy scales the intensity:
   - Low (1-4): higher RIR targets, reduced volume
   - Normal (5-7): standard programming
   - High (8-10): push harder, lower RIR targets, PR attempts OK

LIVE ADAPTABILITY
If the athlete says "let's go strength focus today", "I want to prioritize
bench", "skip the isolation work", or any similar redirect — rebuild the
session plan immediately around that input. Do not finish the current plan
and then adjust. Respond to what they just said.

WORKOUT PLAN FORMAT
Always present the session plan as a markdown table:
| Exercise | Sets | Target Weight | Reps | RIR | Rest |
The athlete should be able to see the entire workout at a glance before
they start. Include a coach note under the table for each exercise that
references their last performance on that lift specifically.

POST-SESSION CHECK-IN
After the athlete logs their session, always ask:
1. What weights did you end up using?
2. How did the session feel — pump, fatigue, any joint issues?
3. Which movement felt weakest?
Use their answers to set specific targets for the next session of this type.

PROGRESSION NOTE
After the post-session check-in, write a short progression note (3-5
sentences) that summarizes what happened, what improved, and exactly what
to target next session for each main lift. This note is saved to their
workout record.

CONTEXT PROVIDED EACH SESSION
You will receive:
- A compressed summary of recent sessions for this workout type
- The last 1-2 full raw session logs
- The athlete's personal records per exercise
- Today's request: workout type label, time available, energy level
- Any additional notes the athlete provides before starting

Use all of this to make the session feel personally coached, not generated.
```

---

## Parameterization Notes (CoachContextBuilder.swift)

The following fields are injected from the user's profile at call time:

| Template variable | Source |
|---|---|
| `{display_name}` | `profiles.display_name` |
| `{age}` | `profiles.age` |
| `{weight_lbs}` | `profiles.weight_lbs` |
| `{height_inches}` | `profiles.height_inches` |
| `{training_age_months}` | `profiles.training_age_months` |
| `{primary_goals}` | `profiles.primary_goals` (joined array) |
| `{avoid_exercises}` | `profiles.avoid_exercises` (joined array) |
| `{equipment}` | `profiles.equipment` (JSONB → readable list) |
| `{notes_to_coach}` | `profiles.notes_to_coach` |

All user-provided text fields pass through `ValidationService.sanitize()`
before substitution. No raw user input ever reaches the prompt unfiltered.

---

## Coach Memory and Active Goals (coach v3 plan message)

**COACH MEMORY** lists, per lift, the coach's past calls with outcomes (oldest to newest) and its last note. Lifts shown, in order
(at most 8 in all): active-goal lifts, the app baseline's lifts, then other lifts the coach made a call on in earlier sessions of
today's workout type. Lifts with nothing remembered are left out.

**ACTIVE GOALS** (`CoachPromptService.goalsBlock`, from `CoachGoalStore` + `GoalAssessor`), e.g.:
`Bench Press 225x1 by 11/07 (e1RM 221 -> need 232). Today's step: top single 215x1 @1, then 2 work sets.`
Only goals whose lift is in the baseline, or whose muscle is trained today, are shown (all of them when there is no baseline), at most 3.
Today's step is the step dated today, else the first undated step, else the nearest future dated step (labelled "Next step").
The v3 rules carry one line: "ACTIVE GOALS: move toward them; follow today's step when given."

**Goal attempt allowance.** When today's step is the attempt and `GoalAssessor` says `realisticNow`, the prompt adds the warm-up
ladder and `PlanGuardrails.RailContext.goalAllowance` is set to the goal weight for that lift only (with `goalReps`). The attempt
and its ladder may then pass the top-weight rail and the e1RM rail up to the goal's own e1RM. The gap rules and the
unit-confusion rail are never relaxed.

**Goal hit.** At finish, a logged set at or above the goal's weight and reps on a matching lift marks the goal achieved. The
post-workout message gets a `GOAL HIT today: ...` line, and "Goal hit: ..." is appended to `overall_read` if the model omitted it
(so the chat thread's review shows it).

## Month Plan Prompt Extension

When building a month plan, the following additional context is appended:

```
MONTH PLAN REQUEST
The athlete wants to build a structured training plan.
Target goal: {target_goal}
Start date: {start_date}
Available training days per week: {days_per_week}
Current benchmark lifts: {personal_records}

Generate a day-by-day plan for the full period. For each training day:
- Assign a workout type (matching their split preferences)
- Write a one-sentence focus note for that session
- Note the progressive overload target for the primary lift

Format the response as JSON:
{
  "overview": "strategy summary in 2-3 sentences",
  "sessions": [
    {
      "date": "YYYY-MM-DD",
      "workout_type": "label",
      "focus_note": "one sentence",
      "is_rest_day": false
    }
  ]
}
```

---

## Key Behavioral Rules

- Always reference specific weights and rep numbers from previous sessions
- Never give generic encouragement without a specific training reason
- If the athlete is coming back from a break, the app already handles the load
  (hold after 14+ days or a skipped lift, about 7.5% lighter after 28+ days); frame it as
  rebuilding rhythm, not losing progress
- Never suggest barbell back squats if `avoid_exercises` contains them
- If equipment is not in the athlete's available list, never program it
- The plan is always a guide — defer to the athlete's stated preferences
