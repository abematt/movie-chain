-- Every finished run, sent by the app at game over: the per-day stats ("today's
-- average") and the answer data (which actors and films players actually name)
-- come from here. Runs are identified by the device id, not a person.
--
--   mode        'daily_start' for a daily (with `number`), else 'endless'
--   number      the daily's number; null for an ordinary run
--   chain       the run in order, start first:
--                 [{"kind": "actor", "id": 31},
--                  {"kind": "movie", "id": 13, "seconds": 4.2}, ...]
--               ids are TMDB ids; `seconds` is the clock time the link took
--   links       accepted links (chain length minus the start)
--   points      as the app scored them; speed can't be checked, so not verified
--
-- Only the `results` Edge Function writes here, with the service role, after
-- checking the run's shape. RLS is on with no policies and the public roles have
-- no grants, so the app's publishable key can neither read nor write it.

create table public.results (
  id bigint generated always as identity primary key,
  device_id uuid not null,
  mode text not null check (mode in ('endless', 'daily_start')),
  number integer check (number >= 1),
  chain jsonb not null check (jsonb_typeof(chain) = 'array'),
  links integer not null check (links >= 0),
  points integer not null check (points >= 0),
  ended_by_quit boolean not null,
  app_version text not null,
  received_at timestamptz not null default now(),
  check ((mode = 'daily_start') = (number is not null))
);

-- One result per daily per device; the app sends a daily once, and a resend is
-- ignored rather than counted twice.
create unique index results_one_daily_per_device
  on public.results (device_id, number) where mode = 'daily_start';
create index results_by_day on public.results (number) where mode = 'daily_start';

alter table public.results enable row level security;
revoke all on public.results from anon, authenticated;
grant select, insert on public.results to service_role;
-- The function checks a daily's start against `puzzles`, which the service role
-- couldn't read (new tables get no grants here).
grant select on public.puzzles to service_role;
