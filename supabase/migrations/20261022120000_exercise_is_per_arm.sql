-- Per-arm (single-side) exercises: logged weight is per arm/side.
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_per_arm boolean NOT NULL DEFAULT false;
