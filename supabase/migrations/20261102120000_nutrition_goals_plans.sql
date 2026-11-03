-- Nutrition phase 2: setup-wizard goal settings (one row per user) and weekday macro plans.
-- Additive and idempotent. Every client write sends every NOT NULL column explicitly.
-- Safe to apply AFTER the app ships: until then the app treats the missing tables as "not ready" and keeps
-- the writes queued (retry with backoff, nothing dropped). No sync_tombstones change: plans are soft-deleted.

-- a. nutrition_goal_settings: the wizard answers. The client derives the id from the user, so one row per user.
CREATE TABLE IF NOT EXISTS public.nutrition_goal_settings (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  goal               text NOT NULL DEFAULT 'maintain' CHECK (goal IN ('lose','maintain','gain')),
  sex                text NOT NULL DEFAULT 'male' CHECK (sex IN ('male','female')),
  age                integer NOT NULL DEFAULT 30 CHECK (age BETWEEN 0 AND 120),
  height_inches      numeric NOT NULL DEFAULT 0 CHECK (height_inches >= 0),
  current_weight_lbs numeric NOT NULL DEFAULT 0 CHECK (current_weight_lbs >= 0),
  target_weight_lbs  numeric NOT NULL DEFAULT 0 CHECK (target_weight_lbs >= 0),
  weekly_rate_lbs    numeric NOT NULL DEFAULT 0 CHECK (weekly_rate_lbs >= 0),
  activity_level     text NOT NULL DEFAULT 'lightlyActive'
                       CHECK (activity_level IN ('sedentary','lightlyActive','active','veryActive')),
  lifts_weights      boolean NOT NULL DEFAULT false,
  unit               text NOT NULL DEFAULT 'lb' CHECK (unit IN ('lb','kg')),
  completed_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id)
);

-- b. nutrition_plans: macro plans, each covering some weekdays (bit 0 = Sunday ... bit 6 = Saturday).
--    Soft-deleted (is_archived) so a delete never needs a tombstone.
CREATE TABLE IF NOT EXISTS public.nutrition_plans (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name            text NOT NULL,
  weekday_mask    integer NOT NULL DEFAULT 0 CHECK (weekday_mask BETWEEN 0 AND 127),
  protein_g       numeric NOT NULL DEFAULT 0 CHECK (protein_g >= 0),
  carbs_g         numeric NOT NULL DEFAULT 0 CHECK (carbs_g >= 0),
  fat_g           numeric NOT NULL DEFAULT 0 CHECK (fat_g >= 0),
  kcal            numeric NOT NULL DEFAULT 0 CHECK (kcal >= 0),
  kcal_overridden boolean NOT NULL DEFAULT false,
  sort_order      integer NOT NULL DEFAULT 0,
  is_archived     boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_nutrition_plans_user_order
  ON public.nutrition_plans(user_id, sort_order);

-- c. RLS: own rows only
ALTER TABLE public.nutrition_goal_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_plans         ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own nutrition goal settings" ON public.nutrition_goal_settings;
CREATE POLICY "Users manage own nutrition goal settings"
  ON public.nutrition_goal_settings FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.nutrition_goal_settings TO authenticated;

DROP POLICY IF EXISTS "Users manage own nutrition plans" ON public.nutrition_plans;
CREATE POLICY "Users manage own nutrition plans"
  ON public.nutrition_plans FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.nutrition_plans TO authenticated;
