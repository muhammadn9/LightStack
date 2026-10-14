# Baseline findings — 2026-10-13 (main 5539be5)

All paths are relative to the repo root. Line numbers refer to main 5539be5.

## Baseline status

- Build passes. Unit tests 412/412 pass. UI tests 45/45 pass. Run on the iPhone 17 Pro simulator (latest iOS) with scheme `Lightstack` for the build and unit tests, and `LightstackUITests` for the UI tests.
- Warnings:
  - 4 x "no 'async' operations occur within 'await' expression".
  - Core Data "Multiple NSEntityDescriptions claim NSManagedObject subclass" in the tests (the model is loaded more than once in the test process).
- CI (`.github/workflows/objective-c-xcode.yml`) runs `xcodebuild clean build analyze` only. It runs no tests (F15).
- The iOS 17.2 simulator has a known issue where `scrollPosition(id:)` does not report swipes. 4 card-swipe UI tests and the import test fail there. Use iOS 26 for UI tests.

## Findings table

| ID | Sev | Confidence | Title | Phase |
|---|---|---|---|---|
| F1 | P0 | Confirmed | `flush()` overwrites the queue and erases operations enqueued during the flush | 1 |
| F2 | P0 | Confirmed | Operations silently dropped after 5 attempts, regardless of error type | 1 |
| F3 | P0 | Confirmed | Sign-out clears the queue and deletes unsynced operations | 1 |
| F4 | P0 | Confirmed (re-onboarding overwrite: Suspected) | No remote-to-local hydration | 2 |
| F5 | P1 | Confirmed | Corrupt queue decodes to `[]` and is overwritten; encode failures ignored | 1 |
| F6 | P1 | Confirmed | Flush only on reconnect and sign-in; overlapping flushes possible | 1 |
| F7 | P2 (downgraded from P1) | Confirmed | Plain inserts; retries after a lost response get 23505 and are treated as failures | 1 / 2 |
| F8 | P1 | Confirmed | Several mutations are local-only | 2 |
| F9 | P1 | Confirmed | Parent and child inserts are separate un-awaited Tasks | 2 |
| F10 | P1 | Confirmed | AI modification apply gaps | 4 |
| F11 | P2 | Confirmed | Prompt-injection surface: unsanitized names and summary in prompts | 4 |
| F12 | P2 | Confirmed | No AI request cancellation; rate-limit slots burned by retries | 4 |
| F13 | P2 | Confirmed (non-idempotent: Suspected) | Unversioned, unordered Supabase migrations; destructive script | 2 / 3 |
| F14 | P3 (downgraded from P2) | Confirmed | Verification password held in Keychain until verified | 3 |
| F15 | P2 | Confirmed | CI runs no tests | 3 |
| F16 | P3 | Confirmed | `docs/BLUEPRINT.md` is stale | 6 |
| F17 | P3 | Confirmed (empty workout row left behind) | Workout row created before the plan AI call; left empty on failure | 2 |

---

### F1 — `flush()` overwrites the queue and erases operations enqueued during the flush
- **Severity:** P0
- **File & location:** `Lightstack/Core/Utilities/OfflineQueueManager.swift`, `flush()` lines 134-175 (snapshot at 135, `await execute(op)` at 164, `saveQueue(failed)` at 174).
- **Steps to reproduce:** Go offline and log sets, so ops are queued. Go online so a flush starts. While it is awaiting a remote call, log another set while the remote is failing or slow. The new `enqueue` runs at an `await` suspension point because the actor is reentrant.
- **Expected:** The new operation stays in the persisted queue.
- **Actual:** `flush()` ends with `saveQueue(failed)`. `failed` only contains ops from the earlier snapshot, so it replaces the persisted queue and the new op is gone.
- **User impact:** Silent loss of cloud writes (sets, workouts). The data stays in Core Data but never reaches Supabase.
- **Confidence:** Confirmed (code reading; the interleaving requires a failing or slow remote call during a flush).
- **Proposed solution:** Remove only the processed op IDs from the current persisted queue after each op, instead of overwriting. Or hold the queue in memory in the actor and persist after each mutation. Add a unit test that enqueues from a concurrent task during a flush.
- **Phase:** 1

### F2 — Operations silently dropped after 5 attempts, regardless of error type
- **Severity:** P0
- **File & location:** `OfflineQueueManager.swift` line 70 (`maxAttempts = 5`), lines 162-172 (the `catch` increments `attempts` and drops the op at 5).
- **Steps to reproduce:** Queue an op, then trigger 5 flushes that fail. Each reconnect or sign-in is one pass, so this takes five reconnects or sign-ins. Any error counts the same: offline, 5xx, RLS denial, FK violation.
- **Expected:** Transient failures (network, 5xx) are retried indefinitely or with backoff. Permanent failures are surfaced.
- **Actual:** After the fifth failed pass the op is discarded (the comment says "silently drop").
- **User impact:** Data that was waiting for a long outage or a transient server problem never reaches the cloud.
- **Confidence:** Confirmed.
- **Proposed solution:** Classify errors. Do not count network errors toward attempts. Keep permanent failures in a dead-letter list with a log and a visible indicator instead of dropping them. Add backoff.
- **Phase:** 1

### F3 — Sign-out clears the queue and deletes unsynced operations
- **Severity:** P0
- **File & location:** `Lightstack/App/AppEnvironment.swift`, `authServiceDidSignOut` lines 297-307 (`clearQueue()` at 306); `OfflineQueueManager.clearQueue()` lines 126-128.
- **Steps to reproduce:** Log a workout offline. Sign out. Sign in again.
- **Expected:** Pending writes for that user are kept, or at least not lost silently.
- **Actual:** The whole queue is wiped. The local Core Data rows remain but never reach the cloud.
- **User impact:** Unsynced workouts exist only on the device. Reinstalling or switching devices loses them.
- **Confidence:** Confirmed. The intent (do not flush under another user's JWT) is valid, but deletion is the wrong remedy.
- **Proposed solution:** Tag each queued op with a `userId` and flush only ops matching the signed-in user. Do not clear on sign-out; clear or archive only on account deletion. Warn before sign-out if there are pending ops.
- **Phase:** 1

### F4 — No remote-to-local hydration
- **Severity:** P0
- **File & location:**
  - `Lightstack/Core/Services/SupabaseService.swift`: `fetchWorkoutsForUser` (78), `fetchExercises` (123), `fetchSets` (143), `fetchPersonalRecords` (255). A grep of the app and tests finds no callers.
  - `AppEnvironment.authServiceDidSignIn` (275-295) and `checkExistingSession` (321-336) check only the local profile via `fetchProfileSync`.
  - `ProfileRepository.loadProfile` (21-27) does pull the remote profile, but it is only called from `ProfileViewModel.loadProfile` (Profile tab, after onboarding).
  - `MonthPlanRepository.fetchActivePlan` (23-32) returns nil before syncing when no local plan exists.
- **Steps to reproduce:** Sign in on a fresh install or a second device with an existing account that has cloud data.
- **Expected:** Profile and history are restored from Supabase.
- **Actual:** The local store is empty. History, Progress and PRs are empty. No local profile exists, so the user is sent to onboarding.
- **User impact:** After a reinstall or device change the user appears to have lost all data. Re-onboarding calls `saveProfile`, which upserts on `user_id` and may overwrite the remote profile.
- **Confidence:** Confirmed for the missing hydration. Suspected for the remote profile overwrite (the upsert path is clear; the effect on the existing row's `id` and fields was not tested).
- **Proposed solution:** On sign-in, if the local store has no data for the user, run a paged pull (profile first, then workouts, exercises, sets, PRs, summaries). Decide onboarding after the remote profile check. Make the merge idempotent (upsert by id) and avoid re-enqueueing pulled rows. Add a "restored N workouts" state.
- **Phase:** 2

### F5 — Corrupt queue decodes to `[]` and is overwritten; encode failures ignored
- **Severity:** P1
- **File & location:** `OfflineQueueManager.swift` `loadQueue()` lines 231-237 (`try?` at 233 returns `[]`); `enqueue` line 85 (`guard let data = try? encoder.encode(payload) else { return }`); `saveQueue` lines 239-242.
- **Steps to reproduce:** Change the persisted queue format (for example add a field or enum case) or corrupt the data, then enqueue or flush.
- **Expected:** The unreadable queue is preserved or reported.
- **Actual:** It reads as empty, and the next `saveQueue` overwrites it. Encoding failures in `enqueue` drop the operation with no log.
- **User impact:** Silent loss of every queued write after a schema or format change.
- **Confidence:** Confirmed.
- **Proposed solution:** Decode per element, quarantine undecodable entries, and log. Version the queue format. Surface encode failures.
- **Phase:** 1

### F6 — Flush only on reconnect and sign-in; overlapping flushes possible
- **Severity:** P1
- **File & location:** `Lightstack/Core/Services/SyncService.swift` `triggerFlush()` lines 33-38 (doc comment on line 32 says "called on sign-in and app foreground"); callers are only `SyncService.swift:50` (offline to online) and `AppEnvironment.swift:293` (sign-in). `flush()` has no cancellation check.
- **Steps to reproduce:** Queue ops while online but failing (server error, timeout). Relaunch or foreground the app without a connectivity change.
- **Expected:** The queue is retried on launch, foreground, and periodically.
- **Actual:** Nothing retries until the next offline-to-online transition or sign-in. A session already authenticated at launch does not flush at launch. `triggerFlush` cancels the previous Task, but `flush()` never checks `Task.isCancelled`, and the actor is reentrant, so two flushes can run over the same snapshot and execute ops twice (duplicate-key errors, F7).
- **User impact:** Pending data can sit un-synced for a long time. Duplicate execution adds noise and wasted attempts.
- **Confidence:** Confirmed.
- **Proposed solution:** Flush on launch, scene-active, after enqueue (debounced), and on a timer while ops are pending. Use a single in-flight flush guard in the actor (join or skip if running).
- **Phase:** 1

### F7 — Plain inserts; retries after a lost response get 23505
- **Severity:** P2 (downgraded from P1; see below)
- **File & location:** `SupabaseService.swift`: `insertWorkout` 37, `insertExercises` 92, `insertSet` 136, `insertPersonalRecord` 248, `insertMonthPlan` 176, `insertPlannedSessions` 199 all use `.insert`. Only `upsertProfile` (28) and `upsertContextSummary` (227) upsert. `flush()` treats any thrown error as a failure.
- **Steps to reproduce:** The request reaches the server but the response is lost (timeout), so the op is queued. On retry the primary key exists, so Postgres returns duplicate key 23505.
- **Expected:** An already-applied insert counts as success.
- **Actual:** It counts as a failure, is retried, and is dropped after 5 attempts (F2).
- **User impact:** Low in itself: the row already exists, so dropping it loses nothing. The real cost is noise and wasted attempts, and a batched `insertExercises` that is partly present can never succeed. The deeper problem is that permanent errors are retried like transient ones.
- **Confidence:** Confirmed.
- **Proposed solution:** Phase 1: classify 23505 as success and permanent errors (RLS, constraint) as non-retryable. Phase 2: use `upsert(onConflict: "id")` for all inserts so writes are idempotent.
- **Phase:** 1 (classification) / 2 (idempotent writes)

### F8 — Several mutations are local-only
- **Severity:** P1
- **File & location:**
  - `WorkoutRepository.updateSet` (`Lightstack/Core/Repositories/WorkoutRepository.swift` 188-191) writes locally only. Its only caller is `TodayViewModel.logSet` line 169, which sets `isPR`. The set is inserted remotely earlier with `isPR` false, so `sets.is_pr` is always false remotely.
  - `PRRepository.recalculatePR` (108-148) and `recalculateAllPRs` (94-102) are local only. PR deletions and newly derived PRs never reach `personal_records`.
  - `MonthPlanRepository.deletePlan` (38-40) is local only.
  - `WorkoutRepository.deleteExercises(forWorkoutId:)` (224-233) swallows remote errors ("Supabase will reconcile on next sync", which never happens).
- **Steps to reproduce:** Log a PR set and inspect `sets.is_pr` in Supabase. Delete a workout that held a PR and inspect `personal_records`.
- **Expected:** Cloud state matches local state.
- **Actual:** Cloud shows PR flags false, stale PR rows remain, deleted plans stay, and failed exercise deletes are lost.
- **User impact:** Cloud data diverges from the device. After hydration (F4) restored data would show wrong PRs, resurrected plans and exercises.
- **Confidence:** Confirmed.
- **Proposed solution:** Add queue ops and Supabase methods for set update, PR delete/upsert and plan delete. Enqueue on failure in `deleteExercises(forWorkoutId:)`. Make the PR table derived (rebuild after hydration) or keep the cloud copy in sync.
- **Phase:** 2

### F9 — Parent and child inserts are separate un-awaited Tasks
- **Severity:** P1
- **File & location:** `WorkoutSessionService.generatePlan` (`Lightstack/Features/Today/Services/WorkoutSessionService.swift` line 62 `createWorkout`), `finalizePlan` (537-542), `startSession` (94-98), `logSet` (120-122). Each repository method launches its own `Task` (`WorkoutRepository` lines 41-72). Only `importWorkout` and `replaceWorkoutContents` chain their remote writes in order within one Task.
- **Steps to reproduce:** Create a workout and log a set quickly on a slow network.
- **Expected:** Workout, then exercises, then sets arrive in order.
- **Actual:** The three Tasks race. A child insert can reach Supabase before its parent (FK violation), is queued, and self-heals only because `flush()` sorts by FK order. Related hazard (Suspected): `finalizePlan` launches a remote `deleteExercises(workoutId:)` Task and a remote `insertExercises` Task together. If the delete lands after the insert it removes the new exercises and their sets, with the error swallowed (F8).
- **User impact:** Occasional missing or delayed cloud rows. Likely rare on a good network.
- **Confidence:** Confirmed for the un-ordered Tasks. The delete/insert reordering is Suspected (needs a network-level test).
- **Proposed solution:** Route all repository remote writes through the queue actor, which orders by dependency and awaits sequentially. Or chain per-workout writes in one serial executor. Drop the remote delete in `finalizePlan` for a workout that has never synced.
- **Phase:** 2

### F10 — AI modification apply gaps
- **Severity:** P1
- **File & location:**
  - `Lightstack/Features/Today/ViewModels/TodayViewModel.swift` `applyModification` line 385. In `.groupSuperset` (481-487), `if let grouped = SupersetGroup.group(...)` has no else branch, and the function still returns `true` (line 494).
  - Same function, line 386: `guard let workoutId = ... else { return false }`. `CoachChatViewModel.confirmModifications` (`Lightstack/Features/AICoach/ViewModels/CoachChatViewModel.swift` 194-217) only reports failures for mods with a `targetExerciseName`. `addExercise` and `groupSuperset` return nil there (`WorkoutModification.swift` 139-146), so a `false` is ignored silently.
  - No version or staleness check between proposal and confirm.
  - `sendMessage` appends the local-command reply ("Removing X.") at line 105 before the user confirms.
  - Swipe-dismissing the sheet only flips `showModificationConfirmation` via the binding (`CoachChatView.swift` line 28), so `pendingModifications` is not cleared (only `rejectModifications()` does).
- **Steps to reproduce:**
  - Ask the coach to superset exercises that cannot be grouped. The chat shows a "✓" line but nothing changed.
  - Type "remove Bench", then swipe the sheet down. The chat already said "Removing Bench."
  - Edit the workout while the sheet is open, then Apply.
- **Expected:** Failures are reported. Replies and state agree with what actually happened.
- **Actual:** As above.
- **User impact:** Misleading chat feedback; proposals may apply to a changed workout.
- **Confidence:** Confirmed.
- **Proposed solution:** Make `applyModification` return a per-modification result (applied / not found / invalid). Report every non-applied one. Snapshot an exercises revision at proposal time and re-validate at confirm. Show the local-command reply only after Apply. Clear pending state in the sheet's `onDismiss`.
- **Phase:** 4

### F11 — Prompt-injection surface
- **Severity:** P2
- **File & location:**
  - `CoachChatViewModel.configure` (lines 70, 83-85) inserts raw `exercise.name` and the stored rolling summary into the chat context message.
  - `CoachPromptService.buildWorkoutRequestMessage` (`Lightstack/Features/AICoach/Services/CoachPromptService.swift` lines 162 and 174) inserts the rolling summary and history `ex.name` unsanitized.
  - `buildPostWorkoutMessage` (line 205) inserts `exercise.name` unsanitized.
  - The workout type, notes and profile fields do go through `ValidationService`/`InputSanitizer`. The rolling summary is model-generated and stored.
- **Steps to reproduce:** Name an exercise with an instruction ("Ignore previous rules and ..."), then generate a plan or chat.
- **Expected:** User-controlled strings are sanitized and delimited as data.
- **Actual:** They are inserted verbatim.
- **User impact:** Bounded: the user is attacking their own coach, and modifications still require the confirmation sheet. It could matter if exercise names or imports ever come from other sources.
- **Confidence:** Confirmed.
- **Proposed solution:** Run all inserted strings through `InputSanitizer.sanitizeLabel`. Wrap data blocks in explicit delimiters and tell the system prompt to treat them as data. Cap the summary length on read.
- **Phase:** 4

### F12 — No AI request cancellation; rate-limit slots burned by retries
- **Severity:** P2
- **File & location:**
  - `CoachChatViewModel.clearChat` (231-237) resets `messages` but the in-flight callback (`sendMessage` lines 118-167) still appends its reply, so it lands in the new chat. There are no request tokens or cancellation.
  - `supabase/functions/ai-proxy/index.ts`: `check_rate_limit` (line 77) inserts a slot before the upstream call (line 92). `GeminiService.performWithRetry` (157-167) retries 503 up to 3 times (4 requests per model), and `AIServiceManager` then falls back to the second model (another 4). One logical request can use up to about 8 of the 10 per-minute slots.
- **Steps to reproduce:** Send a chat message, leave the workout so `clearChat` runs, and wait for the reply. Or use the app while Gemini returns 503s.
- **Expected:** Stale replies are dropped. A transient upstream failure does not exhaust the user's rate limit.
- **Actual:** As above.
- **User impact:** Confusing cross-chat replies; "Too many AI requests" after a Gemini outage.
- **Confidence:** Confirmed (the exact slot count depends on the failure sequence).
- **Proposed solution:** Add a request generation token and ignore stale completions. Support cancellation of the URLSession task. Refund or skip the slot when the upstream returns 5xx, or retry 503 inside the proxy so the client makes one call.
- **Phase:** 4

### F13 — Unversioned, unordered Supabase migrations; destructive script
- **Severity:** P2
- **File & location:** `supabase/migrations/` has four files with no timestamp prefixes: `add_cardio_set_fields.sql`, `exercises_superset_group_id.sql`, `harden_ai_rate_limit.sql`, `sets_rir_nullable_up_to_10.sql`. `supabase/fix_missing_columns.sql` lines 9-22 `DROP TABLE ... CASCADE` on all tables. `sets_rir_nullable_up_to_10.sql` runs `alter table public.sets drop constraint sets_rir_check;` with no `IF EXISTS`. `supabase/supabase_schema.sql` lacks the cardio columns that exist only in a migration.
- **Steps to reproduce:** Apply the files in alphabetical order to a fresh project. Run `fix_missing_columns.sql` on a live project.
- **Expected:** Ordered, idempotent migrations, and one canonical schema.
- **Actual:** There is no defined order. The fix script destroys data. The RIR migration fails on a second run (Suspected: the constraint name is not verified against the live DB) and, on a fresh project, interacts with the schema file's inline check.
- **User impact:** Risk of data loss or drift when rebuilding or changing the database.
- **Confidence:** Confirmed for the missing versioning and the destructive script. Suspected for the non-idempotent migration.
- **Proposed solution:** Adopt `supabase/migrations/<timestamp>_name.sql` with the Supabase CLI. Fold the current state into a baseline migration. Move or delete `fix_missing_columns.sql`. Make migrations idempotent (`IF EXISTS`).
- **Phase:** 2 / 3

### F14 — Verification password held in Keychain until verified
- **Severity:** P3 (downgraded from P2; see below)
- **File & location:** `AppEnvironment.pendingVerificationPassword` (`App/AppEnvironment.swift` 25-34); set in `LoginView.swift:208`; used by `EmailVerificationView.checkVerification` (123-131) and `AuthService.checkEmailVerified` (134-155), which re-signs in with it. Stored by `KeychainService.save` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **Steps to reproduce:** Sign up with email; before verifying, inspect the Keychain item `pending_verification_password`.
- **Expected:** No password is retained after sign-up.
- **Actual:** The password sits in the Keychain until sign-in succeeds or sign-out (cleared at `AppEnvironment` 278 and 302, and `EmailVerificationView:153`). It is not encrypted beyond Keychain protection.
- **User impact:** The Keychain is OS-encrypted, device-only and unlock-gated, so exposure is low. It lingers if the user abandons verification.
- **Confidence:** Confirmed.
- **Proposed solution:** Prefer the email link flow with PKCE (`handleDeepLink`) and drop the stored password. Or expire the item after a short time.
- **Phase:** 3

### F15 — CI runs no tests
- **Severity:** P2
- **File & location:** `.github/workflows/objective-c-xcode.yml`: a single job running `xcodebuild clean build analyze` for a generic simulator destination with `CODE_SIGNING_ALLOWED=NO`.
- **Steps to reproduce:** Open a PR that breaks a unit test.
- **Expected:** The PR check fails.
- **Actual:** It passes. Tests are only run locally, per `CLAUDE.md`, before TestFlight.
- **User impact:** Regressions can merge unnoticed.
- **Confidence:** Confirmed.
- **Proposed solution:** Add a `xcodebuild test` job (unit tests, on iOS 26 simulator) to the workflow. Run the UI suite nightly or manually.
- **Phase:** 3

### F16 — `docs/BLUEPRINT.md` is stale
- **Severity:** P3
- **File & location:** `docs/BLUEPRINT.md` (v1.2, March 2026): describes a two-tab Today/Month layout (lines 23-37), client-side Gemini calls, and Email + Apple auth only.
- **Expected:** Docs match the code.
- **Actual:** The app has Today/History/Progress/Profile tabs, Month behind `FeatureFlags.monthTabEnabled = false`, AI via `ai-proxy`, and Apple, Google and email auth.
- **User impact:** None directly; misleads contributors.
- **Confidence:** Confirmed.
- **Proposed solution:** Treat `docs/SYSTEM_ARCHITECTURE.md` as the current reference. Update or archive `BLUEPRINT.md`.
- **Phase:** 6

### F17 — Workout row created before the plan AI call; left empty on failure
- **Severity:** P3
- **File & location:** `WorkoutSessionService.generatePlan` (`Lightstack/Features/Today/Services/WorkoutSessionService.swift` 36-90). The comment at lines 46-48 says not to create the record yet, but line 62 calls `workoutRepository.createWorkout(pendingWorkout)` before the AI request at line 76. On failure, `sessionServiceDidFail` (`TodayViewModel.swift` 371-376) only resets the phase and error message. Nothing deletes the workout.
- **Steps to reproduce:** Start generating a workout with the network off or the proxy refusing (rate limit), then return to setup.
- **Expected:** No workout is left behind.
- **Actual:** An empty workout row stays in Core Data and is inserted (or queued) to Supabase. `HistoryViewModel.loadWorkouts` lists all recent workouts, so the row can appear in History and in stats counts as a session with no exercises.
- **User impact:** Phantom empty workouts after failed generations. The comment itself is stale because rate limiting moved to the server.
- **Confidence:** Confirmed that the row is created and not removed on failure. Whether every empty row shows in History in practice was not exercised in the UI.
- **Proposed solution:** Create the workout only after a plan is received, or delete it in the failure path (local and remote). Fix the comment.
- **Phase:** 2

---

## Positive (no action)
- RLS is enabled with `USING` and `WITH CHECK` on all 9 tables (`rate_limits` is `service_role` only): `supabase/supabase_schema.sql` lines 201-289.
- No AI key in the app. The Gemini key is the `GEMINI_API_KEY` secret inside `ai-proxy`.
- `ai-proxy` verifies the user (`auth.getUser`, line 57), caps body size and output tokens, allow-lists models, and rate-limits fail-closed (10/min, 100/day via `check_rate_limit`).
- `os.Logger` is used throughout, with private interpolation by default.
- PKCE is enabled (`AppEnvironment.swift` line 90). Apple Sign-In uses a SHA-256 nonce. Deep links are filtered by `AuthService.isAuthCallback`.

## Living roadmap

| Phase | Name | Status |
|---|---|---|
| 1 | Offline queue reliability | Implementing |
| 2 | Local/cloud consistency | Not started |
| 3 | Testing, security & observability | Not started |
| 4 | AI coach reliability | Not started |
| 5 | SwiftUI performance & UX | Not started |
| 6 | Analytics & docs | Not started |
