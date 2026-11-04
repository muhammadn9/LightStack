-- Nutrition phase 3: branded foods from Open Food Facts.
-- Adds foods.barcode (nullable) and allows foods.source = 'off'. Additive and idempotent.
-- Apply BEFORE shipping a build that saves Open Food Facts foods. Until then the app keeps those foods
-- queued and retries (missing column / source check are classified as "not ready yet", not dead-lettered).

ALTER TABLE public.foods
  ADD COLUMN IF NOT EXISTS barcode text;

-- Local-first barcode lookup and restore: find a user's food by barcode.
CREATE INDEX IF NOT EXISTS idx_foods_user_barcode
  ON public.foods(user_id, barcode)
  WHERE barcode IS NOT NULL;

-- Allow the new source value (keeps 'quick' and 'scan'). The inline CHECK from the original
-- table is auto-named foods_source_check.
ALTER TABLE public.foods DROP CONSTRAINT IF EXISTS foods_source_check;
ALTER TABLE public.foods
  ADD CONSTRAINT foods_source_check CHECK (source IN ('quick','scan','off'));
