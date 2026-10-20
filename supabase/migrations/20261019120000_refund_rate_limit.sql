-- Phase 3B: let ai-proxy give back a rate-limit slot when the upstream call fails
-- (5xx / timeout), so users are not charged for failures. ADDITIVE and idempotent.
-- Deletes only the caller's (auth.uid()) newest 'coach' row from the last 2 minutes.
CREATE OR REPLACE FUNCTION public.refund_rate_limit(p_endpoint text DEFAULT 'coach')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM public.rate_limits
  WHERE id = (
    SELECT id FROM public.rate_limits
    WHERE user_id = v_user_id
      AND endpoint = p_endpoint
      AND requested_at >= now() - interval '2 minutes'
    ORDER BY requested_at DESC
    LIMIT 1
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.refund_rate_limit(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refund_rate_limit(text) TO authenticated;
