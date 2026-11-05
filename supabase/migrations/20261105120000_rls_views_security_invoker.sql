-- Database security hardening (DB audit, docs/security/DB_AUDIT.md). Forward-only and idempotent.
-- Drops no table, column or row. Every statement is guarded so it is safe on a project where some
-- earlier nutrition migrations have not been applied yet.

-- a. Views run with the CALLER's privileges so RLS on workouts / exercises / sets / month_plans /
--    planned_sessions applies. Without security_invoker a view runs as its owner (postgres) and bypasses RLS.
--    The app only reads user_streaks; the other two views are unused by the client and edge functions,
--    so only service_role keeps access to them. anon never gets access.
DO $$
DECLARE
  v text;
BEGIN
  FOREACH v IN ARRAY ARRAY['user_streaks','recent_workouts_summary','month_plan_progress'] LOOP
    IF to_regclass(format('public.%I', v)) IS NOT NULL THEN
      EXECUTE format('ALTER VIEW public.%I SET (security_invoker = true)', v);
      EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated', v);
      EXECUTE format('GRANT SELECT ON public.%I TO service_role', v);
      IF v = 'user_streaks' THEN
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated', v);
      END IF;
    END IF;
  END LOOP;
END $$;

-- b. Table privileges. Supabase default privileges give anon and authenticated every privilege on every
--    new public table, including TRUNCATE (which ignores RLS) and TRIGGER/REFERENCES. RLS stays the gate
--    for rows; this removes the privileges nobody needs. anon has no business touching app tables.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind IN ('r','p') LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', r.relname);
    EXECUTE format('REVOKE TRUNCATE, TRIGGER, REFERENCES ON public.%I FROM authenticated', r.relname);
  END LOOP;
END $$;

-- sync_tombstones is append-only for clients (SELECT + INSERT only).
REVOKE ALL ON public.sync_tombstones FROM authenticated;
GRANT SELECT, INSERT ON public.sync_tombstones TO authenticated;

-- rate_limits is service-side only (check_rate_limit / refund_rate_limit are SECURITY DEFINER).
REVOKE ALL ON public.rate_limits FROM authenticated;
GRANT ALL ON public.rate_limits TO service_role;

-- Future tables created by this role should not be handed to anon automatically.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;

-- c. SECURITY DEFINER functions: pin search_path with pg_temp last (without it pg_temp is searched first
--    for relations) and keep EXECUTE tight.
--    check_rate_limit() acts only on auth.uid() (no user argument), so a caller cannot spend another
--    user's quota. refund_rate_limit(p_user_id, ...) takes any user id by design and is service_role only.
DO $$
BEGIN
  IF to_regprocedure('public.check_rate_limit()') IS NOT NULL THEN
    ALTER FUNCTION public.check_rate_limit() SET search_path = public, pg_temp;
    REVOKE EXECUTE ON FUNCTION public.check_rate_limit() FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.check_rate_limit() TO authenticated, service_role;
  END IF;
  IF to_regprocedure('public.refund_rate_limit(uuid,text)') IS NOT NULL THEN
    ALTER FUNCTION public.refund_rate_limit(uuid, text) SET search_path = public, pg_temp;
    REVOKE EXECUTE ON FUNCTION public.refund_rate_limit(uuid, text) FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.refund_rate_limit(uuid, text) TO service_role;
  END IF;
  IF to_regprocedure('public.update_updated_at_column()') IS NOT NULL THEN
    ALTER FUNCTION public.update_updated_at_column() SET search_path = public, pg_temp;
    REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
  END IF;
END $$;

-- d. Cross-user foreign keys. A foreign-key check bypasses RLS, so with a user_id-only policy user B can
--    insert a row (with B's own user_id) whose parent id is A's row. Require every referenced parent to be
--    owned by the caller. USING is unchanged; only WITH CHECK (INSERT and UPDATE) is tightened.
DO $$
BEGIN
  IF to_regclass('public.planned_sessions') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Users manage own planned sessions" ON public.planned_sessions;
    CREATE POLICY "Users manage own planned sessions"
      ON public.planned_sessions FOR ALL
      USING (auth.uid() = user_id)
      WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (SELECT 1 FROM public.month_plans mp
                    WHERE mp.id = planned_sessions.month_plan_id AND mp.user_id = auth.uid())
        AND (planned_sessions.workout_id IS NULL OR EXISTS (
              SELECT 1 FROM public.workouts w
              WHERE w.id = planned_sessions.workout_id AND w.user_id = auth.uid()))
      );
  END IF;

  IF to_regclass('public.personal_records') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Users manage own PRs" ON public.personal_records;
    CREATE POLICY "Users manage own PRs"
      ON public.personal_records FOR ALL
      USING (auth.uid() = user_id)
      WITH CHECK (
        auth.uid() = user_id
        AND (personal_records.workout_id IS NULL OR EXISTS (
              SELECT 1 FROM public.workouts w
              WHERE w.id = personal_records.workout_id AND w.user_id = auth.uid()))
      );
  END IF;

  IF to_regclass('public.food_entries') IS NOT NULL AND to_regclass('public.foods') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Users manage own food entries" ON public.food_entries;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'food_entries' AND column_name = 'meal_slot_id')
       AND to_regclass('public.meal_slots') IS NOT NULL THEN
      CREATE POLICY "Users manage own food entries"
        ON public.food_entries FOR ALL
        USING (auth.uid() = user_id)
        WITH CHECK (
          auth.uid() = user_id
          AND (food_entries.food_id IS NULL OR EXISTS (
                SELECT 1 FROM public.foods f
                WHERE f.id = food_entries.food_id AND f.user_id = auth.uid()))
          AND (food_entries.meal_slot_id IS NULL OR EXISTS (
                SELECT 1 FROM public.meal_slots m
                WHERE m.id = food_entries.meal_slot_id AND m.user_id = auth.uid()))
        );
    ELSE
      CREATE POLICY "Users manage own food entries"
        ON public.food_entries FOR ALL
        USING (auth.uid() = user_id)
        WITH CHECK (
          auth.uid() = user_id
          AND (food_entries.food_id IS NULL OR EXISTS (
                SELECT 1 FROM public.foods f
                WHERE f.id = food_entries.food_id AND f.user_id = auth.uid()))
        );
    END IF;
  END IF;
END $$;
