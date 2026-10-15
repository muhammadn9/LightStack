-- ROLLBACK for 20261015120000_phase2_sync_consistency. NOT auto-run; apply by hand only.
-- The new columns/tables are harmless to leave in place, so only the safe parts
-- are active. Destructive parts are commented out.
BEGIN;

DROP TRIGGER IF EXISTS update_workouts_updated_at ON public.workouts;

-- Restore the original NO ACTION FKs (these block workout deletes again).
ALTER TABLE public.personal_records DROP CONSTRAINT IF EXISTS personal_records_workout_id_fkey;
ALTER TABLE public.personal_records
  ADD CONSTRAINT personal_records_workout_id_fkey
  FOREIGN KEY (workout_id) REFERENCES public.workouts(id);

ALTER TABLE public.planned_sessions DROP CONSTRAINT IF EXISTS planned_sessions_workout_id_fkey;
ALTER TABLE public.planned_sessions
  ADD CONSTRAINT planned_sessions_workout_id_fkey
  FOREIGN KEY (workout_id) REFERENCES public.workouts(id);

COMMIT;

-- ============================================================
-- WARNING: DATA LOSS BELOW. Left commented out on purpose.
-- Dropping sets.duration_seconds / distance_miles / incline_level destroys all
-- cardio data; dropping workouts.setup_note and profiles.custom_equipment
-- destroys user-entered notes/equipment; dropping the tables destroys all
-- tombstones and rest days. Only run after taking a backup.
-- ============================================================
-- DROP TABLE IF EXISTS public.sync_tombstones;
-- DROP TABLE IF EXISTS public.rest_days;
-- ALTER TABLE public.sets     DROP COLUMN IF EXISTS duration_seconds,
--                             DROP COLUMN IF EXISTS distance_miles,
--                             DROP COLUMN IF EXISTS incline_level;
-- ALTER TABLE public.profiles DROP COLUMN IF EXISTS custom_equipment;
-- ALTER TABLE public.workouts DROP COLUMN IF EXISTS setup_note,
--                             DROP COLUMN IF EXISTS updated_at;
