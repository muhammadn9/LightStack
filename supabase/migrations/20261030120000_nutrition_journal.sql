-- Nutrition journal: configurable meals, water log, day notes, and food_entries.meal_slot_id.
-- Additive and idempotent. Every client write sends every NOT NULL column explicitly.
-- Apply BEFORE shipping a build that sends meal_slot_id / writes these tables.

-- a. meal_slots: user-configurable daily meals. Soft-deleted (is_archived) so old entries keep their meal.
CREATE TABLE IF NOT EXISTS public.meal_slots (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  sort_order  integer NOT NULL DEFAULT 0,
  is_archived boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_meal_slots_user_order
  ON public.meal_slots(user_id, sort_order);

-- b. water_entries: one row per log; amount_ml is the canonical unit
CREATE TABLE IF NOT EXISTS public.water_entries (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        date NOT NULL,
  amount_ml   numeric NOT NULL DEFAULT 0 CHECK (amount_ml >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_water_entries_user_date
  ON public.water_entries(user_id, date);

-- c. day_notes: one note per user per day
CREATE TABLE IF NOT EXISTS public.day_notes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        date NOT NULL,
  text        text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, date)
);

-- d. food_entries -> meal slot (null = logged before meal slots existed)
ALTER TABLE public.food_entries
  ADD COLUMN IF NOT EXISTS meal_slot_id uuid REFERENCES public.meal_slots(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_food_entries_meal_slot
  ON public.food_entries(meal_slot_id);

-- e. RLS: own rows only
ALTER TABLE public.meal_slots    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.water_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.day_notes     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own meal slots" ON public.meal_slots;
CREATE POLICY "Users manage own meal slots"
  ON public.meal_slots FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.meal_slots TO authenticated;

DROP POLICY IF EXISTS "Users manage own water entries" ON public.water_entries;
CREATE POLICY "Users manage own water entries"
  ON public.water_entries FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.water_entries TO authenticated;

DROP POLICY IF EXISTS "Users manage own day notes" ON public.day_notes;
CREATE POLICY "Users manage own day notes"
  ON public.day_notes FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.day_notes TO authenticated;

-- f. sync_tombstones: allow the new entities (keeps every existing value)
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
       'nutrition_target','food','food_entry','meal_slot','water_entry','day_note'));
END $$;
