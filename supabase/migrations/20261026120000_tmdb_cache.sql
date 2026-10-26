-- The TMDB proxy's response cache. One upstream fetch of a near-static response
-- (the deal pool, a cast, a filmography) serves every player until it expires.
--
-- Only the `tmdb` Edge Function touches this table, with the service role. RLS is
-- on with no policies and the public roles have no grants, so the app's
-- publishable key can neither read nor write it.

create table public.tmdb_cache (
  -- The TMDB path plus its sorted query string.
  key text primary key,
  -- The response exactly as TMDB sent it.
  body text not null,
  fetched_at timestamptz not null default now(),
  -- Well inside the six months TMDB's terms (§1.C) allow a response to be kept.
  expires_at timestamptz not null
);

alter table public.tmdb_cache enable row level security;
revoke all on public.tmdb_cache from anon, authenticated;
