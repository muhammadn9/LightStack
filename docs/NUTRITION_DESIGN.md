# Nutrition logging: design (macro-first)

Status: proposal, no code yet. Inspired by [MacrosFirst](https://apps.apple.com/id/app/id1253012487): macro targets are the headline, logging is fast (quick add, saved meals, copy day, barcode, large database), and the home view answers "what is left today?".

## 1. Goals and non-goals
Goals
- Set daily calorie/protein/carb/fat targets; see **remaining** at a glance.
- Log a meal in under 10 seconds for repeat foods; works fully offline.
- Tie intake to training (protein vs training days; coach can read it).
- Reuse existing stack: Core Data local-first, outbox sync, Gemini via `ai-proxy`, `AppTheme`.

Non-goals (v1): micronutrients (MacrosFirst tracks 57; we track kcal/P/C/F, optional fiber), meal planning/recipes, social features, per-meal targets, a self-hosted food database, medical/clinical diet advice.

## 2. Where it lives
Today tab is already the workout surface (`MainTabView`: Today, History, Progress, Profile, optional Month). Recommendation: **new "Nutrition" tab** (fork.knife icon, tag 5, behind a `FeatureFlags` flag until ready), plus a compact **macro-remaining strip on Today** that deep-links to it. Reason: logging happens many times a day, independent of a workout session, and must not touch `TodayPhase` state. History/Progress get nutrition views later (Phase 3). Tab bar goes to 5 items (6 with Month flag on); the Month flag is off by default so this fits.

## 3. Target setting
- **Manual (default, MVP):** four fields (kcal, P, C, F). Kcal auto-derives from macros (4/4/9) unless the user overrides; show the mismatch.
- **Suggested (Phase 2):** from profile (`weightLbs`, `heightInches`, `age`; add sex + activity), goal (cut/maintain/bulk) -> Mifflin-St Jeor TDEE, protein 0.8-1.0 g/lb, fat 25-30% kcal, carbs remainder. Shown as a suggestion the user accepts; never silently overwrites.
- Optional **training-day vs rest-day targets** (carbs shift). Training day is known from workouts/`CDRestDay`.
- Targets are versioned by effective date so history keeps the target that applied that day.

## 4. Logging methods, ranked by cost (build order)
| # | Method | Cost | Notes |
|---|---|---|---|
| 1 | Quick add macros | none | Name optional + P/C/F/kcal. MVP. Most MacrosFirst-like fast path. |
| 2 | Recent foods + "copy yesterday/meal" | none | Local query over entries, dedup by name. MVP. |
| 3 | Saved foods / meals | none | User-created `food` rows, a meal is a set of items. MVP (foods), Phase 2 (meals). |
| 4 | Food database search | free API | See below. Phase 2. |
| 5 | Barcode scan | free | `DataScannerViewController` / `AVCaptureMetadataOutput` (VisionKit/AVFoundation, no 3rd-party dep) -> barcode lookup. Phase 2. |
| 6 | AI text/photo estimate | Gemini quota | Phase 3. |

**Food database options**
- **Open Food Facts:** ODbL (attribution + share-alike on derived databases; calling the API per lookup and caching individual results is fine), strong on packaged goods and barcodes, no key, ask for a descriptive User-Agent, rate limits are modest (about 100 req/min product reads, 10/min search), so cache every result locally. Data quality is crowd-sourced and uneven; nutrients can be missing.
- **USDA FoodData Central:** public domain (CC0), free key (about 1,000 req/hour/key), excellent for generic and whole foods (Foundation/SR Legacy), weaker for branded/international barcodes. A key must not ship in the app: proxy through an edge function.
- **Recommendation:** barcode and packaged goods -> **Open Food Facts**; generic foods search -> **USDA FDC** via a thin `food-proxy` edge function (holds the key, adds per-user rate limit and caching). Both write into the same local `CDFood` cache, so repeats are offline. Do not bundle a full database offline (hundreds of MB); ship a small curated generic list (about 300 staples) if search must work with no network. Verify current licence/limit terms before launch.

**AI estimate (Phase 3).** Reuse `AIServiceManager` + `ai-proxy` with a new task type returning JSON `{items:[{name, grams, kcal, p, c, f, confidence}]}`; user always reviews and edits before saving (no auto-save on failure). Text is cheap; photo needs image parts and `ai-proxy`'s 200k-char body cap and model allow-list need checking. Free tier is shared with the coach (10/min, 100/day per user): give nutrition AI its own sub-budget (e.g. 30/day) so it cannot starve the coach, and fall back to quick add when limited. Accuracy for photos is rough (+/-20-30%); label it "estimate".

## 5. Data model
**Core Data:** add a NEW model version `Lightstack 5.xcdatamodel` (lightweight migration, set as current in `.xccurrentversion`); never edit version 4 in place (load `fatalError`). Entities (all with `id UUID`, `userId`, `createdAt`, `updatedAt`):
- `CDNutritionTarget`: effectiveDate, kcal, protein, carbs, fat, dayType (all/training/rest).
- `CDFood`: name, brand, barcode?, source (user/off/usda), servingGrams, servingLabel, per-serving kcal/P/C/F/fiber, isFavorite, lastUsedAt.
- `CDFoodEntry`: date (local day), mealSlot (nullable int), foodId?, name snapshot, servings, kcal/P/C/F snapshot (so edits to a food never rewrite history), source (quick/saved/db/barcode/ai).
- `CDSavedMeal` + items (Phase 2).
Daily totals are computed from entries, not stored.

**Supabase** (new migration file under `supabase/migrations/`, mirrored in `supabase_schema.sql`): `nutrition_targets`, `foods`, `food_entries`, `saved_meals`, `saved_meal_items`. RLS on every table (`user_id = auth.uid()` for select/insert/update/delete), indexes on `(user_id, date)`. Dates sent as device-local `yyyy-MM-dd` (see SYNC_DESIGN). **Every NOT NULL column with a default must be sent explicitly in bulk payloads** (the `is_per_arm` wedge); encode non-optional fields always, add a unit test that decodes/encodes a full payload.

**Sync:** add outbox operation types (upsert + delete per table) to `OfflineQueueManager`, FK order: foods -> entries/meals. Use tombstones for deletes like workouts. Extend `SyncRestoreService` (local pending wins, restore never uploads, first-reconciliation rules apply). Entries are small and numerous: page restore like workouts.

## 6. Link to training
- Protein target compared with logged protein on training days; Progress shows weekly adherence (days within +/-10% of protein/kcal).
- Coach context: add one line to `CoachContextBuilder` (7-day average kcal/protein, target, bodyweight trend) so the coach can say "you are 40 g short on protein on lift days". Opt-in toggle; nothing sent if nutrition is unused. Keep the prompt small.
- Bodyweight trend (already stored per workout/profile) displayed beside intake to answer "is the cut working?".

## 7. HealthKit (optional, Phase 4)
Write dietary energy/protein/carbs/fat (`HKQuantityType` dietary*) so Apple Health and other apps see intake; optionally read bodyweight and active energy for TDEE. Needs entitlement, usage strings, and a privacy-policy update; write-only first. Not required for the core feature; avoid double-counting if we ever read dietary data back.

## 8. Accessibility and tests
- Stable identifiers: `nutrition.tab`, `nutrition.remaining.calories|protein|carbs|fat`, `nutrition.quickAdd.button`, `nutrition.quickAdd.{name,kcal,protein,carbs,fat,save}`, `nutrition.entry.<id>`, `nutrition.target.edit`, `nutrition.search.field`, `nutrition.scan.button`. Macro rings/bars need VoiceOver labels ("Protein, 120 of 180 grams, 60 remaining") and must not rely on colour alone; Dynamic Type safe; AppTheme colours only.
- UI tests (`LightstackUITestCase`, `-uiTesting` seeded store, fake network/AI providers): set targets -> quick add -> remaining updates; delete entry; copy yesterday; relaunch persistence. Unit tests: totals/remaining maths, TDEE calc, payload encoding (NOT NULL defaults), migration v4 -> v5, restore rules, OFF/USDA response mapping from fixtures.

## 9. Phased rollout
- **Phase 1 (MVP):** v5 model, targets (manual), quick add, recent foods, favourites, edit/delete entries, daily remaining view, Today strip, Supabase tables + RLS + sync/restore, flag, UI tests.
- **Phase 2:** saved meals, copy day, food search (USDA proxy + OFF), barcode scan, suggested targets, training/rest-day targets.
- **Phase 3:** AI text then photo estimate, weekly adherence in Progress, coach context.
- **Phase 4:** HealthKit, label-scan import, widgets/Live Activity glance.

## 10. Risks
- Sync scope: five new tables increase outbox/restore surface; mitigate by shipping sync with tests in Phase 1, not later.
- Migration mistakes crash on launch; test v4 -> v5 on a real store copy.
- Database quality/licence (OFF ODbL attribution, missing nutrients); show source, allow edit-before-save.
- Gemini free-tier exhaustion shared with coach; separate budget, graceful fallback.
- Scope creep into a full calorie tracker; hold the macro-first line.
- Health-adjacent claims and eating-disorder sensitivity: no "bad food" language, sane target floors, disclaimer; App Store review of health data use.
- Daily logging increases write volume; entries are tiny but restore paging must be tested at thousands of rows.

## 11. Open questions for the owner
1. Dedicated tab, or only inside Today? (Recommended: tab plus Today strip.)
2. Is Phase 1 quick-add-only acceptable for the first TestFlight, or is search/barcode needed at launch?
3. Units: grams only, or also oz/cups? Imperial/metric follows profile?
4. Calories shown at all, or strictly macros-first (kcal derived, secondary)?
5. Nutrition AI budget: separate quota OK, or wait until a funded provider exists?
6. Include HealthKit, and is a privacy-policy update acceptable?
7. Training-day vs rest-day targets in v1 or later?
8. Should the coach see intake data by default or opt-in?
9. Is a small proxy edge function for USDA (with caching) acceptable infrastructure?
