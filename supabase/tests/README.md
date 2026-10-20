# Supabase tests

## rls_boundaries.sql

Checks that Row Level Security isolates users: one user cannot read, update,
delete or insert another user's rows (including exercises and sets via their
parent workout), `sync_tombstones` is insert/select only, `rate_limits` is
closed to `authenticated`, and `anon` sees nothing.

The script creates two throwaway users in `auth.users` and seeds one row per
table for each, all inside a single transaction that **always ends in
`ROLLBACK`**, so nothing persists. It only counts rows, so it is safe to run
against production. It fails with `RLS FAIL: ...` listing every violation, or
returns a log of `RLS OK: ...` lines.

Run it either way:

- Supabase SQL editor: paste the whole file and run it.
- MCP: send the whole file as one `execute_sql` call.

To confirm cleanup afterwards:
`select count(*) from auth.users where email like 'rls-test-%@invalid.test';` returns 0.
