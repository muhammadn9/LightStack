# Supabase tests

## rls_boundaries.sql

Two-user adversarial checks that Row Level Security and privileges isolate users. It covers:

- core tables and nutrition tables: A cannot SELECT, UPDATE, DELETE or INSERT B's rows, and cannot hand its own rows to B;
- child tables (exercises, sets) via their parent workout;
- the views `user_streaks`, `recent_workouts_summary`, `month_plan_progress`: must have `security_invoker`, must not leak B's rows, and must be closed to `anon`;
- cross-user foreign keys: A inserting or updating its own row to point at B's month plan, workout, food or meal slot must be refused (and A's legitimate own-parent inserts must still work);
- privilege hygiene: `anon` holds nothing on app tables, `authenticated` has no `TRUNCATE`;
- `sync_tombstones` is insert/select only, `rate_limits` is closed to clients;
- SECURITY DEFINER functions: `search_path` pinned, not executable by `anon`; `refund_rate_limit` is not callable by `authenticated`; `check_rate_limit()` only touches the caller's rows;
- `anon` sees nothing and cannot call the RPCs.

The journal tables (`meal_slots`, `water_entries`, `day_notes`) are tested only if they exist; the log says `RLS SKIP` otherwise.

The script creates two throwaway users in `auth.users` and seeds rows for each, all inside a single transaction that **always ends in `ROLLBACK`**, so nothing persists. It fails with `RLS FAIL: ...` listing every violation, or returns a log of `RLS OK: ...` lines.

Run it either way:

- Supabase SQL editor: paste the whole file and run it.
- MCP: send the whole file as one `execute_sql` call.
- Local scratch Postgres (needs `auth.users`, `auth.uid()`, `auth.role()` and the `anon`/`authenticated`/`service_role` roles): load `supabase/supabase_schema.sql`, the migrations in order, then `psql -d scratch -f supabase/tests/rls_boundaries.sql`.

To confirm cleanup afterwards:
`select count(*) from auth.users where email like 'rls-test-%@invalid.test';` returns 0.

Run it again after applying `20261105120000_rls_views_security_invoker.sql`. Before that migration the privilege and cross-user FK checks are expected to fail (and the view checks too, wherever the views lack `security_invoker`).
