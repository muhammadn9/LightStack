-- Phase 2.1: sync consistency. ADDITIVE and idempotent; drops no table, column or row.
-- Supersedes add_cardio_set_fields (never applied to production).
-- Applied as one transaction by the runner (apply_migration / SQL editor runs the file atomically).

-- a. Cardio set fields (types match WorkoutSet.swift: Int?, Double?, Double?)
ALTER TABLE public.sets
  ADD COLUMN IF NOT EXISTS duration_seconds integer,
  ADD COLUMN IF NOT EXISTS distance_miles   numeric,
  ADD COLUMN IF NOT EXISTS incline_level    numeric;

-- b. profiles.custom_equipment
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS custom_equipment text;

-- c. workouts.setup_note, updated_at + trigger
ALTER TABLE public.workouts
  ADD COLUMN IF NOT EXISTS setup_note text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS update_workouts_updated_at ON public.workouts;
CREATE TRIGGER update_workouts_updated_at
  BEFORE UPDATE ON public.workouts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- d. FKs to workouts: ON DELETE SET NULL (only altered if not already 'n')
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conname = 'personal_records_workout_id_fkey'
               AND conrelid = 'public.personal_records'::regclass
               AND confdeltype <> 'n') THEN
    ALTER TABLE public.personal_records DROP CONSTRAINT personal_records_workout_id_fkey;
    ALTER TABLE public.personal_records
      ADD CONSTRAINT personal_records_workout_id_fkey
      FOREIGN KEY (workout_id) REFERENCES public.workouts(id) ON DELETE SET NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conname = 'planned_sessions_workout_id_fkey'
               AND conrelid = 'public.planned_sessions'::regclass
               AND confdeltype <> 'n') THEN
    ALTER TABLE public.planned_sessions DROP CONSTRAINT planned_sessions_workout_id_fkey;
    ALTER TABLE public.planned_sessions
      ADD CONSTRAINT planned_sessions_workout_id_fkey
      FOREIGN KEY (workout_id) REFERENCES public.workouts(id) ON DELETE SET NULL;
  END IF;
END $$;

-- e. sync_tombstones: client-recorded deletions so other devices can apply them
CREATE TABLE IF NOT EXISTS public.sync_tombstones (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  entity     text NOT NULL CHECK (entity IN
               ('workout','exercise','set','personal_record','month_plan','planned_session','rest_day')),
  record_id  uuid NOT NULL,
  deleted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, entity, record_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_tombstones_user_deleted
  ON public.sync_tombstones(user_id, deleted_at);
ALTER TABLE public.sync_tombstones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own tombstones" ON public.sync_tombstones;
CREATE POLICY "Users read own tombstones"
  ON public.sync_tombstones FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users insert own tombstones" ON public.sync_tombstones;
CREATE POLICY "Users insert own tombstones"
  ON public.sync_tombstones FOR INSERT
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT ON public.sync_tombstones TO authenticated;

-- f. rest_days (matches CDRestDay: id, userId, date, createdAt)
CREATE TABLE IF NOT EXISTS public.rest_days (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date       date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, date)
);
ALTER TABLE public.rest_days ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own rest days" ON public.rest_days;
CREATE POLICY "Users manage own rest days"
  ON public.rest_days FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT ALL ON public.rest_days TO authenticated;

-- Delta sync / restore support
CREATE INDEX IF NOT EXISTS idx_workouts_user_updated ON public.workouts(user_id, updated_at);

-- g. personal_records(user_id, exercise_name): already covered by idx_prs_exercise
--    (same columns). Created only if absent, so a no-op in production.
CREATE INDEX IF NOT EXISTS idx_prs_exercise
  ON public.personal_records(user_id, exercise_name);
