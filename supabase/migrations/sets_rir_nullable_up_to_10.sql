-- Migration: allow unknown RIR (NULL) and RIR up to 10 on the sets table.
-- Already applied to the live project; recorded here for reference.
alter table public.sets alter column rir drop not null;
alter table public.sets drop constraint sets_rir_check;
alter table public.sets add constraint sets_rir_check check (rir is null or (rir between 0 and 10));
