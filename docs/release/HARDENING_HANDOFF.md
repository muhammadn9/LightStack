# Production-readiness hardening: handoff

Branch: `claude/production-readiness-hardening`, built from `main` at 8f44149. No PR has been opened and nothing has been merged.

**Status: nothing on this branch has been compiled yet.**
- The work was done on Linux, where `xcodebuild` is not available.
- A read-only compile review found no errors. The first real build is still the Mac or CI run.
- The SQL tests ran against a local Postgres 16 with stubbed Supabase roles:
  - `rls_boundaries.sql`: 274 RLS OK
  - `ai_budget.sql`: 23 checks OK, plus a 6-session concurrency test
- The ai-proxy tests ran under Node with a Deno shim (10 ok).
- Nothing has been deployed.

## What changed

| Area | Summary | Detail doc |
|---|---|---|
| Database security | Views run as the caller (`security_invoker`). Least-privilege grants: nothing for anon, no TRUNCATE. Policies check that cross-user parent rows belong to the caller. Functions use a pinned `search_path`. | `docs/security/DB_AUDIT.md` |
| AI spending | Server-owned limits per task, a usage ledger, per-user and global daily/monthly dollar budgets, an in-flight cap and a kill switch. Request ids are idempotent, media and file parts are rejected, and timeouts are charged. | `docs/ai/AI_COST_CONTROLS.md` |
| Cost model | Cost for 100, 1k and 10k users, plus a pricing recommendation. | `docs/ai/AI_COST_MODEL.md` |
| Account deletion | Settings → Delete account. The `delete-account` edge function verifies the caller. Then the queue is purged, local data is wiped and the user is signed out. Sign in with Apple token revoke is best-effort. | `docs/privacy/ACCOUNT_DELETION_SETUP.md` |
| Privacy | Privacy Policy row, AI consent sheet and Settings toggle. Every AI request is blocked until the user consents. The display name is no longer sent to the AI. Includes a data inventory and a DRAFT policy. | `docs/privacy/*` |
| Local data | Core Data and queue files are protected until first unlock. AI debug snapshots are redacted in Release. Session caches are cleared on sign-out. Local data is wiped on sign-out when nothing is queued. | `docs/security/LOCAL_DATA_AUDIT.md` |
| Sync | Queue purge for account deletion. Nothing gets recreated after deletion. Ownerless ops no longer leak to the next account. Fixes rest-day ordering. Adds a retry timer. | `docs/reliability/SYNC_AUDIT.md` |
| UX | AI failures show friendly text, Retry, and a "Build manually" option. | `docs/release/UX_AUDIT.md` |
| Compliance | App Review gaps and a release checklist. | `docs/release/APP_REVIEW_COMPLIANCE.md`, `RELEASE_CHECKLIST.md` |

## Deploy order (do not reorder)

1. Back up the Supabase database.
2. Apply the pending nutrition migrations. The live database is behind the repo: `20261026120000`, `20261030120000`, `20261102120000`.
3. Apply `20261105120000_rls_views_security_invoker.sql`. Then run `supabase/tests/rls_boundaries.sql` against the live database (it rolls back). Expect only `RLS OK` lines.
4. Apply `20261105130000_ai_usage_ledger_budgets.sql`. Then fill in real Gemini prices and limits in `ai_budget_config`; the seeded values are placeholders.
5. Set the edge function secrets:
   - `SUPABASE_SERVICE_ROLE_KEY` (usually present already)
   - `AI_ALLOW_LEGACY_CLIENTS=1` until old builds age out
   - optional: `AI_MODEL_ROUTING=1`
   - for Sign in with Apple revoke: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_CLIENT_ID`
6. Deploy the edge functions with `supabase functions deploy ai-proxy` and `supabase functions deploy delete-account`.
   - The proxy fails closed (503 `budget_unavailable`) if step 4 is missing.
7. Add the Info.plist key `LSPrivacyPolicyURL` with the published policy URL.
8. Add `PrivacyInfo.xcprivacy` from `docs/release/PrivacyInfo.xcprivacy.template`, then run `xcodegen generate`.
9. In Google Cloud, set a billing budget alert and a Generative Language API quota cap. See `AI_COST_CONTROLS.md`.
10. Ship the app build. Existing users will see the AI consent sheet once.

## Conflicts with open PRs

The coach PRs (#65, #68, #71–#74) also edit these files:
- `ai-proxy/index.ts`
- `AIRequestOptions.swift`
- `GeminiService.swift`
- `CoachPromptService.swift`
- `TodayViewModel.swift`
- `CoachChatViewModel.swift`

Whichever merges second needs a careful merge. #68 changes the proxy's thinking limits, so the new `tasks.ts` must also allow `medium` for the plan task.

## Remaining work

- **P0:**
  - Build and run the unit and UI suites on the Mac.
  - Publish a legally reviewed privacy policy.
  - Run the deploy steps above.
  - Verify the live RLS test.
  - Set real Gemini prices.
  - Decide whether Sign in with Apple revoke must be required rather than best-effort (App Review).
- **P1:**
  - Keep the AI ledger after account deletion for billing (`ON DELETE SET NULL`)?
  - Add a pause-sync API before account deletion.
  - Raise the legacy/plan cost reservations toward the worst case.
  - Stop returning Gemini error text to the client.
  - Add data export (GDPR/CCPA).
  - Turn off form analysis for 1.0 (marked unvalidated).
  - Fix the kg setting not being applied.
  - Paywall or StoreKit (the cost model recommends $6.99/month).
- **P2:**
  - Restore uses offset paging.
  - Two-device sync conflicts resolve as last-write-wins.
  - Swift 6 concurrency warnings.
