-- Nutrition phase 6: weigh-ins (Dashboard weight logging).
-- Additive and idempotent. Every client write sends every NOT NULL column explicitly.
--
-- weigh_ins: one body-weight log per user per local day (UNIQUE (user_id, date)). weight_lbs is the canonical
-- unit; the kg/lb display is only a preference. The client upserts with ON CONFLICT (user_id, date), so two devices
-- that log the same day end up with one row and never a duplicate-key failure. Deleting a weigh-in is recorded
-- in sync_tombstones (entity 'weigh_in'), like water entries.
--
-- Apply BEFORE shipping a build that logs weight. Until then the app keeps those writes queued and retries
-- (missing table / tombstone check are classified as "not ready yet", not dead-lettered).

-- a. weigh_ins
CREATE TABLE IF NOT EXISTS public.weigh_ins (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        date NOT NULL,
  weight_lbs  numeric NOT NULL CHECK (weight_lbs > 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, date)
);
CREATE INDEX IF NOT EXISTS idx_weigh_ins_user_date
  ON public.weigh_ins(user_id, date);

-- b. RLS: own rows only
ALTER TABLE public.weigh_ins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own weigh ins" ON public.weigh_ins;
CREATE POLICY "Users manage own weigh ins"
  ON public.weigh_ins FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.weigh_ins TO authenticated;

-- c. sync_tombstones: allow the new entity (keeps every existing value)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conrelid = 'public.sync_tombstones'::regclass
               AND conname = 'sync_tombstones_entity_check') THEN
    ALTER TABLE public.sync_tombstones DROP CONSTRAINT sync_tombstones_entity_check;
  END IF;
  ALTER TABLE public.sync_tombstones
    ADD CONSTRAINT sync_tombstones_entity_check CHECK (entity IN
      ('workout','exercise','set','personal_record','month_plan','planned_session','rest_day',
       'nutrition_target','food','food_entry','meal_slot','water_entry','day_note',
       'food_collection','food_collection_item','weigh_in'));
END $$;
