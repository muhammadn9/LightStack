-- Supersets: exercises sharing a group id form one superset (2-4 members).
alter table public.exercises add column if not exists superset_group_id uuid;
