# Supabase migrations

This folder is the source of truth for the database schema. `supabase/supabase_schema.sql` is a reference snapshot only.

## Naming
`YYYYMMDDHHMMSS_short_snake_case_description.sql`, using the same 14-digit version Supabase records in its migration history. Files in `legacy/` (`_SUPERSEDED`, `_MANUAL`) were not applied through the normal path and carry no timestamp so the CLI never treats them as pending; their header comment says why.

## Rules
- Additive and idempotent: `IF NOT EXISTS`, `DROP POLICY/TRIGGER IF EXISTS` then create, guard FK changes in a `DO` block.
- Never drop a table, column or row in a migration.
- No explicit BEGIN/COMMIT: the runner applies each file as one atomic transaction.

## Applying
- Supabase MCP `apply_migration` (name = description, query = file contents), or
- Dashboard SQL editor: paste the file and run.

Check `list_migrations` afterwards so the history matches the file name.

## Never run
Anything in `supabase/dangerous/`. `DESTRUCTIVE_reset_all_tables.sql` drops every table.

## Rollback
`rollback/` holds down scripts. They are never auto-run. Active statements are the safe ones (drop trigger, restore FKs); anything that drops columns or tables is commented out because it destroys user data. Take a backup first.
