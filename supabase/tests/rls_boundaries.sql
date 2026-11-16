-- RLS boundary tests. Safe to run against production: everything happens in ONE
-- transaction that always ends in ROLLBACK. Two throwaway users (random uuids,
-- emails rls-test-*@invalid.test) are inserted into auth.users inside it.
-- Results: RAISE NOTICE with the passes, a final result row with the full
-- log, or an exception 'RLS FAIL: ...' listing every violation.
-- Covers: core + nutrition tables (SELECT/INSERT/UPDATE/DELETE across users), the three views,
-- cross-user foreign keys, privilege hygiene (anon/TRUNCATE), SECURITY DEFINER functions and RPC calls.
-- Optional journal tables (meal_slots, water_entries, day_notes) are tested only when they exist.
BEGIN;

DO $test$
DECLARE
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  a_w uuid := gen_random_uuid();  b_w uuid := gen_random_uuid();
  a_e uuid := gen_random_uuid();  b_e uuid := gen_random_uuid();
  a_s uuid := gen_random_uuid();  b_s uuid := gen_random_uuid();
  a_mp uuid := gen_random_uuid(); b_mp uuid := gen_random_uuid();
  a_f uuid := gen_random_uuid();  b_f uuid := gen_random_uuid();   -- foods
  a_m uuid := gen_random_uuid();  b_m uuid := gen_random_uuid();   -- meal_slots
  a_fe uuid := gen_random_uuid(); b_fe uuid := gen_random_uuid();  -- food_entries
  a_ps uuid := gen_random_uuid(); b_ps uuid := gen_random_uuid();  -- planned_sessions
  has_journal boolean;
  u uuid; w uuid; e uuid; s uuid; mp uuid; f uuid; m uuid; fe uuid; ps uuid;
  v text; r record;
  t text; stmt text; label text; n bigint;
  log text := '';
  fails text := '';
  user_tables text[] := ARRAY['profiles','workouts','personal_records','month_plans',
    'planned_sessions','ai_context_summaries','rest_days','sync_tombstones',
    'nutrition_targets','foods','food_entries','nutrition_goal_settings','nutrition_plans'];
  all_tables text[] := ARRAY['profiles','workouts','exercises','sets','personal_records',
    'month_plans','planned_sessions','ai_context_summaries','rest_days','sync_tombstones',
    'nutrition_targets','foods','food_entries','nutrition_goal_settings','nutrition_plans'];
  inserts text[];
  blocked text[];
  i int;
BEGIN
  has_journal := to_regclass('public.meal_slots') IS NOT NULL
             AND to_regclass('public.water_entries') IS NOT NULL
             AND to_regclass('public.day_notes') IS NOT NULL
             AND EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema = 'public' AND table_name = 'food_entries'
                           AND column_name = 'meal_slot_id');
  IF has_journal THEN
    user_tables := user_tables || ARRAY['meal_slots','water_entries','day_notes'];
    all_tables  := all_tables  || ARRAY['meal_slots','water_entries','day_notes'];
  ELSE
    log := log || E'RLS SKIP: journal tables (meal_slots/water_entries/day_notes) not present; not tested\n';
  END IF;

  -- ---------- static catalog checks (as postgres) ----------
  -- views must run as the caller, otherwise they bypass RLS
  FOREACH v IN ARRAY ARRAY['user_streaks','recent_workouts_summary','month_plan_progress'] LOOP
    IF to_regclass('public.' || v) IS NULL THEN
      log := log || format('RLS SKIP: view %s does not exist', v) || E'\n';
    ELSE
      IF coalesce((SELECT 'security_invoker=true' = ANY (c.reloptions) OR 'security_invoker=on' = ANY (c.reloptions)
                   FROM pg_class c WHERE c.oid = ('public.' || v)::regclass), false) THEN
        log := log || format('RLS OK: view %s has security_invoker', v) || E'\n';
      ELSE
        fails := fails || format('RLS FAIL: view %s lacks security_invoker (bypasses RLS)', v) || E'\n';
      END IF;
      IF has_table_privilege('anon', 'public.' || v, 'SELECT') THEN
        fails := fails || format('RLS FAIL: anon has SELECT on view %s', v) || E'\n';
      ELSE
        log := log || format('RLS OK: anon has no privileges on view %s', v) || E'\n';
      END IF;
    END IF;
  END LOOP;
  -- table privilege hygiene: anon nothing; authenticated no TRUNCATE (it ignores RLS)
  FOR r IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind IN ('r','p') LOOP
    IF has_table_privilege('anon', format('public.%I', r.relname), 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') THEN
      fails := fails || format('RLS FAIL: anon holds table privileges on %s', r.relname) || E'\n';
    END IF;
    IF has_table_privilege('authenticated', format('public.%I', r.relname), 'TRUNCATE') THEN
      fails := fails || format('RLS FAIL: authenticated holds TRUNCATE on %s (bypasses RLS)', r.relname) || E'\n';
    END IF;
  END LOOP;
  log := log || E'RLS OK: table privilege hygiene checked (anon none, authenticated no TRUNCATE)\n';
  -- SECURITY DEFINER functions pin search_path and are not callable by anon / PUBLIC
  FOR r IN SELECT p.oid, p.proname, p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.prosecdef LOOP
    IF NOT EXISTS (SELECT 1 FROM unnest(coalesce(r.proconfig, '{}')) x WHERE x LIKE 'search_path=%') THEN
      fails := fails || format('RLS FAIL: SECURITY DEFINER function %s has no search_path', r.proname) || E'\n';
    END IF;
    IF has_function_privilege('anon', r.oid, 'EXECUTE') THEN
      fails := fails || format('RLS FAIL: anon can EXECUTE SECURITY DEFINER function %s', r.proname) || E'\n';
    END IF;
  END LOOP;
  IF to_regprocedure('public.refund_rate_limit(uuid,text)') IS NOT NULL
     AND has_function_privilege('authenticated', 'public.refund_rate_limit(uuid,text)', 'EXECUTE') THEN
    fails := fails || E'RLS FAIL: authenticated can EXECUTE refund_rate_limit (service_role only)\n';
  END IF;
  log := log || E'RLS OK: SECURITY DEFINER functions checked (search_path, anon execute)\n';

  -- ---------- seed as postgres ----------
  INSERT INTO auth.users (id, email) VALUES
    (a, 'rls-test-a-' || a || '@invalid.test'),
    (b, 'rls-test-b-' || b || '@invalid.test');

  FOREACH u IN ARRAY ARRAY[a, b] LOOP
    w  := CASE WHEN u = a THEN a_w  ELSE b_w  END;
    e  := CASE WHEN u = a THEN a_e  ELSE b_e  END;
    s  := CASE WHEN u = a THEN a_s  ELSE b_s  END;
    mp := CASE WHEN u = a THEN a_mp ELSE b_mp END;
    f  := CASE WHEN u = a THEN a_f  ELSE b_f  END;
    m  := CASE WHEN u = a THEN a_m  ELSE b_m  END;
    fe := CASE WHEN u = a THEN a_fe ELSE b_fe END;
    ps := CASE WHEN u = a THEN a_ps ELSE b_ps END;
    -- a signup trigger may already have created the profile
    INSERT INTO public.profiles (user_id) VALUES (u) ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO public.workouts (id, user_id, workout_type) VALUES (w, u, 'rls-test');
    INSERT INTO public.exercises (id, workout_id, name, muscle_group, order_index)
      VALUES (e, w, 'rls-test', 'rls-test', 0);
    INSERT INTO public.sets (id, exercise_id, set_number, weight_lbs, reps) VALUES (s, e, 1, 1, 1);
    INSERT INTO public.personal_records (user_id, exercise_name, weight_lbs, reps, date_achieved)
      VALUES (u, 'rls-test', 1, 1, current_date);
    INSERT INTO public.month_plans (id, user_id, start_date, end_date) VALUES (mp, u, current_date, current_date);
    INSERT INTO public.planned_sessions (id, month_plan_id, user_id, planned_date, workout_type)
      VALUES (ps, mp, u, current_date, 'rls-test');
    INSERT INTO public.ai_context_summaries (user_id, workout_type, summary_text) VALUES (u, 'rls-test', 'x');
    INSERT INTO public.rest_days (user_id, date) VALUES (u, current_date);
    INSERT INTO public.sync_tombstones (user_id, entity, record_id) VALUES (u, 'workout', gen_random_uuid());
    INSERT INTO public.rate_limits (user_id) VALUES (u);
    -- nutrition
    INSERT INTO public.nutrition_targets (user_id, effective_date) VALUES (u, current_date);
    INSERT INTO public.foods (id, user_id, name) VALUES (f, u, 'rls-test');
    INSERT INTO public.nutrition_goal_settings (user_id) VALUES (u);
    INSERT INTO public.nutrition_plans (user_id, name) VALUES (u, 'rls-test');
    IF has_journal THEN
      INSERT INTO public.meal_slots (id, user_id, name) VALUES (m, u, 'rls-test');
      INSERT INTO public.food_entries (id, user_id, date, food_id, meal_slot_id, name)
        VALUES (fe, u, current_date, f, m, 'rls-test');
      INSERT INTO public.water_entries (user_id, date) VALUES (u, current_date);
      INSERT INTO public.day_notes (user_id, date) VALUES (u, current_date);
    ELSE
      INSERT INTO public.food_entries (id, user_id, date, food_id, name)
        VALUES (fe, u, current_date, f, 'rls-test');
    END IF;
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

  -- 1b. views show only A's rows (or are closed to authenticated); B's rows must never leak
  FOREACH v IN ARRAY ARRAY['user_streaks','recent_workouts_summary','month_plan_progress'] LOOP
    IF to_regclass('public.' || v) IS NOT NULL THEN
      BEGIN
        EXECUTE format('SELECT count(*) FROM public.%I', v) INTO n;
        IF n <= 1 THEN
          log := log || format('RLS OK: A sees %s row(s) in view %s (no leak of B)', n, v) || E'\n';
        ELSE
          fails := fails || format('RLS FAIL: A sees %s rows in view %s (B''s rows leak)', n, v) || E'\n';
        END IF;
        EXECUTE format('SELECT count(*) FROM public.%I WHERE user_id = %L', v, b) INTO n;
        IF n <> 0 THEN
          fails := fails || format('RLS FAIL: A reads B''s rows through view %s', v) || E'\n';
        END IF;
      EXCEPTION WHEN insufficient_privilege THEN
        log := log || format('RLS OK: authenticated denied on view %s (privilege error)', v) || E'\n';
      END;
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
    format('INSERT INTO public.sync_tombstones (user_id, entity, record_id) VALUES (%L, ''set'', gen_random_uuid())', b),
    format('INSERT INTO public.nutrition_targets (user_id, effective_date) VALUES (%L, current_date + 1)', b),
    format('INSERT INTO public.foods (user_id, name) VALUES (%L, ''x'')', b),
    format('INSERT INTO public.food_entries (user_id, date, name) VALUES (%L, current_date, ''x'')', b),
    format('INSERT INTO public.nutrition_goal_settings (user_id) VALUES (%L)', b),
    format('INSERT INTO public.nutrition_plans (user_id, name) VALUES (%L, ''x'')', b),
    -- cross-user foreign keys: own user_id, but the parent belongs to B
    format('INSERT INTO public.planned_sessions (month_plan_id, user_id, planned_date, workout_type) VALUES (%L, %L, current_date, ''x'')', b_mp, a),
    format('INSERT INTO public.planned_sessions (month_plan_id, user_id, planned_date, workout_type, workout_id) VALUES (%L, %L, current_date, ''x'', %L)', a_mp, a, b_w),
    format('INSERT INTO public.personal_records (user_id, exercise_name, weight_lbs, reps, date_achieved, workout_id) VALUES (%L, ''x'', 1, 1, current_date, %L)', a, b_w),
    format('INSERT INTO public.food_entries (user_id, date, name, food_id) VALUES (%L, current_date, ''x'', %L)', a, b_f)
  ];
  IF has_journal THEN
    inserts := inserts || ARRAY[
      format('INSERT INTO public.meal_slots (user_id, name) VALUES (%L, ''x'')', b),
      format('INSERT INTO public.water_entries (user_id, date) VALUES (%L, current_date + 1)', b),
      format('INSERT INTO public.day_notes (user_id, date) VALUES (%L, current_date + 1)', b),
      format('INSERT INTO public.food_entries (user_id, date, name, meal_slot_id) VALUES (%L, current_date, ''x'', %L)', a, b_m)
    ];
  END IF;
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

  -- 3c. A cannot re-point its own rows at B's parents (UPDATE ... WITH CHECK), nor move children into B's tree
  blocked := ARRAY[
    format('UPDATE public.planned_sessions SET month_plan_id = %L WHERE id = %L', b_mp, a_ps),
    format('UPDATE public.planned_sessions SET workout_id = %L WHERE id = %L', b_w, a_ps),
    format('UPDATE public.personal_records SET workout_id = %L WHERE user_id = %L', b_w, a),
    format('UPDATE public.food_entries SET food_id = %L WHERE id = %L', b_f, a_fe),
    format('UPDATE public.exercises SET workout_id = %L WHERE id = %L', b_w, a_e),
    format('UPDATE public.sets SET exercise_id = %L WHERE id = %L', b_e, a_s)
  ];
  IF has_journal THEN
    blocked := blocked || ARRAY[format('UPDATE public.food_entries SET meal_slot_id = %L WHERE id = %L', b_m, a_fe)];
  END IF;
  FOREACH stmt IN ARRAY blocked LOOP
    BEGIN
      EXECUTE stmt; GET DIAGNOSTICS n = ROW_COUNT;
      IF n = 0 THEN
        log := log || format('RLS OK: blocked (0 rows): %s', left(stmt, 70)) || E'\n';
      ELSE
        fails := fails || format('RLS FAIL: cross-user FK UPDATE succeeded: %s', stmt) || E'\n';
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || format('RLS OK: blocked: %s', left(stmt, 70)) || E'\n';
    END;
  END LOOP;

  -- 3d. positive control: A CAN insert child rows pointing at its own parents (policies are not over-tight)
  BEGIN
    INSERT INTO public.planned_sessions (month_plan_id, user_id, planned_date, workout_type, workout_id)
      VALUES (a_mp, a, current_date + 1, 'rls-test', a_w);
    INSERT INTO public.personal_records (user_id, exercise_name, weight_lbs, reps, date_achieved, workout_id)
      VALUES (a, 'rls-test-2', 1, 1, current_date, a_w);
    INSERT INTO public.food_entries (user_id, date, name, food_id) VALUES (a, current_date, 'rls-test-2', a_f);
    IF has_journal THEN
      INSERT INTO public.food_entries (user_id, date, name, food_id, meal_slot_id)
        VALUES (a, current_date, 'rls-test-3', a_f, a_m);
    END IF;
    log := log || E'RLS OK: A can insert child rows pointing at its own parents\n';
  EXCEPTION WHEN insufficient_privilege THEN
    fails := fails || E'RLS FAIL: A cannot insert child rows pointing at its OWN parents (policy too tight)\n';
  END;

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

  -- 6. RPC: A cannot act on B's id; check_rate_limit only ever touches the caller
  BEGIN
    PERFORM public.refund_rate_limit(b, 'coach');
    fails := fails || E'RLS FAIL: authenticated executed refund_rate_limit(B)\n';
  EXCEPTION WHEN insufficient_privilege THEN
    log := log || E'RLS OK: authenticated cannot call refund_rate_limit\n';
  END;
  BEGIN
    PERFORM public.check_rate_limit();
    log := log || E'RLS OK: A can call check_rate_limit()\n';
  EXCEPTION WHEN insufficient_privilege THEN
    fails := fails || E'RLS FAIL: authenticated cannot call check_rate_limit\n';
  END;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO n FROM public.rate_limits WHERE user_id = b;
  IF n = 1 THEN
    log := log || E'RLS OK: B''s rate_limits untouched by A''s RPC calls (count=1)\n';
  ELSE
    fails := fails || format('RLS FAIL: B''s rate_limits changed to %s rows after A''s RPC calls', n) || E'\n';
  END IF;
  SELECT count(*) INTO n FROM public.rate_limits WHERE user_id = a;
  IF n = 2 THEN  -- seeded row + the one check_rate_limit() added
    log := log || E'RLS OK: check_rate_limit() recorded the call for A only (count=2)\n';
  ELSE
    fails := fails || format('RLS FAIL: A has %s rate_limits rows (expected 2)', n) || E'\n';
  END IF;

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
  FOREACH v IN ARRAY ARRAY['user_streaks','recent_workouts_summary','month_plan_progress'] LOOP
    IF to_regclass('public.' || v) IS NOT NULL THEN
      BEGIN
        EXECUTE format('SELECT count(*) FROM public.%I', v) INTO n;
        IF n = 0 THEN
          log := log || format('RLS OK: anon sees nothing in view %s (0 rows)', v) || E'\n';
        ELSE
          fails := fails || format('RLS FAIL: anon sees %s rows in view %s', n, v) || E'\n';
        END IF;
      EXCEPTION WHEN insufficient_privilege THEN
        log := log || format('RLS OK: anon denied on view %s (privilege error)', v) || E'\n';
      END;
    END IF;
  END LOOP;
  FOREACH stmt IN ARRAY ARRAY['SELECT public.check_rate_limit()',
                              format('SELECT public.refund_rate_limit(%L, ''coach'')', a)] LOOP
    BEGIN
      EXECUTE stmt;
      fails := fails || format('RLS FAIL: anon executed %s', stmt) || E'\n';
    EXCEPTION WHEN insufficient_privilege THEN
      log := log || format('RLS OK: anon cannot execute %s', left(stmt, 40)) || E'\n';
    END;
  END LOOP;

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
