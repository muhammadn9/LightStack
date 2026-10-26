# Nutrition logging: design (label-scan first)

Status: decisions applied, no code yet. Inspired by [MacrosFirst](https://apps.apple.com/id/app/id1253012487): macro targets are the headline, the home view answers "what is left today?", and the signature feature is **scanning a Nutrition Facts label with the camera** to create a food.

## 1. Decisions (owner)
1. Own **Nutrition tab**; no Today macro strip for now.
2. MVP = quick-add plus **on-device nutrition-label scanning** (headline feature).
3. Track and display **calories + macros + micros**. Targets for calories/macros only; micros shown, optional targets later.
4. **No AI** for now (no Gemini estimates). Possible future phase only.
5. **No Apple Health.**
6. **Coach does not see nutrition data** for now.
7. External food databases (Open Food Facts / USDA) are a later phase.

## 2. Goals and non-goals
Goals
- Daily calorie/protein/carb/fat targets; **remaining** at a glance.
- Create a food by scanning its label in seconds; reuse it from history afterwards.
- Fully offline, no network, no third-party dependency. Reuse Core Data local-first, outbox sync, `AppTheme`.

Non-goals (Phase 1): AI, barcode/database lookup, Apple Health, coach integration, meal planning/recipes, per-meal targets, micro targets, medical diet advice.

## 3. Where it lives
New **Nutrition** tab (`fork.knife`, tag 5) in `MainTabView`, behind a `FeatureFlags` flag until ready. Independent of `TodayPhase`; Today is untouched. Month flag is off by default so the tab bar stays at 5.

## 4. Targets
Manual only: kcal, protein, carbs, fat. Kcal auto-derives from macros (4/4/9) unless overridden; show the mismatch. Targets are versioned by effective date so history keeps the target that applied that day. Micros have no targets in Phase 1 (displayed totals only).

## 5. Logging methods (Phase 1)
- **Quick add:** optional name + kcal/P/C/F (micros optional, collapsed section).
- **Label scan** (section 6): creates a food, then logs N servings.
- **Own food history:** Recent, Favourites, and search over the user's own saved foods (local query). Logging a saved food snapshots its values into the entry.

## 6. Label scanning (headline)
**Flow:** Scan button -> camera (live scan) -> OCR text -> `NutritionLabelParser` -> **review form prefilled** -> user edits name, serving size, servings, any value -> Save (creates `CDFood` and optionally logs an entry). Uncertain fields are highlighted; nothing is saved without the user confirming.

**Frameworks (Apple only, no AI, no 3rd party):** `VisionKit.DataScannerViewController` (`.text()` recognized items, live) as primary; fallback `VNRecognizeTextRequest` (`.accurate`, language correction off, `recognitionLanguages` en-US/en-GB) on a captured camera frame or the simulator/unsupported devices (`DataScannerViewController.isSupported`/`isAvailable` false). Needs `NSCameraUsageDescription`. SwiftUI wrapper via `UIViewControllerRepresentable` (existing pattern; no UIKit view controllers of our own). Gather recognized lines with bounding boxes, accumulate across frames, and let the user tap "Use this" (no auto-commit).

**Parser design** (`NutritionLabelParser`, pure Swift, no Vision import; input is `[OCRLine]` of text + normalized bounding box, plus a convenience `parse(text:)`):
1. **Normalise:** lowercase, fold OCR confusions in numeric context (`O->0`, `l/I->1`, `,`->`.` decimal when one comma and <=2 trailing digits, `S->5` only next to digits), strip `%DV` tokens and collapse whitespace. Join a nutrient name with its value when OCR splits them across lines/columns (same baseline within a y-tolerance, value to the right).
2. **Detect format:** `Nutrition Facts` / `Serving size` / `%DV` -> **US**; `Nutrition information` / `per 100g` / `per serving` / `kJ` / `Typical values` / `of which` -> **EU/UK**. Mixed labels default to the per-serving column if present.
3. **Serving:** US `Serving size 2/3 cup (55g)` -> label text + grams (parenthesised metric wins), `Servings per container N`. EU/UK: `per 100g` / `per 100ml` column and optional `per serving (30g)` column; store both, **normalise to per-serving** using the serving grams (if absent, use per-100g with serving = 100 g and flag uncertain).
4. **Nutrient dictionary** (case-insensitive, synonym list, longest match first): calories/energy (kcal; kJ converted /4.184 when kcal absent; kcal preferred when both), total fat, saturated fat (`saturates`), trans fat, cholesterol, sodium (`salt` g -> sodium mg x400), total carbohydrate (`carbohydrate`), dietary fibre/fiber, total sugars (`of which sugars`), added sugars (`includes Xg added sugars`), protein, potassium, calcium, iron, vitamin D, plus other vitamins/minerals when present (A, C, E, B-vitamins, magnesium, zinc, etc.).
5. **Units:** accept g, mg, mcg/µg/ug, kcal, kJ, IU (kept as-is). Convert to canonical (g for macros, mg for minerals, mcg for vitamins where applicable). `<1g`/`less than 1g` -> 0.5 with low confidence; `0` / `-` / `trace` -> 0.
6. **%DV handling:** a trailing `%` figure is never used as the amount. Used only as a cross-check for micros (value vs standard DV, e.g. sodium 2300 mg, potassium 4700 mg, calcium 1300 mg, iron 18 mg); a large mismatch lowers confidence. If a micro shows only %DV (no amount), store nothing and flag.
7. **Confidence + highlights:** each field gets `value`, `unit`, `confidence` 0-1, and `source` (matched line). Confidence drops for: OCR digit confusion repaired, value not adjacent to its name, unit missing/guessed, kJ-derived kcal, %DV mismatch, **macro consistency fail** (4P+4C+9F vs kcal off by >15%), or sum checks (sugars > carbs, sat fat > fat). Below ~0.7 the review form highlights the field (colour + icon + VoiceOver "check this value"); missing required fields (kcal/P/C/F, serving) are shown empty and highlighted.
8. **Output:** `ParsedLabel { name?, servingLabel, servingGrams?, servingsPerContainer?, format, fields: [Nutrient: ParsedValue], warnings }`.

**Unit tests (fixtures in `LightstackTests/Fixtures/labels/*.txt`, one OCR dump per file, expected JSON beside it):** US standard label; US with added sugars and vitamins (D, calcium, iron, potassium); US with `2/3 cup (55g)` and decimals; EU per-100g + per-serving columns with kJ/kcal; UK `Energy 1046kJ / 250kcal`, `salt` instead of sodium; per-100ml drink; OCR noise (`O`/`l` swaps, comma decimals, split lines); `<1g` / trace / zero; %DV-only micro; macro-inconsistent label (should flag); garbage text (returns empty + warning). Assert values, units, kJ/salt conversions, and which fields fall below the confidence threshold.

**Test-mode stub:** in `-uiTesting`, the scanner view is replaced by a stub that injects a fixture OCR string (selectable via launch argument), so UI tests exercise parse -> review -> save without a camera.

## 7. Data model
**Core Data:** NEW model version `Lightstack 5.xcdatamodel` (lightweight migration, set current in `.xccurrentversion`); never edit version 4 in place (load `fatalError`). Entities (all `id UUID`, `userId`, `createdAt`, `updatedAt`):
- `CDNutritionTarget`: effectiveDate, kcal, protein, carbs, fat.
- `CDFood`: name, brand?, servingLabel, servingGrams?, per-serving kcal/P/C/F, micros (fiber, sugar, addedSugar, satFat, transFat, cholesterol, sodium, potassium, calcium, iron, vitaminD, plus `otherMicros` JSON for the rest), source (quick/scan), isFavorite, lastUsedAt.
- `CDFoodEntry`: date (local day), foodId?, name snapshot, servings, kcal/P/C/F + micros snapshot (editing a food never rewrites history), source (quick/saved/scan).
Daily totals are computed from entries, not stored. Micro fields are optional (nil = unknown, distinct from 0).

**Supabase** (new migration under `supabase/migrations/`, mirrored in `supabase_schema.sql`): `nutrition_targets`, `foods`, `food_entries`. RLS on every table (`user_id = auth.uid()` for select/insert/update/delete), indexes on `(user_id, date)`. Dates sent as device-local `yyyy-MM-dd`. **Every NOT NULL column with a default is sent explicitly in bulk payloads** (the `is_per_arm` wedge): non-optional fields always encoded, with a unit test that encodes a full payload.

**Sync:** outbox operation types (upsert + delete per table) in `OfflineQueueManager`, FK order foods -> entries, tombstones for deletes. Extend `SyncRestoreService` (local pending wins, restore never uploads, first-reconciliation rules apply); page entry restore like workouts.

## 8. Accessibility and tests
- Identifiers: `nutrition.tab`, `nutrition.remaining.calories|protein|carbs|fat`, `nutrition.quickAdd.button`, `nutrition.quickAdd.{name,kcal,protein,carbs,fat,save}`, `nutrition.scan.button`, `nutrition.review.field.<nutrient>`, `nutrition.review.{servings,save}`, `nutrition.food.<id>`, `nutrition.entry.<id>`, `nutrition.target.edit`, `nutrition.history.search`. Rings/bars have VoiceOver labels ("Protein, 120 of 180 grams, 60 remaining"), never colour alone; Dynamic Type safe; AppTheme only.
- UI tests (`LightstackUITestCase`, `-uiTesting`): set targets -> quick add -> remaining updates; scan stub -> review (uncertain field highlighted) -> edit -> save -> log servings -> totals update; reuse from recent/favourites/search; delete entry; relaunch persistence.
- Unit tests: label parser fixtures (section 6), totals/remaining maths, payload encoding (NOT NULL defaults), migration v4 -> v5, restore rules.

## 9. Phased rollout
- **Phase 1:** Nutrition tab + flag, manual targets, quick add, **label scan + review form**, own food history (recent/favourites/search), edit/delete entries, daily remaining view with micros, Core Data v5, Supabase tables (RLS, NOT NULL defaults) + outbox sync/restore, UI tests with scanner stub, parser unit tests.
- **Phase 2:** saved meals, copy yesterday/day, barcode scan, external food DB search (Open Food Facts, USDA via a key-holding proxy), suggested targets, training/rest-day targets, optional micro targets, imperial/metric serving units.
- **Phase 3 (future, owner-gated):** AI estimates, weekly adherence in Progress, coach context.
- **Phase 4 (future, owner-gated):** Apple Health, widgets.

## 10. Risks
- OCR accuracy varies (glare, curved packs, multi-column EU labels): always show a review form, highlight low confidence, never auto-save.
- Sync scope (three new tables): ship sync with tests in Phase 1.
- Migration mistakes crash on launch: test v4 -> v5 on a real store copy.
- Scanner is device-only (camera): simulator uses the stub path; verify on device before TestFlight.
- Scope creep into a full calorie tracker; hold the macro-first line.
- Health-adjacent sensitivity: no "bad food" language, sane target floors, disclaimer.

## 11. Decisions

D1. **Serving units are user-selectable** (g, oz, cup, ml, piece, serving, etc.). The label's household text is kept; conversion to grams/ml is stored where known.
D2. **Per-100g-only labels** (no serving size) default to a 100 g serving, highlighted in the review form, and editable.
D3. **No photo-library scan in Phase 1.** Scanning is camera-only (plus the test stub); `PhotosPicker` is deferred.
