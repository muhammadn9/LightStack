-- Nutrition (Phase 1): targets, saved foods and the daily diary.
-- Additive and idempotent. Every client write sends every NOT NULL column explicitly.
-- NOT YET APPLIED: apply with Supabase MCP apply_migration or the SQL editor, then check list_migrations.

-- a. nutrition_targets: daily goals, versioned by effective date
CREATE TABLE IF NOT EXISTS public.nutrition_targets (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  effective_date  date NOT NULL,
  kcal            numeric NOT NULL DEFAULT 0 CHECK (kcal >= 0),
  protein_g       numeric NOT NULL DEFAULT 0 CHECK (protein_g >= 0),
  carbs_g         numeric NOT NULL DEFAULT 0 CHECK (carbs_g >= 0),
  fat_g           numeric NOT NULL DEFAULT 0 CHECK (fat_g >= 0),
  kcal_overridden boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_nutrition_targets_user_date
  ON public.nutrition_targets(user_id, effective_date);

-- b. foods: saved foods, values per serving (micros nullable: null = unknown, not 0)
CREATE TABLE IF NOT EXISTS public.foods (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name           text NOT NULL,
  brand          text,
  serving_label  text NOT NULL DEFAULT 'serving',
  serving_unit   text NOT NULL DEFAULT 'serving',
  serving_amount numeric NOT NULL DEFAULT 1 CHECK (serving_amount > 0),
  serving_grams  numeric CHECK (serving_grams IS NULL OR serving_grams > 0),
  kcal           numeric NOT NULL DEFAULT 0 CHECK (kcal >= 0),
  protein_g      numeric NOT NULL DEFAULT 0 CHECK (protein_g >= 0),
  carbs_g        numeric NOT NULL DEFAULT 0 CHECK (carbs_g >= 0),
  fat_g          numeric NOT NULL DEFAULT 0 CHECK (fat_g >= 0),
  fiber_g        numeric,
  sugar_g        numeric,
  added_sugar_g  numeric,
  sat_fat_g      numeric,
  trans_fat_g    numeric,
  cholesterol_mg numeric,
  sodium_mg      numeric,
  potassium_mg   numeric,
  calcium_mg     numeric,
  iron_mg        numeric,
  vitamin_d_mcg  numeric,
  other_micros   jsonb NOT NULL DEFAULT '{}'::jsonb,
  source         text NOT NULL DEFAULT 'quick' CHECK (source IN ('quick','scan')),
  is_favorite    boolean NOT NULL DEFAULT false,
  last_used_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_foods_user_last_used
  ON public.foods(user_id, last_used_at);

-- c. food_entries: what was eaten, with a per-serving snapshot of the values
CREATE TABLE IF NOT EXISTS public.food_entries (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date           date NOT NULL,
  food_id        uuid REFERENCES public.foods(id) ON DELETE SET NULL,
  name           text NOT NULL DEFAULT '',
  servings       numeric NOT NULL DEFAULT 1 CHECK (servings >= 0),
  serving_label  text NOT NULL DEFAULT 'serving',
  kcal           numeric NOT NULL DEFAULT 0 CHECK (kcal >= 0),
  protein_g      numeric NOT NULL DEFAULT 0 CHECK (protein_g >= 0),
  carbs_g        numeric NOT NULL DEFAULT 0 CHECK (carbs_g >= 0),
  fat_g          numeric NOT NULL DEFAULT 0 CHECK (fat_g >= 0),
  fiber_g        numeric,
  sugar_g        numeric,
  added_sugar_g  numeric,
  sat_fat_g      numeric,
  trans_fat_g    numeric,
  cholesterol_mg numeric,
  sodium_mg      numeric,
  potassium_mg   numeric,
  calcium_mg     numeric,
  iron_mg        numeric,
  vitamin_d_mcg  numeric,
  other_micros   jsonb NOT NULL DEFAULT '{}'::jsonb,
  source         text NOT NULL DEFAULT 'quick' CHECK (source IN ('quick','saved','scan')),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_food_entries_user_date
  ON public.food_entries(user_id, date);
CREATE INDEX IF NOT EXISTS idx_food_entries_food
  ON public.food_entries(food_id);

-- d. RLS: own rows only
ALTER TABLE public.nutrition_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.foods             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.food_entries      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own nutrition targets" ON public.nutrition_targets;
CREATE POLICY "Users manage own nutrition targets"
  ON public.nutrition_targets FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.nutrition_targets TO authenticated;

DROP POLICY IF EXISTS "Users manage own foods" ON public.foods;
CREATE POLICY "Users manage own foods"
  ON public.foods FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.foods TO authenticated;

DROP POLICY IF EXISTS "Users manage own food entries" ON public.food_entries;
CREATE POLICY "Users manage own food entries"
  ON public.food_entries FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.food_entries TO authenticated;

-- e. sync_tombstones: allow the new entities (replaces the CHECK; the existing name is the Postgres default)
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
       'nutrition_target','food','food_entry'));
END $$;
