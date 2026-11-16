-- 20261105120000 revoked anon access and TRUNCATE/TRIGGER/REFERENCES (for authenticated) on every public table
-- that existed then. The tables created afterwards (nutrition kitchen 20261108, weigh-ins 20261110) were given
-- GRANT ALL to authenticated, which includes TRUNCATE, and TRUNCATE ignores RLS: any signed-in user could empty
-- everyone's rows. This repeats the same hardening for them. Idempotent; safe to re-run.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['food_collections', 'food_collection_items', 'weigh_ins'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', t);
      EXECUTE format('REVOKE TRUNCATE, TRIGGER, REFERENCES ON public.%I FROM authenticated', t);
    END IF;
  END LOOP;
END $$;
