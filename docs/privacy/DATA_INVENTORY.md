# LightStack Data Inventory

Derived from the Core Data model, the Supabase schema (`supabase/supabase_schema.sql` and migrations) and the AI prompts (`CoachPromptService`). Update it whenever a model or prompt changes.

## Where data lives

| Place | What | Notes |
|---|---|---|
| Device (Core Data, UserDefaults, Keychain) | Everything below, plus the offline sync queue, settings and the Supabase session | Removed by Delete account |
| Supabase (Postgres + Auth) | Account and all synced tables | Row-level security per user; removed by `delete-account` |
| Google Gemini (via `ai-proxy`) | Prompt content for AI features only (coaching text, meal descriptions, meal photos). Restaurant meals may also use Google Search grounding | Needs user consent; not stored by LightStack. Retention is under Google's terms |
| Open Food Facts | Barcodes and food search text | No account identifier sent |

## Data collected

| Data | Fields | Purpose | Device | Supabase | Gemini |
|---|---|---|---|---|---|
| Account | email or Apple/Google identity, user id | Sign-in | session only | auth.users | no |
| Profile | display name, age, height, weight, training age, goals, split days, avoid list, equipment, notes to coach | Personalisation, coaching | CDUserProfile | profiles | partly (see below) |
| Workouts | type, dates, notes, exercises, sets (weight, reps, RIR), per-arm flags, supersets | Core feature, progress | CDWorkout, CDExercise, CDWorkoutSet | workouts, exercises, sets | recent sessions |
| Personal records | exercise, weight, reps, date | Progress | CDPersonalRecord | personal_records | maybe in context |
| Plans | month plans, planned sessions, rest days | Scheduling | CDMonthPlan, CDPlannedSession, CDRestDay | month_plans, planned_sessions, rest_days | plan chat |
| Coach summaries | rolling AI context text | Coaching memory | CDAIContextSummary | ai_context_summaries | yes |
| Coach chat | messages typed to the coach | Coaching | in memory / debug store | no | yes |
| Nutrition | foods, entries, meal slots, water, day notes, targets, goal settings, plans | Nutrition tab | CDFood, CDFoodEntry, CDMealSlot, CDWaterEntry, CDDayNote, CDNutritionTarget, CDNutritionGoalSettings, CDNutritionPlan | matching tables | no |
| AI meal logging input | meal description text and meal photos the user chooses to send | Estimate nutrition for a meal | not stored (photo sent once) | no | yes |
| Sync bookkeeping | tombstones, rate-limit rows | Sync correctness, abuse control | queue in UserDefaults | sync_tombstones, rate_limits | no |
| Form check video | camera frames analysed on device (Vision pose); only the numeric result summary may go to AI feedback | Form feedback | not stored | no | summary text only |
| Preferences | theme, units, rest timer, Live Activity | Settings | UserDefaults | no | no |

No advertising, analytics or crash-reporting SDKs are present.

## What goes to Google Gemini

AI meal logging (nutrition phase 4) also sends the meal description you type and any meal photo you choose to send, through `ai-proxy`, to estimate nutrition. Restaurant meals may use Google Search grounding. Photos are sent only on a user action and are not stored by LightStack.

`CoachPromptService.profileLine` sends, on every AI call: display name, age, weight, height, training months, goals, avoid list, equipment, notes to coach. Task prompts add recent sessions (exercises, sets), best sets, rolling summary, the day's notes/time/energy, and chat messages.

### Minimisation (proposed; `CoachPromptService` is not in this workstream)

1. Remove `display name` from `profileLine` (the first `parts.append(name)`); the coach does not need it. Highest value, lowest risk.
2. Replace exact age with an age band (e.g. 30-34) and exact weight/height with rounded values (nearest 5 lb / 1 in) unless a prompt needs exact numbers.
3. Keep `notes to coach` but warn in the field help text not to enter health conditions or personal details; it is free text.
4. Never include email, user id or device identifiers in prompts (currently not included; keep it so).
5. Send only the last N sessions needed by each task (already limited; keep).

## Consent and control

- AI consent: UserDefaults `ai.thirdPartyConsent.v1` (Bool) plus `.date`; asked once, changeable in Settings. Without consent no AI request is made.
- Deletion: Settings, Delete account calls the `delete-account` Edge Function (all user tables, then the auth user), then wipes the device.
- Not yet offered: data export (needed for GDPR portability / CCPA access).
