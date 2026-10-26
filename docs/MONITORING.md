# Monitoring — what to watch

What can go wrong with the running service and the app around it, where to look today,
and what to do about it. Today these are checked by hand in each tool's own dashboard.
This list is the spec for **the dashboard to come**: one page pulling together PostHog
(the app), website visits (playunspool.com), ad campaigns and Supabase usage, so these
signals sit side by side instead of in five tabs.

Add a signal here whenever a feature brings a new way to fail.

## Where the numbers live today

| Source | What it knows | Where |
|---|---|---|
| PostHog | App sessions and runs (`run_started`, `run_ended`; [`ANALYTICS.md`](ANALYTICS.md)) | PostHog project |
| Supabase | Edge Function invocations, status codes and logs; database size; project status | [Project dashboard](https://supabase.com/dashboard/project/hqdcmuxownykfzmnhmbb) → Edge Functions → `tmdb` |
| Supabase advisors | Security and performance issues in the database | `npx --yes supabase@2 db advisors --linked` |
| Website analytics | Visits to playunspool.com | The site's host |
| Ad platforms | Campaign spend, installs | Each platform (none yet) |

## Signals

### The proxy is being used by something other than the app
The publishable key ships in the app, so anyone can extract it and call the `tmdb`
function. The function only answers the five lookups the app makes, mostly from the
cache, so the worst case is load, not a leak.
- **Watch:** `tmdb` invocations per day against app sessions per day (PostHog). A cold
  launch makes up to ~24 requests, fewer once the deal pool is saved on the phone, and
  each turn makes one. Invocations growing much faster than sessions means someone else
  is calling it. A run of `401`s (no or wrong key) means someone is probing.
- **If it happens:** add a per-device rate limit to the function. Rotating the
  publishable key works too, but every installed app carries the old one, so it breaks
  old builds until people update.

### The cache isn't working
- **Watch:** `cache read failed` / `cache write failed` in the `tmdb` logs (the function
  logs both), and requests that never come back as `X-Cache: hit`. A healthy cache
  makes repeat requests fast (~0.4s against ~2s from TMDB).
- **Seen once:** the first deploy cached nothing because the table had no grant for the
  service role. Fixed by a migration; the log lines were added because of it.

### TMDB is refusing or failing
- **Watch:** `TMDB answered 429` (rate limited) or `5xx` responses from the function, and
  `stale` serves (the function falling back to an expired copy).
- **If it happens:** longer cache lifetimes for the affected route, and check TMDB's
  status. Persistent 429s mean the proxy's single IP has hit TMDB's per-IP limit (~40
  requests a second).

### The project is paused (free plan)
Supabase pauses a free project after a week with no requests. While paused, the proxy
is down: phones with a saved deal pool can deal but can't load a turn, and a new player
sees "Out of film".
- **Watch:** the project's status in the dashboard; Supabase emails before pausing.
- **Decide before the beta:** move to the Pro plan (no pausing) or schedule a keep-alive
  request. Once people play daily, the pause can't trigger.

### No daily start published ahead
Phones fetch the week ahead. A day with no row plays the app's fallback list, which is
the same on every phone of the same build but may differ between builds, and a fix to
that day can then only reach players through a new row.
- **Watch:** the highest `number` for `daily_start` in `public.puzzles` against today's
  number (`firstDay` is 2026-10-26 = #1). Keep at least seven days ahead.
- **If it happens:** insert the missing days ([`ARCHITECTURE.md`](ARCHITECTURE.md#daily-start--dailystartswift)).

### Results aren't arriving, or are being forged
- **Watch:** rows in `public.results` per day against `run_ended` in PostHog (they
  should track each other, minus demo and offline-for-good runs); `insert failed` in the
  `results` function's logs; a run of `422`s (an app/function mismatch after a change to
  either, or someone hand-making requests). `app_version` ending `-debug` is development
  play: leave it out of any stat.
- **If forged runs appear:** the function checks shape only. Re-check links against the
  TMDB cache before storing, or drop the device's rows.

### A schema change opened something
- **Watch:** the advisors, before every schema change ships ([`ROADMAP.md`](ROADMAP.md)
  0.8.0's safety rules). Clean as of 2026-10-26.
