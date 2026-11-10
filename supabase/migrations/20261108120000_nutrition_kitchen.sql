-- Nutrition phase 5: Kitchen (saved meals and recipes).
-- Additive and idempotent. Every client write sends every NOT NULL column explicitly.
--
-- food_collections:       one row per saved meal (kind 'meal') or recipe (kind 'recipe').
-- food_collection_items:  the foods inside one, with a servings amount each.
-- A recipe also owns a derived row in public.foods with source 'recipe' (recomputed by the client), which is why
-- foods.source gains that value. Past diary entries keep their own snapshot, so deleting a recipe never edits them.
--
-- Apply BEFORE shipping a build that saves meals/recipes. Until then the app keeps those writes queued and retries
-- (missing table / source check / tombstone check are classified as "not ready yet", not dead-lettered).

-- a. food_collections
CREATE TABLE IF NOT EXISTS public.food_collections (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind            text NOT NULL DEFAULT 'meal' CHECK (kind IN ('meal','recipe')),
  name            text NOT NULL,
  servings_yield  numeric NOT NULL DEFAULT 1 CHECK (servings_yield > 0),
  cooked_weight_g numeric CHECK (cooked_weight_g IS NULL OR cooked_weight_g > 0),
  last_used_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_food_collections_user_kind
  ON public.food_collections(user_id, kind);

-- b. food_collection_items: deleting the collection or the food removes the item.
CREATE TABLE IF NOT EXISTS public.food_collection_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  collection_id uuid NOT NULL REFERENCES public.food_collections(id) ON DELETE CASCADE,
  food_id       uuid NOT NULL REFERENCES public.foods(id) ON DELETE CASCADE,
  servings      numeric NOT NULL DEFAULT 1 CHECK (servings > 0),
  sort_order    integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_food_collection_items_collection
  ON public.food_collection_items(collection_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_food_collection_items_food
  ON public.food_collection_items(food_id);

-- c. RLS: own rows only. Items must also point at the caller's own collection AND food, so a user can never
--    attach another user's food or collection to their own item.
ALTER TABLE public.food_collections      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.food_collection_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own food collections" ON public.food_collections;
CREATE POLICY "Users manage own food collections"
  ON public.food_collections FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
GRANT ALL ON public.food_collections TO authenticated;

DROP POLICY IF EXISTS "Users manage own food collection items" ON public.food_collection_items;
CREATE POLICY "Users manage own food collection items"
  ON public.food_collection_items FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM public.food_collections c WHERE c.id = collection_id AND c.user_id = auth.uid())
    AND EXISTS (SELECT 1 FROM public.foods f WHERE f.id = food_id AND f.user_id = auth.uid())
  );
GRANT ALL ON public.food_collection_items TO authenticated;

-- d. foods.source: add 'recipe' (keeps 'quick', 'scan', 'off' and 'ai').
ALTER TABLE public.foods DROP CONSTRAINT IF EXISTS foods_source_check;
ALTER TABLE public.foods
  ADD CONSTRAINT foods_source_check CHECK (source IN ('quick','scan','off','ai','recipe'));

-- e. sync_tombstones: allow the new entities (keeps every existing value)
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
       'food_collection','food_collection_item'));
END $$;
