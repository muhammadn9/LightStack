-- Phase 3B: let ai-proxy give back a rate-limit slot when the upstream call fails
-- (5xx / timeout). ADDITIVE and idempotent.
-- Callable ONLY by service_role (the Edge Function, with the user id it verified):
-- signed-in clients must not be able to call it, or they could dodge the limit.
-- Deletes the user's newest row for the endpoint from the last 2 minutes.
CREATE OR REPLACE FUNCTION public.refund_rate_limit(p_user_id uuid, p_endpoint text DEFAULT 'coach')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM public.rate_limits
  WHERE id = (
    SELECT id FROM public.rate_limits
    WHERE user_id = p_user_id
      AND endpoint = p_endpoint
      AND requested_at >= now() - interval '2 minutes'
    ORDER BY requested_at DESC
    LIMIT 1
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.refund_rate_limit(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refund_rate_limit(uuid, text) TO service_role;
