# Launch Checklist

Date: 2026-11-05. Tick items in order; each section lists a verification step. Items marked **(gap)** are required work found in the audits (`docs/release/APP_REVIEW_COMPLIANCE.md`, `docs/release/UX_AUDIT.md`, `docs/ai/AI_COST_MODEL.md`) that does not exist yet.

## 0. Code gates before anything ships

- [ ] **(gap)** Account deletion, AI consent screen, privacy policy links, `PrivacyInfo.xcprivacy` (compliance doc #1-#5).
- [ ] **(gap)** AI failure UX: retry and friendly messages (UX audit #1, #2); kg/lbs setting fixed or hidden (UX #3).
- [ ] Decision on `FeatureFlags.formAnalysisEnabled` (UX #12). `monthTabEnabled` stays `false`.
- [ ] Build passes: `xcodebuild build` EXIT=0; unit tests pass; full UI suite passes (per CLAUDE.md).
- [ ] No DEBUG-only code reachable in Release (`#if DEBUG` sections, `-uiTesting` args). Archive and smoke test the Release build, not just Debug.
- [ ] Lock package versions (Supabase is `from: "2.0.0"`); commit resolved `Package.resolved`.

## 1. Supabase migrations (apply in this order, once each, staging first)

Source of truth is `supabase/migrations/`; `supabase_schema.sql` is a snapshot. Rules in `supabase/migrations/README.md`: additive, idempotent, no explicit BEGIN/COMMIT. Never run anything in `supabase/dangerous/`.

1. [ ] Take a backup (dashboard backup or `pg_dump`) and note the restore point.
2. [ ] Compare `list_migrations` in the target project with the files; apply only the missing ones, in filename order:
   1. `20261003000635_sets_rir_nullable_up_to_10.sql`
   2. `20261004025842_exercises_superset_group_id.sql`
   3. `20261015120000_phase2_sync_consistency.sql` (down script: `rollback/20261015120000_phase2_sync_consistency_down.sql`)
   4. `20261019120000_refund_rate_limit.sql` (needed by the proxy refund path; the proxy tolerates it missing but then does not refund failed calls)
   5. `20261022120000_exercise_is_per_arm.sql`
   6. `20261026120000_nutrition_tables.sql`
   7. `20261030120000_nutrition_journal.sql`
   8. `20261102120000_nutrition_goals_plans.sql`
   9. `20261103120000_nutrition_food_barcode.sql`
3. [ ] **(gap)** New migrations to write and apply before launch (suggested names): `ai_usage` table (per-call tokens and cost), per-user monthly budget and cost-weighted `check_rate_limit`, `ai_consent` columns/table, `account_deletion` support (cascades or a delete function), subscription entitlement table.
4. [ ] Do NOT apply `legacy/*` files (`harden_ai_rate_limit_MANUAL.sql` is manual; its header says why).
5. [ ] Run `supabase/tests/rls_boundaries.sql` and confirm every user table has RLS enabled; run the Supabase advisors (security and performance) and fix warnings.
6. [ ] Confirm `check_rate_limit()` and `refund_rate_limit` are not executable by `anon`/`authenticated` where intended (`REVOKE ... FROM PUBLIC, anon`, refund callable only by service role).
7. [ ] `list_migrations` matches file names afterwards.

## 2. Edge function deploys

- [ ] Deploy `ai-proxy` (`supabase functions deploy ai-proxy`; JWT verification must stay on, the function also re-checks `auth.getUser`).
- [ ] **(gap)** Update `ai-proxy` before launch: add flash-lite models to `ALLOWED_MODELS`, server-side per-task model and thinking caps (raise `MAX_THINKING_BUDGET` only if coach-v3 medium thinking ships), read `usageMetadata` and write `ai_usage`, enforce consent and entitlement, tighten `MAX_BODY_CHARS`.
- [ ] **(gap)** Deploy `delete-account` function.
- [ ] Smoke test with a real session JWT: 200 with valid body; 400 on bad model/thinking config; 401 without JWT; 429 after the limit; 504 on slow upstream and slot refunded.
- [ ] Note the previous deployed function version so rollback is one command.

## 3. Secrets and environment variables

Set in Supabase > Edge Functions > Secrets (never in the repo or app bundle).

| Name | Used by | Notes |
|---|---|---|
| `GEMINI_API_KEY` | ai-proxy | Key from a **dedicated Google Cloud project** with billing (paid tier, so prompts are not used for model training). Restrict to the Generative Language API. Rotate on any leak. |
| `SUPABASE_SERVICE_ROLE_KEY` | ai-proxy refund, delete-account | Auto-provided to functions; never ship in the app. Without it refunds are skipped with a warning. |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | ai-proxy | Auto-provided. |
| `APPLE_TEAM_ID` | delete-account | **(gap)** For Sign in with Apple revoke. |
| `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (.p8 contents) | delete-account | **(gap)** Key with Sign in with Apple enabled. |
| `APPLE_CLIENT_ID` | delete-account, Supabase Apple provider | Bundle ID (native) or Services ID. |
| Google OAuth client IDs | Supabase Google provider; app `Info.plist` | Web client ID in Supabase; iOS client ID in app. |

- [ ] Supabase Auth settings: Site URL and redirect URLs, email confirmation on, SMTP configured (custom sender, not the shared low-rate default), password-reset template tested, Apple and Google providers enabled with correct IDs.
- [ ] CI/TestFlight secrets: `scripts/asc-config.sh` (`ASC_APP_ID` and API key) present for `scripts/testflight-release.sh`.

## 4. Google Cloud: budget alerts and quota caps

Budgets only alert; quotas actually stop spend. Do both.

- [ ] Billing budget on the Gemini project: alerts at 50%, 90%, 100% and 150% of expected monthly spend (cost model: 1,000 users is about $80-200/month). Email at least two people.
- [ ] Pub/Sub budget notification that can disable billing or flip a kill-switch row (optional but recommended).
- [ ] API quotas for Generative Language API: requests per minute and tokens per minute per project set to about 3x peak launch traffic; per-model limits for 3.5-flash lower than 2.5-flash.
- [ ] API key restrictions: API restricted to Generative Language; key stored only as the function secret.
- [ ] Alert on spend anomalies (daily spend more than 3x trailing average).
- [ ] Global app-level kill-switch row checked by the proxy (**gap**), tested.

## 5. App Store Connect

- [ ] App record, bundle ID, SKU, category (Health & Fitness), age rating questionnaire (note AI-generated content; fitness/nutrition guidance).
- [ ] **Privacy policy URL** entered (published at a stable HTTPS URL; also linked in-app). Also support URL and marketing URL.
- [ ] **App Privacy labels** completed per the mapping in `APP_REVIEW_COMPLIANCE.md` section 2 (email, name, health, fitness, user content, user ID; linked; no tracking).
- [ ] Export compliance: `ITSAppUsesNonExemptEncryption=false` already set.
- [ ] App Review Information: demo account credentials, notes explaining AI processing by Google Gemini, where consent appears, how to delete an account, camera processed on device.
- [ ] Sign in with Apple capability enabled for the App ID; Apple Developer key created for revoke.
- [ ] Screenshots, description without medical claims, "What to test" text for TestFlight.
- [ ] If subscriptions: products, agreement and tax forms, subscription group, localized price, Terms link.

## 6. TestFlight beta plan

1. [ ] Internal testers (you): full manual pass on a physical device, including airplane mode generation failure, kg setting, delete account, consent decline path, sign in with Apple and Google, sign-out with unsynced changes.
2. [ ] Run the whole UI suite and unit tests, then `scripts/testflight-release.sh --skip-tests` (bumps build number; build numbers must never repeat; commit the bump afterward).
3. [ ] External group A (10-25 trusted users), 1 week. Success criteria: crash-free sessions above 99.5%, plan generation success above 97%, median plan latency under 15s, no data-loss reports, measured cost per active user within 2x of the model in `AI_COST_MODEL.md`.
4. [ ] Review `ai_usage` costs and replace estimates with measured token counts.
5. [ ] External group B (100-300) with the free-tier limits on, 1-2 weeks. Collect crash logs via the Share flow (`scripts/asc_api.py`, `betaFeedbackCrashSubmissions`).
6. [ ] Beta App Review submitted early (external TestFlight triggers a review that checks the same privacy items).
7. [ ] Release candidate build frozen; no schema or proxy changes in the final 48 hours without a rollback plan.

## 7. Monitoring

- [ ] Supabase logs: edge function error rate, 4xx/5xx split, p95 latency, 429 counts (use `get_advisors` and the logs views); alert if 5xx above 3% for 10 minutes.
- [ ] Daily AI spend dashboard from `ai_usage` (**gap**): cost by model, task, and the top 20 users.
- [ ] Gemini upstream errors (503/429) surfaced separately from our own rate-limit errors.
- [ ] Database: connection count, storage growth, advisor warnings weekly.
- [ ] Client: Xcode Organizer crashes and TestFlight crash feedback checked daily in the first two weeks; in-app Diagnostics export covers support.
- [ ] Uptime check on the proxy health path or a synthetic daily plan-generation call.
- [ ] Support inbox and on-call owner named for launch week.

## 8. Rollback

| Layer | Rollback |
|---|---|
| App binary | Cannot be recalled from users; stop phased release in App Store Connect (pause), ship a fixed build, use server kill-switch flags for features. Keep the previous build available in TestFlight. |
| Feature flags | Currently compile-time (`FeatureFlags.swift`). **(gap)** Move form analysis and AI features behind server config so they can be disabled without a release. |
| Edge function | Redeploy the previous function version (keep the prior `index.ts` tagged in git). The proxy fails closed, so an outage degrades to "AI unavailable" while logging, history, and sync keep working. |
| Migrations | Additive only. Use `supabase/migrations/rollback/*_down.sql` (safe statements active; column/table drops are commented out). For anything destructive, restore from the pre-migration backup instead. |
| Cost runaway | Flip the global kill-switch row; lower the Google quota; if needed rotate or delete `GEMINI_API_KEY` (all AI fails closed). |
| Bad auth config | Revert Supabase Auth provider settings; sessions remain valid because JWT secret is unchanged. |
| Data incident | Point-in-time restore of Supabase to the pre-launch restore point; communicate via in-app banner and email. |

## 9. Launch day

- [ ] Phased release for automatic updates on (7-day phased rollout).
- [ ] Watch the dashboards in section 7 for the first 24 hours; review cost at 24h, 72h, 7d against `AI_COST_MODEL.md`.
- [ ] Re-evaluate free-tier limits and routing after one week of real usage.
