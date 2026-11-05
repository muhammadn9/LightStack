-- AI budget tests (ai_reserve / ai_settle / ledger RLS). One transaction that ALWAYS ends in ROLLBACK,
-- so the temporary config changes, throwaway users and ledger rows never persist.
-- Briefly takes the global budget advisory lock and edits the singleton config row (rolled back);
-- prefer running it on staging, or at a quiet time. Run in the SQL editor or as one execute_sql call.
-- Result: NOTICE 'AI BUDGET OK: ...' or an exception 'AI BUDGET FAIL: ...' listing every failure.
--
-- Concurrency note: a single transaction cannot interleave two sessions. The tests here prove
-- the accounting and the lock; see "Manual concurrency test" in docs/ai/AI_COST_CONTROLS.md for the
-- two-session check (both sessions call ai_reserve for the same user near the limit; exactly one wins).
BEGIN;

DO $test$
DECLARE
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  r jsonb;
  fails text := '';
  passes int := 0;
  g_before numeric;
  n bigint;
  v_actual numeric;

BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (a, 'ai-budget-a-' || a || '@invalid.test'),
    (b, 'ai-budget-b-' || b || '@invalid.test');

  -- Known config: generous global limits relative to current real spend, small per-user limits.
  SELECT COALESCE(sum(CASE WHEN status = 'reserved' THEN reserved_usd ELSE actual_usd END), 0)
    INTO g_before FROM public.ai_usage_ledger
   WHERE created_at >= date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  UPDATE public.ai_budget_config SET
    ai_enabled = true, per_user_daily_usd = 0.10, per_user_monthly_usd = 0.15,
    global_daily_usd = g_before + 1000, global_monthly_usd = g_before + 1000,
    max_concurrent_per_user = 2,
    prices = '{"gemini-2.5-flash": {"input": 1.0, "output": 2.0, "thinking": 4.0}}'::jsonb
  WHERE id;

  -- 1. first reservation ok
  r := public.ai_reserve(a, 'req-00000001', 'chat', 'gemini-2.5-flash', 0.04);
  IF (r->>'ok')::boolean THEN passes := passes + 1; ELSE fails := fails || E'\n first reserve: ' || r::text; END IF;

  -- 2. same request while in flight -> duplicate_in_flight (idempotent, not double counted)
  r := public.ai_reserve(a, 'req-00000001', 'chat', 'gemini-2.5-flash', 0.04);
  IF r->>'reason' = 'duplicate_in_flight' THEN passes := passes + 1; ELSE fails := fails || E'\n duplicate in flight: ' || r::text; END IF;
  SELECT count(*) INTO n FROM public.ai_usage_ledger WHERE user_id = a AND request_id = 'req-00000001';
  IF n = 1 THEN passes := passes + 1; ELSE fails := fails || E'\n duplicate created extra rows: ' || n; END IF;

  -- 3. settle: 10,000 in * $1 + 5,000 out * $2 + 2,500 thinking * $4 (per 1M) = 0.01 + 0.01 + 0.01 = 0.03
  r := public.ai_settle(a, 'req-00000001', 10000, 5000, 2500, 'succeeded', 120, NULL);
  v_actual := (r->>'actual_usd')::numeric;
  IF v_actual = 0.03 THEN passes := passes + 1; ELSE fails := fails || E'\n settle cost expected 0.03 got ' || COALESCE(v_actual::text, 'null'); END IF;

  -- 4. settling twice is a no-op
  r := public.ai_settle(a, 'req-00000001', 99999, 99999, 99999, 'succeeded', 1, NULL);
  IF r->>'reason' = 'not_reserved' THEN passes := passes + 1; ELSE fails := fails || E'\n double settle: ' || r::text; END IF;

  -- 5. replaying a succeeded request is refused
  r := public.ai_reserve(a, 'req-00000001', 'chat', 'gemini-2.5-flash', 0.01);
  IF r->>'reason' = 'duplicate_completed' THEN passes := passes + 1; ELSE fails := fails || E'\n duplicate completed: ' || r::text; END IF;

  -- 6. failed attempt costs 0 and the fallback attempt reuses the SAME request_id/row
  r := public.ai_reserve(a, 'req-00000002', 'chat', 'gemini-3.5-flash', 0.04);
  IF NOT (r->>'ok')::boolean THEN fails := fails || E'\n reserve 2: ' || r::text; ELSE passes := passes + 1; END IF;
  r := public.ai_settle(a, 'req-00000002', NULL, NULL, NULL, 'failed', 50, 'upstream_503');
  IF (r->>'actual_usd')::numeric = 0 THEN passes := passes + 1; ELSE fails := fails || E'\n failed should cost 0: ' || r::text; END IF;
  r := public.ai_reserve(a, 'req-00000002', 'chat', 'gemini-2.5-flash', 0.04);
  IF (r->>'ok')::boolean AND (r->>'reused')::boolean THEN passes := passes + 1; ELSE fails := fails || E'\n fallback re-reserve: ' || r::text; END IF;
  SELECT count(*) INTO n FROM public.ai_usage_ledger WHERE user_id = a AND request_id = 'req-00000002';
  IF n = 1 THEN passes := passes + 1; ELSE fails := fails || E'\n fallback created a second row: ' || n; END IF;

  -- 7. in-flight cap (max 2): req-2 is reserved; add one more, third is refused
  r := public.ai_reserve(a, 'req-00000003', 'chat', 'gemini-2.5-flash', 0.01);
  IF NOT (r->>'ok')::boolean THEN fails := fails || E'\n reserve 3: ' || r::text; ELSE passes := passes + 1; END IF;
  r := public.ai_reserve(a, 'req-00000004', 'chat', 'gemini-2.5-flash', 0.01);
  IF r->>'reason' = 'too_many_in_flight' THEN passes := passes + 1; ELSE fails := fails || E'\n in-flight cap: ' || r::text; END IF;

  -- 8. user daily budget: spent so far = 0.03 (settled) + 0.04 + 0.01 (reserved) = 0.08 ; 0.08 + 0.04 > 0.10
  PERFORM public.ai_settle(a, 'req-00000002', 1, 1, 0, 'succeeded', 1, NULL);
  PERFORM public.ai_settle(a, 'req-00000003', 1, 1, 0, 'succeeded', 1, NULL);
  r := public.ai_reserve(a, 'req-00000005', 'plan', 'gemini-3.5-flash', 0.09);
  IF r->>'reason' = 'budget_user_daily' THEN passes := passes + 1; ELSE fails := fails || E'\n user daily: ' || r::text; END IF;

  -- 9. users are independent
  r := public.ai_reserve(b, 'req-00000001', 'chat', 'gemini-2.5-flash', 0.04);
  IF (r->>'ok')::boolean THEN passes := passes + 1; ELSE fails := fails || E'\n other user blocked: ' || r::text; END IF;

  -- 10. user monthly budget: lift the daily cap, month cap 0.15
  UPDATE public.ai_budget_config SET per_user_daily_usd = 100 WHERE id;
  PERFORM public.ai_settle(b, 'req-00000001', 1, 1, 0, 'succeeded', 1, NULL);
  UPDATE public.ai_usage_ledger SET actual_usd = 0.14 WHERE user_id = b AND request_id = 'req-00000001';
  r := public.ai_reserve(b, 'req-00000009', 'chat', 'gemini-2.5-flash', 0.02);
  IF r->>'reason' = 'budget_user_monthly' THEN passes := passes + 1; ELSE fails := fails || E'\n user monthly: ' || r::text; END IF;

  -- 11. global budget
  UPDATE public.ai_budget_config SET per_user_monthly_usd = 100,
    global_daily_usd = (SELECT COALESCE(sum(CASE WHEN status = 'reserved' THEN reserved_usd ELSE actual_usd END), 0)
                          FROM public.ai_usage_ledger WHERE created_at >= date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC') + 0.01
   WHERE id;
  r := public.ai_reserve(b, 'req-00000010', 'chat', 'gemini-2.5-flash', 0.05);
  IF r->>'reason' = 'budget_global' THEN passes := passes + 1; ELSE fails := fails || E'\n global: ' || r::text; END IF;

  -- 12. kill switch wins over everything
  UPDATE public.ai_budget_config SET ai_enabled = false, global_daily_usd = g_before + 1000 WHERE id;
  r := public.ai_reserve(b, 'req-00000011', 'chat', 'gemini-2.5-flash', 0.001);
  IF r->>'reason' = 'ai_disabled' THEN passes := passes + 1; ELSE fails := fails || E'\n kill switch: ' || r::text; END IF;
  UPDATE public.ai_budget_config SET ai_enabled = true WHERE id;

  -- 13. stale reservations expire (crashed proxy) and are closed, not left blocking
  PERFORM public.ai_reserve(a, 'req-00000013', 'chat', 'gemini-2.5-flash', 0.001);
  UPDATE public.ai_usage_ledger SET created_at = now() - interval '10 minutes' WHERE user_id = a AND request_id = 'req-00000013';
  PERFORM public.ai_reserve(b, 'req-00000012', 'chat', 'gemini-2.5-flash', 0.001);
  SELECT count(*) INTO n FROM public.ai_usage_ledger WHERE user_id = a AND request_id = 'req-00000013' AND status = 'failed' AND error_code = 'expired';
  IF n = 1 THEN passes := passes + 1; ELSE fails := fails || E'\n stale reservation not expired'; END IF;

  -- 14. privileges: clients cannot call the functions or write the ledger
  IF has_function_privilege('authenticated', 'public.ai_reserve(uuid,text,text,text,numeric)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ai_reserve(uuid,text,text,text,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ai_settle(uuid,text,integer,integer,integer,text,integer,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ai_settle(uuid,text,integer,integer,integer,text,integer,text)', 'EXECUTE') THEN
    fails := fails || E'\n client roles can EXECUTE ai_reserve/ai_settle';
  ELSE passes := passes + 1; END IF;
  IF NOT has_function_privilege('service_role', 'public.ai_reserve(uuid,text,text,text,numeric)', 'EXECUTE') THEN
    fails := fails || E'\n service_role cannot EXECUTE ai_reserve';
  ELSE passes := passes + 1; END IF;
  IF has_table_privilege('authenticated', 'public.ai_usage_ledger', 'INSERT')
     OR has_table_privilege('authenticated', 'public.ai_usage_ledger', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.ai_usage_ledger', 'DELETE')
     OR has_table_privilege('anon', 'public.ai_usage_ledger', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ai_budget_config', 'SELECT') THEN
    fails := fails || E'\n ledger/config privileges too broad';
  ELSE passes := passes + 1; END IF;

  -- 15. RLS: a user sees only their own ledger rows
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.ai_usage_ledger WHERE user_id = b;
  IF n <> 0 THEN fails := fails || E'\n RLS leak: user a sees ' || n || ' rows of user b'; ELSE passes := passes + 1; END IF;
  SELECT count(*) INTO n FROM public.ai_usage_ledger WHERE user_id = a;
  IF n = 0 THEN fails := fails || E'\n RLS: user a cannot see own rows'; ELSE passes := passes + 1; END IF;
  RESET ROLE;

  IF fails <> '' THEN
    RAISE EXCEPTION 'AI BUDGET FAIL (% passed):%', passes, fails;
  END IF;
  RAISE NOTICE 'AI BUDGET OK: % checks passed', passes;
END
$test$;

ROLLBACK;
