-- Migration: add cardio-specific columns to the sets table
-- These columns are nullable so existing strength-exercise rows are unaffected.
-- Run once against the remote Supabase project (lightstack).

ALTER TABLE sets
    ADD COLUMN IF NOT EXISTS duration_seconds integer,
    ADD COLUMN IF NOT EXISTS distance_miles   numeric,
    ADD COLUMN IF NOT EXISTS incline_level    numeric;
