-- RLS boundary tests. Safe to run against production: everything happens in ONE
-- transaction that always ends in ROLLBACK. Two throwaway users (random uuids,
-- emails rls-test-*@invalid.test) are inserted into auth.users inside it.
-- Results: RAISE NOTICE with the passes, a final result row with the full
-- log, or an exception 'RLS FAIL: ...' listing every violation.
BEGIN;

DO $test$
DECLARE
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  a_w uuid := gen_random_uuid();  b_w uuid := gen_random_uuid();
  a_e uuid := gen_random_uuid();  b_e uuid := gen_random_uuid();
  a_s uuid := gen_random_uuid();  b_s uuid := gen_random_uuid();
  a_mp uuid := gen_random_uuid(); b_mp uuid := gen_random_uuid();
  u uuid; w uuid; e uuid; s uuid; mp uuid;
  t text; stmt text; label text; n bigint;
  log text := '';
  fails text := '';
  user_tables text[] := ARRAY['profiles','workouts','personal_records','month_plans',
    'planned_sessions','ai_context_summaries','rest_days','sync_tombstones'];
  all_tables text[] := ARRAY['profiles','workouts','exercises','sets','personal_records',
    'month_plans','planned_sessions','ai_context_summaries','rest_days','sync_tombstones'];
  inserts text[];
  i int;
BEGIN
  -- ---------- seed as postgres ----------
  INSERT INTO auth.users (id, email) VALUES
    (a, 'rls-test-a-' || a || '@invalid.test'),
    (b, 'rls-test-b-' || b || '@invalid.test');

  FOREACH u IN ARRAY ARRAY[a, b] LOOP
    w  := CASE WHEN u = a THEN a_w  ELSE b_w  END;
    e  := CASE WHEN u = a THEN a_e  ELSE b_e  END;
    s  := CASE WHEN u = a THEN a_s  ELSE b_s  END;
    mp := CASE WHEN u = a THEN a_mp ELSE b_mp END;
    -- a signup trigger may already have created the profile
    INSERT INTO public.profiles (user_id) VALUES (u) ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO public.workouts (id, user_id, workout_type) VALUES (w, u, 'rls-test');
    INSERT INTO public.exercises (id, workout_id, name, muscle_group, order_index)
      VALUES (e, w, 'rls-test', 'rls-test', 0);
    INSERT INTO public.sets (id, exercise_id, set_number, weight_lbs, reps) VALUES (s, e, 1, 1, 1);
    INSERT INTO public.personal_records (user_id, exercise_name, weight_lbs, reps, date_achieved)
      VALUES (u, 'rls-test', 1, 1, current_date);
    INSERT INTO public.month_plans (id, user_id, start_date, end_date) VALUES (mp, u, current_date, current_date);
    INSERT INTO public.planned_sessions (month_plan_id, user_id, planned_date, workout_type)
      VALUES (mp, u, current_date, 'rls-test');
    INSERT INTO public.ai_context_summaries (user_id, workout_type, summary_text) VALUES (u, 'rls-test', 'x');
    INSERT INTO public.rest_days (user_id, date) VALUES (u, current_date);
    INSERT INTO public.sync_tombstones (user_id, entity, record_id) VALUES (u, 'workout', gen_random_uuid());
    INSERT INTO public.rate_limits (user_id) VALUES (u);
  END LOOP;

  -- ---------- act as user A ----------
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  IF auth.uid() IS DISTINCT FROM a THEN
    RAISE EXCEPTION 'RLS FAIL: test harness could not impersonate user A (auth.uid()=%)', auth.uid();
  END IF;

  -- 1. A sees only A's rows (each table was seeded with exactly 1 row for A)
  FOREACH t IN ARRAY all_tables LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    IF n = 1 THEN
      log := log || format('RLS OK: A sees only own rows in %s (count=1)', t) || E'\n';
    ELSE
      fails := fails || format('RLS FAIL: A sees %s rows in %s (expected 1)', n, t) || E'\n';
    END IF;
  END LOOP;

  -- 2. A cannot UPDATE / DELETE B's rows
  FOREACH t IN ARRAY user_tables LOOP
    FOR i IN 1..2 LOOP
      stmt := CASE WHEN i = 1
        THEN format('UPDATE public.%I SET user_id = user_id WHERE user_id = %L', t, b)
        ELSE format('DELETE FROM public.%I WHERE user_id = %L', t, b) END;
      label := CASE WHEN i = 1 THEN 'UPDATE' ELSE 'DELETE' END;
      BEGIN
        EXECUTE stmt; GET DIAGNOSTICS n = ROW_COUNT;
        IF n = 0 THEN
          log := log || format('RLS OK: A cannot %s B''s rows in %s (0 rows)', label, t) || E'\n';
        ELSE
          fails := fails || format('RLS FAIL: A did %s on %s of B''s rows in %s', label, n, t) || E'\n';
        END IF;
      EXCEPTION WHEN insufficient_privilege THEN
        log := log || format('RLS OK: A cannot %s B''s rows in %s (privilege error)', label, t) || E'\n';
      END;
    END LOOP;
  END LOOP;
  -- child tables (policy goes through the parent workout)
  FOR i IN 1..4 LOOP
    stmt := CASE i
      WHEN 1 THEN format('UPDATE public.exercises SET name = name WHERE id = %L', b_e)
      WHEN 2 THEN format('DELETE FROM public.exercises WHERE id = %L', b_e)
      WHEN 3 THEN format('UPDATE public.sets SET reps = reps WHERE id = %L', b_s)
      ELSE format('DELETE FROM public.sets WHERE id = %L', b_s) END;
    label := CASE i WHEN 1 THEN 'UPDATE exercises' WHEN 2 THEN 'DELETE exercises'
                    WHEN 3 THEN 'UPDATE sets' ELSE 'DELETE sets' END;
    BEGIN
      EXECUTE stmt; GET DIAGNOSTICS n = ROW_COUNT;
      IF n = 0 THEN
        log := log || format('RLS OK: A cannot %s of B (0 rows)', label) || E'\n';
      ELSE
        fails := fails || format('RLS FAIL: A did %s of B (%s rows)', label, n) || E'\n';
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || format('RLS OK: A cannot %s of B (privilege error)', label) || E'\n';
    END;
  END LOOP;

  -- 3. A cannot INSERT rows owned by B / into B's workout / B's exercise
  inserts := ARRAY[
    format('INSERT INTO public.profiles (user_id) VALUES (%L)', b),
    format('INSERT INTO public.workouts (user_id, workout_type) VALUES (%L, ''x'')', b),
    format('INSERT INTO public.exercises (workout_id, name, muscle_group, order_index) VALUES (%L, ''x'', ''x'', 0)', b_w),
    format('INSERT INTO public.sets (exercise_id, set_number, weight_lbs, reps) VALUES (%L, 2, 1, 1)', b_e),
    format('INSERT INTO public.personal_records (user_id, exercise_name, weight_lbs, reps, date_achieved) VALUES (%L, ''x'', 1, 1, current_date)', b),
    format('INSERT INTO public.month_plans (user_id, start_date, end_date) VALUES (%L, current_date, current_date)', b),
    format('INSERT INTO public.planned_sessions (month_plan_id, user_id, planned_date, workout_type) VALUES (%L, %L, current_date, ''x'')', a_mp, b),
    format('INSERT INTO public.ai_context_summaries (user_id, workout_type, summary_text) VALUES (%L, ''y'', ''x'')', b),
    format('INSERT INTO public.rest_days (user_id, date) VALUES (%L, current_date + 1)', b),
    format('INSERT INTO public.sync_tombstones (user_id, entity, record_id) VALUES (%L, ''set'', gen_random_uuid())', b)
  ];
  FOREACH stmt IN ARRAY inserts LOOP
    BEGIN
      EXECUTE stmt;
      fails := fails || format('RLS FAIL: cross-user INSERT succeeded: %s', stmt) || E'\n';
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || format('RLS OK: blocked: %s', left(stmt, 70)) || E'\n';
    END;
  END LOOP;

  -- 3b. A cannot hand its own row to B (UPDATE ... SET user_id = B)
  FOREACH t IN ARRAY ARRAY['workouts','personal_records','month_plans','ai_context_summaries','rest_days'] LOOP
    BEGIN
      EXECUTE format('UPDATE public.%I SET user_id = %L WHERE user_id = %L', t, b, a);
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n = 0 THEN
        log := log || format('RLS OK: A cannot reassign own %s row to B (0 rows)', t) || E'\n';
      ELSE
        fails := fails || format('RLS FAIL: A reassigned %s rows in %s to B', n, t) || E'\n';
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || format('RLS OK: A cannot reassign own %s row to B (privilege error)', t) || E'\n';
    END;
  END LOOP;

  -- 4. sync_tombstones: A can insert/select own, cannot update/delete any
  BEGIN
    INSERT INTO public.sync_tombstones (user_id, entity, record_id) VALUES (a, 'set', gen_random_uuid());
    SELECT count(*) INTO n FROM public.sync_tombstones;
    IF n = 2 THEN
      log := log || E'RLS OK: A inserted and sees own tombstones (2), none of B''s\n';
    ELSE
      fails := fails || format('RLS FAIL: A sees %s tombstones after own insert (expected 2)', n) || E'\n';
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    fails := fails || E'RLS FAIL: A cannot insert own tombstone\n';
  END;
  FOR i IN 1..2 LOOP
    stmt := CASE WHEN i = 1 THEN format('UPDATE public.sync_tombstones SET deleted_at = now() WHERE user_id = %L', a)
                 ELSE format('DELETE FROM public.sync_tombstones WHERE user_id = %L', a) END;
    BEGIN
      EXECUTE stmt; GET DIAGNOSTICS n = ROW_COUNT;
      IF n = 0 THEN
        log := log || E'RLS OK: A cannot UPDATE/DELETE own tombstones (0 rows)\n';
      ELSE
        fails := fails || format('RLS FAIL: A modified %s own tombstones (%s)', n, stmt) || E'\n';
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || E'RLS OK: A cannot UPDATE/DELETE own tombstones (privilege error)\n';
    END;
  END LOOP;

  -- 5. rate_limits: authenticated has no access at all
  FOR i IN 1..4 LOOP
    stmt := CASE i
      WHEN 1 THEN 'SELECT count(*) FROM public.rate_limits'
      WHEN 2 THEN format('INSERT INTO public.rate_limits (user_id) VALUES (%L)', a)
      WHEN 3 THEN 'UPDATE public.rate_limits SET endpoint = endpoint'
      ELSE 'DELETE FROM public.rate_limits' END;
    BEGIN
      IF i = 1 THEN
        EXECUTE stmt INTO n;
      ELSE
        EXECUTE stmt; GET DIAGNOSTICS n = ROW_COUNT;
      END IF;
      IF i <> 2 AND n = 0 THEN
        log := log || format('RLS OK: authenticated has no access to rate_limits (0 rows): %s', stmt) || E'\n';
      ELSE
        fails := fails || format('RLS FAIL: authenticated reached rate_limits (%s): %s', n, stmt) || E'\n';
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || format('RLS OK: authenticated has no access to rate_limits (privilege error): %s', left(stmt, 40)) || E'\n';
    END;
  END LOOP;

  -- ---------- anon ----------
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);
  FOREACH t IN ARRAY all_tables || ARRAY['rate_limits'] LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
      IF n = 0 THEN
        log := log || format('RLS OK: anon sees nothing in %s (0 rows)', t) || E'\n';
      ELSE
        fails := fails || format('RLS FAIL: anon sees %s rows in %s', n, t) || E'\n';
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || format('RLS OK: anon denied on %s (privilege error)', t) || E'\n';
    END;
  END LOOP;
  BEGIN
    EXECUTE format('INSERT INTO public.workouts (user_id, workout_type) VALUES (%L, ''x'')', a);
    fails := fails || E'RLS FAIL: anon inserted a workout\n';
  EXCEPTION WHEN insufficient_privilege THEN
    log := log || E'RLS OK: anon cannot insert\n';
  END;

  EXECUTE 'RESET ROLE';

  IF fails <> '' THEN
    RAISE EXCEPTION E'RLS FAIL: violations found\n%\n--- passes ---\n%', fails, log;
  END IF;
  RAISE NOTICE E'%', log;
  PERFORM set_config('rls_test.log', log, true);
END
$test$;

-- Full pass log as the result row (only reached if no violation).
SELECT current_setting('rls_test.log') AS rls_log;

ROLLBACK;
