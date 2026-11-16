# Production-readiness hardening: status after merging the current app (2026-11-16)

Branch `claude/production-readiness-hardening` (PR #76). Nothing here has been deployed, pushed or run against Supabase. Everything below was done and tested locally.

## 1. What the branch contains now

- Everything from `origin/claude/audit-client-fixes` (main + gym-side redesign + new sign-in/first-run screens with in-app Terms/Privacy + audit fixes: offline sign-out, store recovery, PrivacyInfo.xcprivacy).
- Hardening from the original branch: in-app account deletion (`delete-account` edge function), AI consent gate and Settings switch, hardened `ai-proxy` (task table, budgets, ledger, kill switch, idempotent request ids), RLS/privilege migrations, local-data protection, sync fixes, AI failure UX, docs.

## 2. What changed during the merge, and why

| Area | Resolution |
|---|---|
| `project.pbxproj` | Took the incoming side, then `xcodegen generate`. |
| `SettingsView` | Kept this branch's Privacy section (AI consent toggle + footer) and delete-account; added the incoming Legal section (Privacy Policy, Terms of Use rows open the in-app `LegalView`). The old privacy row and the `PrivacyInfoView` summary screen were removed so there is one Privacy Policy entry. The `PrivacyPolicy.url` / `LSPrivacyPolicyURL` helper is kept for when a public URL exists (Info.plist does not have the key yet). The consent sheet's policy link now opens `LegalView`. Consent and delete sheets use the new system-font look instead of Playfair. |
| `AuthService` | Took the incoming `performSignOut` (always completes locally, `remoteSignOutOverride` seam) and `finishSignOut`; kept this branch's session-cache clearing in it. Account deletion still ends in `finishSignOut`. |
| `GeminiService` | Kept the incoming per-attempt deadline / failover (`finish(...)`) and this branch's proxy error codes, so budget refusals still get friendly messages. |
| `CoachDebugStore` | Kept this branch's Release redaction of the user message and the incoming new fields (scorecard, nutrition/meals shared, fuel/meals blocks). |
| `CoachPromptServiceTests` | Kept both tests (data minimisation and decision prompt). |
| `docs/legal/PRIVACY_POLICY.md` | Single source shown in-app. Account deletion paragraph now says deletion is in the app (Settings, Delete account); AI section describes the consent switch. Placeholders untouched. `docs/privacy/PRIVACY_POLICY_DRAFT.md` is now a short pointer to it. |
| `PrivacyInfo.xcprivacy` | The incoming manifest in `Lightstack/Resources` is the live one; it already declares every data type in this branch's template (verified side by side). The template stays as documentation. |
| `ai-proxy` | `formFeedback` now accepts ONE jpeg/png image (the contact sheet the app sends, about 400 KB), 3000 output tokens, thinking up to `low`, reserve $0.015 (was text only, 600 tokens, minimal: it would have rejected the new form-coach feedback). `mealEstimate` already allowed one image and Google Search. Tests extended. |
| `delete-account` | Now also clears `food_collection_items`, `food_collections`, `weigh_ins` (kitchen and weigh-in tables added to main after this function was written; they cascade on user delete anyway, this is belt and braces). |
| New migration | `20261116120000_revoke_truncate_late_tables.sql`: the kitchen and weigh-in tables were created after the privilege hardening and got `GRANT ALL` to `authenticated`, including TRUNCATE, which ignores RLS. The migration revokes it. Not run against any Postgres (none available locally). |
| UI test | `HardeningChecksTests` now looks for the Privacy Policy row id `settings.privacy`. |

Consent gate: it is central, in `AIServiceManager.generateReply` (`generateChat` calls it). Every AI entry point goes through the manager: coach chat, plan decisions, month plan, post-workout (including Freestyle review), form-coach feedback, nutrition meal estimate and photo, and coach-with-meals. No entry point calls a provider directly. Denied consent returns `AIConsent.deniedError`. UI-test mode starts with consent granted (use `-uiTestingNoAIConsent` to see the prompt).

## 3. Test results

All on iPhone 17 simulator, local, no backend.

- Build: `xcodebuild build-for-testing` EXIT=0, no errors.
- Unit suite: 1405 tests, 1 skipped, 0 failures, EXIT=0.
- UI classes (AuthRedesignTests, BackupStatusTests, RestoreFreshInstallTests, SignOutWarningTests, StoreRecoveryTests, RelaunchTests, TabNavigationTests, WorkoutFlowTests, CoachChatTests, plus this branch's HardeningChecksTests and DeleteAccountSheetTests): 42 tests in the first run, 41 passed, 1 failed.
  - Failed: `HardeningChecksTests.testAIFailureShowsRetryAndBuildManually`. Cause: stale test, not a bug. After the gym redesign an AI failure no longer blocks plan building (the engine plan opens, marked "engine only"), so the old "Error" alert never appears. Replaced by `testAIFailureStillBuildsEnginePlan`, which passed.
  - `HardeningChecksTests.testSettingsAIToggleAndPrivacyPolicyRow` failed once (toggle tap not registered by the simulator) in the rerun of the whole class and passed when rerun alone.
  - After the fixes: all 4 HardeningChecksTests passed (3 in the class rerun, 1 rerun alone). The other classes were not rerun, as nothing they cover changed after their pass.
- ai-proxy tests: 17 passed, 0 failed (Node with a small Deno shim; there is no Deno here).
- Not run: SQL tests (no Postgres), the real proxy against Gemini, the delete-account function, UI classes outside the requested set (Nutrition, Form, Coach V2 etc.).

## 4. Backend deploy checklist (owner, in order, do not reorder)

Nothing in this list has been run. Step 0 is read-only and decides which migrations are really pending.

0. **Check what is live (read-only).** Supabase dashboard, Database, Migrations (or MCP `list_migrations`). Compare with `supabase/migrations/`. The original handoff listed only three pending nutrition migrations, but the repo now also has `20261103`, `20261104`, `20261108`, `20261110`. Apply every file that is missing, in filename order. Verify: the list matches the folder. Rollback: n/a.
1. **Take a backup.** Dashboard, Database, Backups (confirm a recent one exists), plus a manual dump: `pg_dump "$DATABASE_URL" --format=custom --file=lightstack-pre-hardening.dump` (connection string from Project Settings, Database). Verify: `pg_restore --list lightstack-pre-hardening.dump | head` shows tables. Rollback: n/a. Do not continue without it.
2. **Apply the missing nutrition migrations** (from step 0), one at a time, SQL editor or `supabase db push` after reviewing the dry run. Additive and idempotent. Verify: `list_migrations`; tables exist. Rollback: restore the dump (there are no down scripts for these).
3. **Apply `20261105120000_rls_views_security_invoker.sql`.** *Changes privileges:* revokes anon access and TRUNCATE on all tables, pins function search paths, tightens policies. It can break any client that relied on anon access or on views running as owner (the app does not). Then run `supabase/tests/rls_boundaries.sql` in the SQL editor (rolls back by itself); expect only `RLS OK` lines, no `RLS FAIL`. Verify afterwards: `select count(*) from auth.users where email like 'rls-test-%@invalid.test';` is 0, and sign in on a test build and open History, Progress, Nutrition. Rollback: restore from the dump (privileges revoked by the migration would otherwise be re-granted by hand).
4. **Apply `20261116120000_revoke_truncate_late_tables.sql`** (new, from this merge; after the 1108 and 1110 migrations exist). Same kind of change as step 3 for three tables. Verify: `select grantee, privilege_type from information_schema.role_table_grants where table_name in ('weigh_ins','food_collections','food_collection_items') and grantee in ('anon','authenticated');` shows no TRUNCATE/TRIGGER/REFERENCES and nothing for anon. Rollback: `GRANT TRUNCATE ON ... TO authenticated` (not recommended).
5. **Apply `20261105130000_ai_usage_ledger_budgets.sql`.** Creates `ai_budget_config` (one row), `ai_usage_ledger` (rows cascade-delete with the user), `ai_reserve`/`ai_settle`. Then set REAL prices and limits (see `docs/ai/AI_COST_CONTROLS.md`: the seeded numbers are placeholders and the 3.5-flash prices are a guess). The proxy fails closed (503 `budget_unavailable`) if this step is missing, so do it BEFORE step 7. Verify: `select * from ai_budget_config;`. Run `supabase/tests/ai_budget.sql` only if you are comfortable with it; it was only ever run on scratch Postgres, so prefer not to run it on production. Rollback: kill switch `update ai_budget_config set ai_enabled=false;`; dropping the objects is destructive to the ledger.
6. **Set edge function secrets** (dashboard, Edge Functions, Secrets, or `supabase secrets set`): `AI_ALLOW_LEGACY_CLIENTS=1` (until old builds age out), optional `AI_MODEL_ROUTING=1`; for Sign in with Apple revoke: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_CLIENT_ID`. `SUPABASE_SERVICE_ROLE_KEY` is provided automatically. Verify: secrets list shows the names. Rollback: unset the secret.
7. **Deploy `ai-proxy`.** *Replaces the live function; irreversible unless you keep the old source.* First save the current live source (dashboard, Edge Functions, ai-proxy, download, or `supabase functions download ai-proxy`). Then `supabase functions deploy ai-proxy`. This is the v4 proxy: coach v3 + meal estimates + form-feedback image + all budget controls; never deploy main's older `index.ts` over it. Verify: from a TestFlight build, chat, build a plan, log a meal by photo, run form feedback; then `select task, status, count(*), sum(actual_usd) from ai_usage_ledger group by 1,2;` shows rows. Rollback: redeploy the saved old source (it ignores the ledger; budgets then stop applying).
8. **Deploy `delete-account`.** `supabase functions deploy delete-account` (keep JWT verification ON). Verify with a throwaway account: Settings, Delete account; the user disappears from Authentication and its rows from every table. **Test only with a throwaway account: account deletion is irreversible.** Rollback: redeploy removes nothing already deleted; if the function misbehaves, delete it (the app then shows an error and keeps local data).
9. **Google Cloud:** set a billing budget alert and a Generative Language API quota cap (`docs/ai/AI_COST_CONTROLS.md`). Verify in the console. Rollback: n/a.
10. **App side (not backend):** add `LSPrivacyPolicyURL` to Info.plist once a policy is published; fill the placeholders in `docs/legal/*.md`; ship the build. Existing users see the consent sheet once.

Irreversible or destructive steps: 3 and 4 (privileges), 7 (replaces live function), 8 (users who delete are gone for good; the function itself is safe), and any dropping of the ledger. Steps 1 and 0 are what make the rest recoverable.

## 5. Things I believe are wrong, unfinished or risky

- **Nothing here was exercised against a real Supabase.** The SQL (the original two test files plus my new migration) has not been run in this work; there is no local Postgres. The proxy tests ran under Node with a small Deno shim (17 pass); the real `index.ts` request path (auth, reserve, Gemini call) was not run.
- `rls_boundaries.sql` does not cover `food_collections`, `food_collection_items`, `weigh_ins`; extend it before trusting the live run.
- `formFeedback` and `mealEstimate` reserve amounts are estimates; `gemini-3.5-flash` prices in the seed are a guess.
- Input caps may be tight for the new coach inputs: `chat` allows 60,000 chars and `plan` 150,000; the coach now also receives meal and fuel blocks, scorecards and decision context. A 413 `input_too_large` would show as a coach failure. Watch the first TestFlight runs.
- The Privacy and Terms texts are drafts with placeholders and no legal review. `LSPrivacyPolicyURL` is not set; App Store needs a public URL.
- Sign in with Apple revoke is best-effort; App Review may require it. Account deletion is cloud-first: if the cloud call fails local data stays and the user must retry.
- The ledger is deleted with the user (`ON DELETE CASCADE`); decide if billing needs it kept.
- No data export (GDPR/CCPA), no pause-sync API before deletion, one-device last-write-wins, offset paging in restore, Swift 6 concurrency warnings (original P1/P2 list still stands).
- Commits: the merge commit also contains the settings/proxy/policy-doc edits made while resolving the merge. The delete-account table list, the new migration, the test change and this document are in a second local commit.
