-- Players. Every install signs in anonymously on first use (the app's
-- PlayerSession), so a player is an `auth.users` row from day one, and signing
-- in at 0.9.0 links a provider to that same user. Everything that stores a
-- player stores that id and nothing else: never an email, never a device id.

-- A run belongs to the player the `results` function reads from the caller's
-- token. Rows from before this held a random per-device id; they stay, as
-- players nobody can sign in as.
alter table public.results rename column device_id to player_id;
alter index public.results_one_daily_per_device rename to results_one_daily_per_player;
comment on column public.results.player_id is
  'auth.users id of the run''s player (from the token); older rows hold a per-device id';

-- The name a player goes by on challenges ("What should friends call you?").
-- Not unique and not searchable. A player reads and writes only their own row;
-- links still carry the name, so nobody needs to read anyone else's yet.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40)
);

alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select, insert (id, display_name), update (display_name) on public.profiles to authenticated;

create policy "Players read their own profile" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "Players create their own profile" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy "Players rename themselves" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
