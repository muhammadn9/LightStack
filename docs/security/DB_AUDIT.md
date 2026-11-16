# Database security audit

Date: 2026-11-05. Scope: `supabase/supabase_schema.sql`, `supabase/migrations/**` (incl. `legacy/`, `rollback/`), `supabase/tests/`, and a read-only catalog comparison against the live project `Gym-App-DB` (`tzyjfgcasifincmfnerj`).
Fix: `supabase/migrations/20261105120000_rls_views_security_invoker.sql`. Tests: `supabase/tests/rls_boundaries.sql`.

## Findings

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | Views `user_streaks`, `recent_workouts_summary`, `month_plan_progress` are created without `security_invoker` in the schema snapshot. A view owned by `postgres` bypasses RLS, so with Supabase default grants any signed-in user (and anon) could read every user's rows. | High if present | **Live: already `security_invoker=on`** (not exploitable today). **Repo drift**: no file in the repo sets it, so a rebuild from the repo reintroduces the leak (reproduced on a scratch DB: A saw 2 rows). Fixed in migration. |
| 2 | Views are granted `ALL` (incl. INSERT/UPDATE/DELETE/TRUNCATE) to `anon` and `authenticated`. RLS on the base tables limits the damage, but anon should have nothing. Two of the three views are unused by the app. | Medium | **Confirmed live**. Fixed. |
| 3 | Every public table grants all privileges (incl. `TRUNCATE`, `TRIGGER`, `REFERENCES`) to `anon` and `authenticated` (Supabase default privileges). `TRUNCATE` ignores RLS, so any holder of the role over a direct SQL connection could wipe a table. PostgREST does not expose TRUNCATE, so this is defence in depth. `sync_tombstones` and `rate_limits` are also over-granted (RLS is the only gate). | Medium | **Confirmed live**. Fixed. |
| 4 | Cross-user foreign keys: policies on `planned_sessions`, `personal_records`, `food_entries` check only `user_id`. FK checks bypass RLS, so user B can insert/update a row (with B's `user_id`) whose `month_plan_id`, `workout_id`, `food_id` or `meal_slot_id` points at user A's row. No data is read back, but it can pollute A's `month_plan_progress` aggregates (when views run as owner), leaks existence of A's ids by FK error vs success, and breaks A's deletes (`ON DELETE SET NULL` is fine, but plan cascade removes B's rows). Previously documented as "known low-risk gap". | Low-Medium | **Confirmed live** for `planned_sessions`, `personal_records`, `food_entries.food_id` (policies identical to repo); `meal_slot_id` not testable live (column absent). Reproduced locally. Fixed. |
| 5 | SECURITY DEFINER functions `check_rate_limit`, `refund_rate_limit` use `SET search_path = public` without `pg_temp`, so `pg_temp` is searched first for relations. Practically hard to exploit (callers can create temp tables, the function writes `rate_limits`, `INSERT` into a shadowing temp table would skip the quota). | Low-Medium | **Confirmed live** (`proconfig = search_path=public`). Fixed (`public, pg_temp`). |
| 6 | RPC identity: `check_rate_limit()` takes no user argument and uses `auth.uid()`, so a caller cannot act on another user. `refund_rate_limit(p_user_id, ...)` accepts any id by design but is `service_role`-only live (`proacl = postgres, service_role`). `anon` has no EXECUTE on either. | Info | **Confirmed OK live**. Tests added to keep it that way. |
| 7 | Nutrition tables (`nutrition_targets`, `foods`, `food_entries`, `meal_slots`, `water_entries`, `day_notes`, `nutrition_goal_settings`, `nutrition_plans`): RLS enabled, one `FOR ALL` policy with `USING` and `WITH CHECK` `auth.uid() = user_id`, which covers SELECT/INSERT/UPDATE/DELETE. | Info | Repo OK; live OK for the tables that exist. |
| 8 | **Live is behind the repo**: `meal_slots`, `water_entries`, `day_notes` and `food_entries.meal_slot_id` (migration `20261030120000`) do not exist live. Live `schema_migrations` only lists 5 versions; many earlier migrations were applied outside the history. | Operational | Confirmed live. See deploy steps. |
| 9 | Live has tables not in the repo: `all_time_prs` (RLS: SELECT/INSERT own only) and `muscle_groups` (SELECT for authenticated, `true`). Legacy; privileges revoked from anon by the migration's loop. | Info | Confirmed live. Consider documenting or dropping later (not done: no drops in migrations). |
| 10 | `workouts.planned_session_id` has no FK, so it can hold any uuid. Exposes nothing. | Info | Repo-only, not changed. |
| 11 | RLS policies apply to role `public` (not `authenticated`). Harmless because `auth.uid()` is null for anon and anon now has no table grants. | Info | Left as is. |
| 12 | `supabase/dangerous/DESTRUCTIVE_reset_all_tables.sql` drops everything; clearly marked, not a migration. | Info | Repo-only. |

## What the migration does

1. For each existing view: `ALTER VIEW ... SET (security_invoker = true)`; revoke all from `PUBLIC, anon, authenticated`; grant SELECT to `service_role`; re-grant SELECT to `authenticated` only for `user_streaks` (the only view the Swift client reads, `SupabaseService.fetchCurrentStreak`; `recent_workouts_summary` and `month_plan_progress` are unused by the client and edge functions).
2. Revoke all table privileges from `PUBLIC, anon` and `TRUNCATE, TRIGGER, REFERENCES` from `authenticated` on every public table; `sync_tombstones` = SELECT+INSERT only for authenticated; `rate_limits` = no client access; default privileges for future tables no longer grant anon.
3. `ALTER FUNCTION ... SET search_path = public, pg_temp` on `check_rate_limit`, `refund_rate_limit`, `update_updated_at_column`; execute stays `authenticated` (+`service_role`) for `check_rate_limit`, `service_role` only for `refund_rate_limit`.
4. Policies for `planned_sessions`, `personal_records`, `food_entries` require every referenced parent (`month_plan_id`, `workout_id`, `food_id`, `meal_slot_id`) to be owned by `auth.uid()` in `WITH CHECK`. Guarded so it also works when the journal tables are absent.

It is idempotent (run twice without error), drops no data, and tolerates missing objects.

## Behaviour risks to be aware of

- Parent-ownership checks mean a client must push the parent before the child. `planned_sessions` needs its `month_plans` row (and `workout_id`'s workout, when set) to exist first; same for `food_entries` -> `foods`/`meal_slots`. If the sync layer upserts children before parents it will now get a 403/RLS error where it previously got an FK error or a success. Verify the push order in the sync code before shipping (child writes that fail should be retried, not dead-lettered).
- Because the `food_entries` policy references `meal_slots`, apply `20261030120000` before this migration (see below), otherwise the `meal_slot_id` check is omitted and a second run of this migration is needed after it.
- Revoking `authenticated` from `recent_workouts_summary` and `month_plan_progress` breaks any client that reads them (none found in this repo).

## Deploy steps

1. Back up (or note the time for PITR).
2. Apply pending nutrition migrations to the live project in order, if the build in TestFlight needs them: `20261026120000`, `20261030120000`, `20261102120000` (`20261103...` already applied). The live history is sparse, so check the live schema with `list_tables` rather than trusting `list_migrations`.
3. Apply `20261105120000_rls_views_security_invoker.sql` (MCP `apply_migration` or SQL editor). If step 2 ran afterwards instead, re-run this file once.
4. Run `supabase/tests/rls_boundaries.sql` (rolls back; safe) and expect only `RLS OK` lines; confirm the cleanup query in `supabase/tests/README.md` returns 0.
5. Smoke test in the app: streak shows, workout/plan sync and food logging work for a real account.
6. Optional hardening in the Supabase dashboard: Auth > Attack protection/leaked-password protection; run the Security Advisor.

## Verification

- Scratch PostgreSQL 16 with stubbed `auth` schema and roles, default privileges mimicking Supabase: baseline (no new migration) fails the extended test with the findings above; after the migration (applied twice) the test passes with 274 `RLS OK` lines and rolls back (0 leftover users). Re-run without journal tables also passes (journal checks skipped). Stub differs from real Supabase (superuser, no GoTrue), so run step 4 on the real project.
- Live checks were read-only catalog queries only (`pg_class`, `pg_policies`, `pg_proc`, `information_schema.role_table_grants`, `schema_migrations`, `pg_default_acl`). The test script was NOT run live (it inserts inside a rolled-back transaction).
