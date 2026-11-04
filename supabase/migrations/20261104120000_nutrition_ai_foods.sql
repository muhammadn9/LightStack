-- Nutrition phase 4: AI meal logging.
-- Allows foods.source = 'ai' and adds foods.ai_sources (jsonb: [{"title","url"}]) and foods.ai_confidence
-- (low | medium | high). Additive and idempotent.
-- Apply BEFORE shipping a build that saves AI-estimated foods. Until then the app keeps those foods queued and
-- retries (missing column / source check are classified as "not ready yet", not dead-lettered).

ALTER TABLE public.foods
  ADD COLUMN IF NOT EXISTS ai_sources jsonb,
  ADD COLUMN IF NOT EXISTS ai_confidence text;

-- Keep confidence to the three values the app writes (NULL allowed).
ALTER TABLE public.foods DROP CONSTRAINT IF EXISTS foods_ai_confidence_check;
ALTER TABLE public.foods
  ADD CONSTRAINT foods_ai_confidence_check CHECK (ai_confidence IS NULL OR ai_confidence IN ('low','medium','high'));

-- Allow the new source value (keeps 'quick', 'scan' and 'off'). The inline CHECK from the original
-- table is auto-named foods_source_check.
ALTER TABLE public.foods DROP CONSTRAINT IF EXISTS foods_source_check;
ALTER TABLE public.foods
  ADD CONSTRAINT foods_source_check CHECK (source IN ('quick','scan','off','ai'));
