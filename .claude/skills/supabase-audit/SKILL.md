---
name: supabase-audit
description: Security review of Unspool's Supabase service — runs scripts/supabase-check.py, then the judgment pass a script can't do (Edge Function abuse paths, what each policy means, the accounts checklist). Use for "/supabase-audit", "audit the service", "is the backend safe", before a milestone that touches the service, before the beta, and before accounts (0.9.0) ship.
---

# /supabase-audit — is the service safe to put in front of strangers?

The publishable key ships in the app, so anyone can extract it. Everything here asks
one question: **what can a stranger with that key do?** The answer has to be "exactly
what `supabase/access.toml` says, and nothing that costs us money or corrupts the
data players see."

Two layers, the same split as `swift-check.py` / `/swift-review`:
- `scripts/supabase-check.py` — the mechanical checks, run on every schema change
  (migrations lint, secret scan, advisors, live catalog against `access.toml`, a probe
  with the publishable key, auth settings). It must be green before you start here.
- This skill — the judgment: logic in the Edge Functions, the meaning of each policy,
  and the abuse cases the access table can't express.

## 1. Run the script

```bash
scripts/supabase-check.py          # needs `npx --yes supabase@2 login` (Abraham runs it)
```

Build Release first if the app changed, so the secret scan covers the shipped bundle:
`xcodebuild -scheme movie-quiz -configuration Release -destination 'generic/platform=iOS Simulator' build`.

Report every FAIL and warn. A FAIL is a finding on its own; don't re-derive it below.
If `access.toml` itself looks wrong (a table readable that shouldn't be), say so: the
script only proves the service matches the file.

## 2. Each Edge Function (`supabase/functions/*/index.ts`)

Every function runs with the **service role**, so it bypasses RLS and every grant. Its
checks are the only checks. For each one, write down what a stranger can make it do
with the publishable key and a script, then go through:

- **Gate.** Does it check `apikey` before doing any work? (The `APP_KEY` check is a
  light gate, not authentication: the key is public.)
- **Input bounds.** Body size, array lengths, string lengths, number ranges, and that
  every field written to the database is one it validated (no `insert(body)`).
- **Identity the client chooses.** Anything keyed by a client-supplied id
  (`device_id`) can be forged at will: unlimited fresh ids defeat per-device limits and
  dedup. Ask what that does to anything computed from the table (daily averages,
  answer data) and whether it matters yet.
- **Amplification.** Can one cheap request cause expensive work: an upstream call, a
  row written, a cache entry created? Look for keys built from client input (query
  strings, paths) that can be varied endlessly. That fills the free plan's 500MB and
  spends the upstream quota.
- **Upstream exposure.** For the proxy: only allowlisted paths *and parameters* go to
  TMDB; the token never reaches the response or the logs; errors don't echo upstream
  bodies with anything sensitive.
- **Errors and logs.** No stack traces or SQL errors to the client; logs carry no keys
  or personal data.
- **Rate limiting.** There is none at the platform level for Edge Functions. Note
  where a burst would hurt, and whether `docs/MONITORING.md` has a signal for it.

## 3. Each policy and grant, by meaning

The script checks that grants match `access.toml` and catches `using (true)` on writes.
It can't tell whether a read policy shows the right rows. For every policy:
- Who does it apply to, and which rows does its condition let through? Write the
  condition out in words.
- Is any row readable before it should be? (`puzzles` is, on purpose; see *Accepted*.)
- With accounts: does every owner check use `auth.uid()` against a column the player
  can't change, and does UPDATE's `with check` stop moving a row to someone else?

## 4. Before accounts ship (0.9.0)

Flip `[auth] accounts = true` in `access.toml` only when these hold:
- Signups: email confirmation on; minimum password 8+ (or passwordless only, which is
  the plan: Apple, Google, email one-time code); leaked-password protection on if the
  plan allows it.
- Redirect URLs: exact, no wildcards; `site_url` is the real app/site, not localhost.
- Anonymous sign-ins: on since 2026-10-31 (every install is one), declared in
  `access.toml`. Linking a provider must keep the anonymous user's id.
- Every table a player owns: an owner column set by default from `auth.uid()`, insert
  and update policies checking it, column-scoped `update(...)` grants in `access.toml`
  (never a table-wide `update`, or a player can rewrite their own score or owner).
- Anything privileged (friend-group membership, results) still goes through an Edge
  Function, not a direct table write.
- Linking keeps the anonymous user's id (no data moves). The one merge is a second
  phone's anonymous player signing in to an existing account: its local data goes up
  under the account without letting it claim anyone else's.

## 5. Report

Lead with what a stranger can do today, worst first. For each finding: the request
that does it (method, path, body), what happens, and the smallest fix. Separate:
- **Fix now:** a leak, a write path, or unbounded cost.
- **Before the beta / before 0.9.0:** real but not yet reachable or not yet costly.
- **Accepted:** deliberate trade-offs. Don't re-raise the ones below unless what they
  rest on has changed; add new ones here with the date and the reason.

Anything that should become a mechanical check goes into `supabase-check.py`; a new
way for the service to fail goes into `docs/MONITORING.md`.

## Accepted

- **Future dailies are readable** (2026-10-27). `puzzles` is `using (true)`, so a day
  inserted ahead is public at once. The design needs that: phones fetch a week ahead
  (ROADMAP *Client-side rules*; MONITORING keeps seven days published), and whatever the
  app can read, its extracted key can read. Spoilers across time zones are already
  accepted (DAILY-CHAIN.md), and the start is a prompt, not an answer. Re-raise only if
  days are published far more than a week ahead, then cap the policy at ~8 days.
- **Results can be forged** (2026-10-27; narrowed 2026-10-31). `results` takes the
  player from the caller's token now, so each forged player needs an anonymous session
  (30 an hour per IP), but anyone can still post well-formed runs as themselves. There's no prize or rank to win (ROADMAP: anti-cheat is motive, not
  detection), and nothing reads `results` yet. Re-raise when the stats panel or answer
  data ships: its decision (ROADMAP *For Abraham, 2026-10-27*) carries the mitigations.
- **Points can't be verified** (2026-10-27). Speed is measured on the phone; the
  function only checks points fall in the possible range for the link count.
