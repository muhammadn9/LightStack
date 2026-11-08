-- AI spending controls: usage ledger, editable budgets, concurrency-safe reservation.
-- ADDITIVE and idempotent. Written only by the ai-proxy Edge Function (service role).
-- Rows hold ids, token counts and USD only. Raw prompts / responses are NEVER stored.

-- ============================================================
-- Budget config: ONE row, edited in the Supabase dashboard / SQL editor. No app release needed.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ai_budget_config (
  id                     boolean PRIMARY KEY DEFAULT true CHECK (id),   -- singleton
  ai_enabled             boolean NOT NULL DEFAULT true,                 -- kill switch
  per_user_daily_usd     numeric(10,4) NOT NULL DEFAULT 0.50,           -- PLACEHOLDER: tune to your pricing
  per_user_monthly_usd   numeric(10,4) NOT NULL DEFAULT 5.00,           -- PLACEHOLDER
  global_daily_usd       numeric(10,2) NOT NULL DEFAULT 25.00,          -- PLACEHOLDER
  global_monthly_usd     numeric(10,2) NOT NULL DEFAULT 300.00,         -- PLACEHOLDER
  max_concurrent_per_user integer NOT NULL DEFAULT 2 CHECK (max_concurrent_per_user >= 1),
  -- USD per 1,000,000 tokens. "thinking" is billed at the output rate for Gemini.
  -- PLACEHOLDER PRICES: verify against https://ai.google.dev/gemini-api/docs/pricing before launch.
  -- gemini-2.5-flash figures are the published paid-tier list price as last known; gemini-3.5-flash is a guess.
  prices                 jsonb NOT NULL DEFAULT '{
    "gemini-2.5-flash": {"input": 0.30, "output": 2.50, "thinking": 2.50},
    "gemini-3.5-flash": {"input": 0.50, "output": 3.00, "thinking": 3.00}
  }'::jsonb,
  updated_at             timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.ai_budget_config (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.ai_budget_config ENABLE ROW LEVEL SECURITY;
-- No policies: invisible to anon/authenticated. service_role and the dashboard bypass RLS.
REVOKE ALL ON public.ai_budget_config FROM PUBLIC, anon, authenticated;

-- ============================================================
-- Usage ledger
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ai_usage_ledger (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id       text NOT NULL,                       -- client UUID, reused across retries/fallback
  task             text NOT NULL,
  model            text NOT NULL,
  input_tokens     integer,
  output_tokens    integer,
  thinking_tokens  integer,
  reserved_usd     numeric(12,6) NOT NULL DEFAULT 0,
  actual_usd       numeric(12,6) NOT NULL DEFAULT 0,
  status           text NOT NULL DEFAULT 'reserved'
                   CHECK (status IN ('reserved','succeeded','failed','refunded')),
  latency_ms       integer,
  error_code       text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  -- Scoped per user so one user's request ids can never collide with (or probe) another's.
  CONSTRAINT ai_usage_ledger_user_request_key UNIQUE (user_id, request_id)
);

CREATE INDEX IF NOT EXISTS ai_usage_ledger_user_created_idx ON public.ai_usage_ledger (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_usage_ledger_created_idx ON public.ai_usage_ledger (created_at DESC);
CREATE INDEX IF NOT EXISTS ai_usage_ledger_reserved_idx ON public.ai_usage_ledger (user_id) WHERE status = 'reserved';

ALTER TABLE public.ai_usage_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_usage_ledger_select_own" ON public.ai_usage_ledger;
CREATE POLICY "ai_usage_ledger_select_own" ON public.ai_usage_ledger
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);
-- No INSERT/UPDATE/DELETE policies: only the service role (edge function) writes.

REVOKE ALL ON public.ai_usage_ledger FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ai_usage_ledger TO authenticated;

-- ============================================================
-- ai_reserve: check budgets and reserve, atomically.
-- Locks: global first, then per user (always this order, so no deadlocks). Every reservation
-- is serialised on the global lock for a few milliseconds; that is what makes the global caps exact.
-- Returns {"ok":true,"reused":bool} or {"ok":false,"reason":...} with reason one of
-- ai_disabled | too_many_in_flight | budget_user_daily | budget_user_monthly | budget_global |
-- duplicate_in_flight | duplicate_completed | invalid_args.
-- Cost counted against a budget: reserved_usd while status = 'reserved', else actual_usd.
-- Idempotent on (user, request_id): a failed/refunded request (e.g. primary model 503) may be
-- reserved again by the fallback attempt with the same id; it is the same ledger row, never counted twice.
-- ============================================================
CREATE OR REPLACE FUNCTION public.ai_reserve(
  p_user uuid,
  p_request_id text,
  p_task text,
  p_model text,
  p_reserve_usd numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  cfg           public.ai_budget_config%ROWTYPE;
  ex            public.ai_usage_ledger%ROWTYPE;
  v_day_start   timestamptz := date_trunc('day',   now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_month_start timestamptz := date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_exclude     uuid;
  v_inflight    integer;
  v_u_day       numeric;
  v_u_month     numeric;
  v_g_day       numeric;
  v_g_month     numeric;
BEGIN
  IF p_user IS NULL OR p_request_id IS NULL OR length(p_request_id) = 0
     OR p_task IS NULL OR p_model IS NULL OR p_reserve_usd IS NULL OR p_reserve_usd < 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_args');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('ai_budget_global', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended('ai_budget_user:' || p_user::text, 0));

  -- Crashed requests: a reservation older than 3 minutes (upstream timeout is 45s) is closed,
  -- charged at its reserved amount to stay conservative.
  UPDATE public.ai_usage_ledger
     SET status = 'failed', actual_usd = reserved_usd, error_code = 'expired'
   WHERE status = 'reserved' AND created_at < now() - interval '3 minutes';

  SELECT * INTO cfg FROM public.ai_budget_config WHERE id;
  IF NOT FOUND OR NOT cfg.ai_enabled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ai_disabled');
  END IF;

  SELECT * INTO ex FROM public.ai_usage_ledger
   WHERE user_id = p_user AND request_id = p_request_id FOR UPDATE;
  IF FOUND THEN
    IF ex.status = 'reserved'  THEN RETURN jsonb_build_object('ok', false, 'reason', 'duplicate_in_flight'); END IF;
    IF ex.status = 'succeeded' THEN RETURN jsonb_build_object('ok', false, 'reason', 'duplicate_completed'); END IF;
    -- A failed row that was charged (timeout / expired: Gemini may have billed it) is final.
    -- Re-reserving it would reset actual_usd to 0 and erase that charge.
    IF ex.actual_usd > 0 THEN RETURN jsonb_build_object('ok', false, 'reason', 'duplicate_completed'); END IF;
    v_exclude := ex.id;   -- failed / refunded: being re-reserved, do not count it twice
  END IF;

  SELECT count(*) INTO v_inflight FROM public.ai_usage_ledger
   WHERE user_id = p_user AND status = 'reserved';
  IF v_inflight >= cfg.max_concurrent_per_user THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'too_many_in_flight');
  END IF;

  SELECT
    COALESCE(sum(CASE WHEN status = 'reserved' THEN reserved_usd ELSE actual_usd END)
             FILTER (WHERE user_id = p_user AND created_at >= v_day_start), 0),
    COALESCE(sum(CASE WHEN status = 'reserved' THEN reserved_usd ELSE actual_usd END)
             FILTER (WHERE user_id = p_user), 0),
    COALESCE(sum(CASE WHEN status = 'reserved' THEN reserved_usd ELSE actual_usd END)
             FILTER (WHERE created_at >= v_day_start), 0),
    COALESCE(sum(CASE WHEN status = 'reserved' THEN reserved_usd ELSE actual_usd END), 0)
  INTO v_u_day, v_u_month, v_g_day, v_g_month
  FROM public.ai_usage_ledger
  WHERE created_at >= v_month_start
    AND (v_exclude IS NULL OR id <> v_exclude);

  IF v_u_day + p_reserve_usd > cfg.per_user_daily_usd THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'budget_user_daily');
  END IF;
  IF v_u_month + p_reserve_usd > cfg.per_user_monthly_usd THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'budget_user_monthly');
  END IF;
  IF v_g_day + p_reserve_usd > cfg.global_daily_usd
     OR v_g_month + p_reserve_usd > cfg.global_monthly_usd THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'budget_global');
  END IF;

  IF v_exclude IS NOT NULL THEN
    UPDATE public.ai_usage_ledger
       SET status = 'reserved', task = p_task, model = p_model, reserved_usd = p_reserve_usd,
           actual_usd = 0, input_tokens = NULL, output_tokens = NULL, thinking_tokens = NULL,
           latency_ms = NULL, error_code = NULL, created_at = now()
     WHERE id = v_exclude;
    RETURN jsonb_build_object('ok', true, 'reused', true);
  END IF;

  INSERT INTO public.ai_usage_ledger (user_id, request_id, task, model, reserved_usd, status)
  VALUES (p_user, p_request_id, p_task, p_model, p_reserve_usd, 'reserved');
  RETURN jsonb_build_object('ok', true, 'reused', false);
END;
$$;

-- ============================================================
-- ai_settle: close a reservation with the real token counts.
-- succeeded -> actual cost from the price table (tokens / 1e6 * price). If the response had no
--   usage numbers, or the model has no price, the reserved amount is charged (conservative).
-- failed / refunded -> actual cost 0, except failed with error_code 'upstream_timeout' (reserved amount).
-- Only a row still in 'reserved' can be settled, so a repeated call is a harmless no-op.
-- ============================================================
CREATE OR REPLACE FUNCTION public.ai_settle(
  p_user uuid,
  p_request_id text,
  p_input_tokens integer DEFAULT NULL,
  p_output_tokens integer DEFAULT NULL,
  p_thinking_tokens integer DEFAULT NULL,
  p_status text DEFAULT 'succeeded',
  p_latency_ms integer DEFAULT NULL,
  p_error_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r      public.ai_usage_ledger%ROWTYPE;
  v_price jsonb;
  v_actual numeric := 0;
BEGIN
  IF p_status NOT IN ('succeeded', 'failed', 'refunded') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_status');
  END IF;

  SELECT * INTO r FROM public.ai_usage_ledger
   WHERE user_id = p_user AND request_id = p_request_id AND status = 'reserved' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_reserved');
  END IF;

  IF p_status = 'succeeded' THEN
    SELECT prices -> r.model INTO v_price FROM public.ai_budget_config WHERE id;
    IF v_price IS NULL
       OR (p_input_tokens IS NULL AND p_output_tokens IS NULL AND p_thinking_tokens IS NULL) THEN
      v_actual := r.reserved_usd;
    ELSE
      v_actual := (
          COALESCE(p_input_tokens, 0)    * COALESCE((v_price ->> 'input')::numeric, 0)
        + COALESCE(p_output_tokens, 0)   * COALESCE((v_price ->> 'output')::numeric, 0)
        + COALESCE(p_thinking_tokens, 0) * COALESCE((v_price ->> 'thinking')::numeric, (v_price ->> 'output')::numeric, 0)
      ) / 1000000.0;
    END IF;
  ELSIF p_status = 'failed' AND p_error_code = 'upstream_timeout' THEN
    -- The proxy gave up, but Gemini may still finish and bill the call: charge the reservation.
    v_actual := r.reserved_usd;
  END IF;

  UPDATE public.ai_usage_ledger
     SET status = p_status,
         actual_usd = round(v_actual, 6),
         input_tokens = p_input_tokens,
         output_tokens = p_output_tokens,
         thinking_tokens = p_thinking_tokens,
         latency_ms = p_latency_ms,
         error_code = left(p_error_code, 64)
   WHERE id = r.id;

  RETURN jsonb_build_object('ok', true, 'actual_usd', round(v_actual, 6));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ai_reserve(uuid, text, text, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ai_reserve(uuid, text, text, text, numeric) TO service_role;
REVOKE EXECUTE ON FUNCTION public.ai_settle(uuid, text, integer, integer, integer, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ai_settle(uuid, text, integer, integer, integer, text, integer, text) TO service_role;
