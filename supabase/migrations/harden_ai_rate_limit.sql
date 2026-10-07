-- Per-user AI rate limit, enforced server-side by the ai-proxy Edge Function.
-- 10 requests / minute and 100 / day. auth.uid() comes from the caller's JWT,
-- so it cannot be spoofed. Signed-out callers cannot execute it.
CREATE OR REPLACE FUNCTION public.check_rate_limit()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID;
  v_minute     INTEGER;
  v_day        INTEGER;
  v_lock_key   BIGINT;
  v_max_minute INTEGER := 10;
  v_max_day    INTEGER := 100;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('allowed', FALSE, 'reason', 'unauthenticated');
  END IF;

  v_lock_key := ('x' || left(replace(v_user_id::text, '-', ''), 15))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  DELETE FROM rate_limits
  WHERE user_id = v_user_id AND endpoint = 'coach'
    AND requested_at < NOW() - INTERVAL '1 day';

  SELECT COUNT(*) FILTER (WHERE requested_at >= NOW() - INTERVAL '1 minute'),
         COUNT(*)
  INTO v_minute, v_day
  FROM rate_limits
  WHERE user_id = v_user_id AND endpoint = 'coach';

  IF v_minute >= v_max_minute THEN
    RETURN json_build_object('allowed', FALSE, 'reason', 'minute', 'request_count', v_minute);
  END IF;
  IF v_day >= v_max_day THEN
    RETURN json_build_object('allowed', FALSE, 'reason', 'day', 'request_count', v_day);
  END IF;

  INSERT INTO rate_limits (user_id, endpoint, requested_at)
  VALUES (v_user_id, 'coach', NOW());

  RETURN json_build_object('allowed', TRUE, 'request_count', v_minute + 1);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_rate_limit() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_rate_limit() TO authenticated;
