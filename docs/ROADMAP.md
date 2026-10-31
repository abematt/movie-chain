# Roadmap to 1.0 (launch)

> **1.0.0 means launch.** The solo game loop is complete and tested at
> [`0.4.0`](../CHANGELOG.md), and the visual design overhaul landed as `0.5.0`
> (2026-10-22) — ahead of Foundations, so the two swapped version numbers. The rebrand
> to **Unspool** was inserted as `0.6.0` on 2026-10-22, pushing every later milestone
> down one minor version. This plan was re-cut on **2026-08-08** after a planning
> conversation that changed the launch scope, dropped global leaderboards, and added a
> new headline mode. Seven milestones stand between here and a public release.
>
> This doc is the *planning* layer: scope, rationale, what each milestone touches, and
> the decisions/traps to settle before writing code. Deep technical designs live in
> [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`DAILY-CHAIN.md`](DAILY-CHAIN.md) and are
> linked rather than duplicated. The order is a plan, not a contract — if milestones land
> out of order, the version follows the work.

| Version | Milestone | Depends on |
|---|---|---|
| 0.5.0 | [Design overhaul](#050--design-overhaul) — **landed 2026-10-22** (motion re-tuned in 0.5.1) | — |
| 0.6.0 | [Unspool — the rebrand](#060--unspool) — **landed 2026-10-23** | 0.5.0 |
| 0.7.0 | [Ground & Object](#ground--object--the-10-look) and the first of [Foundations](#070--foundations--safety-net) — **landed 2026-10-26** (logging, crash reporting, the build pipeline still to come) | — |
| 0.8.0 | [The service — TMDB proxy first](#080--the-service) | — |
| 0.9.0 | [Accounts](#090--accounts) | 0.7.0 (device id), 0.8.0 (a backend) |
| 0.10.0 | [The Daily Chain](#0100--the-daily-chain) | 0.8.0 (generation job) |
| 0.11.0 | [Friend groups](#0110--friend-groups) | 0.9.0 |
| 1.0.0 | [Launch](#100--launch) | all of the above |

## Re-cut 2026-10-26: the service before launch

**This supersedes "No login at launch… no backend" below; launch is no longer bound to
early November.** The backend (Supabase) comes before launch, because what it unlocks
is what makes the game different, not just bigger: per-day stats for everyone ("you
beat 74% today") as comparison without leaderboards, answer data that can score
obscurity by what players actually remember, content changed without an app release,
and the head-to-head's automatic return. In order:

1. **The daily start, built in** — landed; its list stays as the offline fallback.
2. **The TMDB proxy** ([0.8.0 Job 1](#job-1--the-tmdb-proxy)) — *landed 2026-10-26*
   (`supabase/functions/tmdb`, cache table `tmdb_cache`). Release builds leave the TMDB
   token out (`TMDBSecrets.plist` is development-only); the security advisor is clean
   once `rls_auto_enable` is locked down. **Run `scripts/supabase-check.py` (the advisors
   plus the checks against `supabase/access.toml`) before and after every `db push`.**
3. **The daily start served from a table** — *built 2026-10-27* (`puzzles`, mode
   `daily_start`; `DailyStartFeed.swift`). Publish a day with an insert in the SQL
   editor ([`ARCHITECTURE.md`](ARCHITECTURE.md#daily-start--dailystartswift)); the list
   is the fallback. Days 1–9 are seeded from the placeholder list.
4. **A results table** — per-day stats and the answer data. *Collecting since
   2026-10-27* (`results`, written only by the `results` function; `RunResults.swift`).
   Every run, links as TMDB ids with per-link seconds, no typed text; shape checks only,
   no re-check against TMDB. **Still to decide: what the player sees.** Wordle's model is
   a fixed panel (your stats, and how everyone did today), not a percentile.
5. **Head-to-head with the automatic return**, on the service from the start.
6. **Free daily credits + the hint ladder**, as before.

**Room for new modes** (six degrees, A→B longest route, and whatever comes next): a
mode's rules and screens ship as app updates; the service only serves its content and
stores its results. So puzzles and results are keyed by a `mode` with the mode's data in
a JSON column, not a table per mode, and modes can be switched on remotely. No more than
that until a second mode is real.

Owed before the beta because of this: the privacy policy's app section and the App Store
privacy label (results and typed answers leave the phone), and the version plan re-cut.

## Re-cut 2026-10-24: launch early

**This supersedes the first two decisions below and the milestone table above.** The
solo game ships to the App Store as soon as it's ready (aiming for early November
2026) rather than after the full loop. The point moved from "own the whole cycle before
launch" to learning from real players sooner: the backend gets designed around how
people actually play rather than guesses.

- **No login at launch.** No accounts, no backend. The device id
  ([0.7.0](#070--foundations--safety-net)) is the hook a later account claims.
- **Free at launch, no purchases.** TMDB's terms on commercial use get settled (by email)
  before anything is charged for — see [Monetization-ready](#monetization-ready--built-in-switched-off)
  for what that costs and the fallback. Purchases such as credits or streak saves, when
  they come, are StoreKit consumables, which need no login.
- **Competition without accounts, at launch.** Chain sharing (a versioned payload and
  URL format for a chain, GROWTH.md D1), challenge links (D4, built out as the
  [head-to-head](#head-to-head--same-start-both-sides-see-the-score)), and a daily start for
  everyone (D5) from a **fixed list** of starts, not derived from each phone's cached
  pool, which can differ between friends. The A→B Daily Chain
  ([`DAILY-CHAIN.md`](DAILY-CHAIN.md)) stays after launch.
- **Before launch from 0.7.0:** the "Dealing…" hang fix and the deal-pool disk cache
  (both landed), plus a TestFlight build to friends. Logging, Sentry and the build
  pipeline can follow launch; crashes go to Xcode's Organizer for now.
- **After launch, in order of what players show is needed:** the Daily Chain, accounts
  (Supabase, anonymous first, then Google and Apple linked to the same user), friend
  groups, a backend of our own. Version numbers get re-cut when launch scope is final.

## Next up — the game mechanics, in order

*Set 2026-10-26.* The next mechanic work, before launch, in this order. Each item names
where its detail lives; update this list as they land (move a landed one to the changelog).

1. **A daily start for everyone** — *built 2026-10-26 (`DailyStart.swift`), served from
   the service since 2026-10-27; the starts are still placeholders.* One shared starting name per day,
   drawn from a **fixed hand-picked list** (not each phone's cached pool, which can differ
   between friends), so everyone plays the same start on the same day and the share card
   compares. GROWTH.md D5. Small; no backend, no developer account. Not the A→B Daily
   Chain — that's [0.10.0](#0100--the-daily-chain), after launch.
2. **Challenge links + the head-to-head (step one).** *Built 2026-10-27, Debug builds
   only:* the challenge link, B's head-to-head at game over, the reply link back to A, and
   the Rivals list — see [Head-to-head](#head-to-head--same-start-both-sides-see-the-score).
   Left: universal links (playunspool.com + the Apple Developer account) to switch it on
   in Release, the site's fallback page ([`WEBSITE-SYNC.md`](WEBSITE-SYNC.md)), and a
   design pass on its screens alongside the daily's.
3. **Free daily credits + the hint ladder.** A credit balance with a free daily grant,
   spent on the escalating hint ([`ASSISTED-MODE.md`](ASSISTED-MODE.md#if-assistance-returns-preserve-the-recall-act)),
   built with the `Entitlements` check, assisted-run marking and analytics events from
   [Monetization-ready](#monetization-ready--built-in-switched-off). Free in the beta —
   it answers "does a stuck player want a hint?" before anything is ever sold.

**To come back to** (noted 2026-10-26, after playing the daily on a phone):
- **The daily's look** — the Today pill and the "Daily #N" tag work, but the design isn't
  settled; iterate on them.
- **The share image names no one.** The coins are blank by design (`ShareCard.swift`:
  spoiler-free, the start is the dare), but on a phone it reads as missing. Decide what
  it should reveal — at least the start, maybe the chain once played.

**For Abraham, 2026-10-27** (left over from building the two tables):
- [x] ~~Delete the two probe rows~~: already gone (checked 2026-10-27; ids 4 and 5 are
  real runs and stay).
- [ ] **Publish the real starts before day 10 (4 November).** Days 1–9 are the placeholder
  list; with no row for day 10 the app wraps back to the start of its list. Insert days 10
  onward (the statement is under *Daily start* in [`ARCHITECTURE.md`](ARCHITECTURE.md#daily-start--dailystartswift)),
  and replace 3–9 with new revisions if the placeholders shouldn't run.

**Tweak run**: small polish, parked so the mechanics come first (set 2026-10-27). Do
these together in one pass:
- **The daily's game over gets a flourish, not a stats panel.** Same treatment as New
  best: the points line adds how everyone did today ("14 links · 620 pts · today 8") and
  a tag in New best's spot when you beat it (wording open: "Above today" / "Beat the
  room"; New best wins if both). Hidden until a day has 5+ results. Needs a
  `daily_stats(number)` function returning only the count and the figure, so `results`
  stays unreadable to the app's key. Undecided: that figure, or "you beat N%".
  **Anyone can post forged runs**, one anonymous session per fake player since
  2026-10-31 (sign-ins are rate limited per IP; accepted for now;
  `/supabase-audit` → *Accepted*), so the figure has to hold up to that, in order of cost:
  1. **The median, not the mean**, without `-debug` runs: a flood has to outnumber real
     players to move it. Nearly free.
  2. **Re-check each link against `tmdb_cache`** in the `results` function before storing
     (the response `MONITORING.md` already names): forged runs then need real chains.
  3. **App Attest** (DeviceCheck), proving a request came from the app on a real device:
     the real fix for invented ids. Free, but a medium build; only if forging shows up.
- **Results go behind the analytics opt-out** (decided 2026-10-27). The toggle promises to
  stop "your turns, what you type", and a result is exactly that. Check
  `Telemetry.enabledKey` before `RunResults` sends; note it in [`ANALYTICS.md`](ANALYTICS.md)
  and the privacy draft (unspool-site PR #1). Opted-out players still see today's figure.
  The head-to-head's automatic return is a send the player chooses, so the toggle doesn't
  cover it.
- **Mode identity** (Abraham, 2026-10-28: "the daily should not just be a pill", "the
  daily's end should not just be a normal screen with random text, same for the
  head-to-head"). The daily and a challenge each get:
  - **their own home state** — the daily is a dealt *thing* with a presence (the day,
    the fact that everyone plays it, how many have), not a Today pill in the header; a
    received challenge is the challenger's dare, front and centre, not a caption line;
  - **their own game over** — the daily's ends against the room (the flourish, below);
    the head-to-head's ends as a bout: the two runs faced off, the verdict, and Send it
    back as the only act. Night stays the ground; what's on it differs per mode. Neither
    is the ordinary game over plus a tag.
  Settle this on the design canvas first (the screen-flow canvas is the base), then build.
  This absorbs **the daily's look** and **the share image naming no one** (above), and
  the header-overflow bug (the four pills), since the Today pill goes.
- **The head-to-head's UX** (first pass landed 2026-10-27; `/swift-review` findings
  included):
  - **One owner for sheets.** A link opened while the Reel, Settings or Rivals sheet is
    up shows nothing (the match is still recorded): the root's sheet and alert can't
    present over a child's. Lift the screens' sheets into one root `enum`
    (reel / settings / rivals / match), so a link replaces whatever is up.
  - **Keep sent challenges on the phone**, keyed by `challengeKey`, and take your side of
    a reply from there, ignoring replies to nothing you sent. Today "you" comes from the
    reply's `r`, so a forged reply can set your score.
  - **One win rule**: build `Outcome` from `Scoring.isNewRecord` rather than restating it.
  - **Tests**: a challenge arriving during the home's first pool load; `PlayerName.current`.
  - **Resume with a challenge on the home** still refreshes the dailies
    (`dealFreshOnResume` returns before it).
  - **"vs you"** in a reply's share text when the challenger had no name → "vs them".
  - **Persist a challenge that arrives mid-run** (lost if the app is killed first).
  - The screens themselves: see *Mode identity* above. The reply sheet and the Rivals
    list and the name prompt need the design pass too (the prompt stays: it writes the profile).

**Meanwhile, no code:** playtest the A→B Daily Chain with two people and index cards
([`DAILY-CHAIN.md`](DAILY-CHAIN.md)) — it's the gate on 0.10.0.

## Monetization-ready — built in, switched off

*Decided 2026-10-26.* Nothing is sold at launch, and most apps never reach the scale where
selling matters. But if Unspool does, turning money on should mean **filling slots that
already exist**, not reworking the game. So build the seams now; leave StoreKit products,
paywall screens, App Store Connect setup and pricing until the numbers say so.

**The seams, built as the features they belong to land:**
1. **One access check.** An `Entitlements` type the game asks ("can this player use a
   hint?", "is the archive unlocked?"). Today it always says yes; later it reads StoreKit.
   No paid checks scattered through views.
2. **Credits, given away daily.** A balance, a free daily grant, spends on hints and
   pauses. In the beta everyone has plenty — it answers whether a stuck player wants help
   at all (the open hint question below) for free, and a purchase later just adds to the
   same balance.
3. **Assisted runs are marked.** The run summary records whether a hint or continue was
   used; those runs stay out of the best run and friend comparisons, paid or not (the
   Hardcore flag is the precedent).
4. **Every Daily Chain is replayable.** A date-derived id, deterministic, stored — so an
   archive of past dailies is a sellable thing later with no rework. Expensive to
   retrofit; build it into [0.10.0](#0100--the-daily-chain) from the start.
5. **Credit and hint events in analytics,** in [`ANALYTICS.md`](ANALYTICS.md) — they're the
   numbers that say when monetizing is worth it.

Already in place: the `MovieDataProvider` seam (the data source can change), and StoreKit
2 restores purchases and subscriptions without a login, so accounts don't block selling.

**What would be sold, ranked:** a Daily Chain premium or subscription (archive, Practice,
stats — the model daily puzzle games use) → credits for hints and pauses ($0.99 / $2.99 /
$4.99 packs) → app icons and themes. Nothing sold *on* an actor's card until a lawyer has
looked at selling around real people's faces. No ads, no upfront price (the site promises
free), no tip jar.

**TMDB's side (checked 2026-10-26).** Any revenue — purchases, ads, tips — is commercial
use under the [API terms](https://www.themoviedb.org/api-terms-of-use) §2.A, and TMDB
staff have said publicly it costs **$149/month under $1M revenue**, no indie tier. At
~$2.40 kept per $2.99 sale that's ~62 sales a month, roughly 1,600–9,500 monthly players
depending on conversion. Subscribe the day purchases go live, not before. **The fallback
is Wikidata (CC0):** a coverage test against the top 500 films found 99.5% of top-3 billed
and 92% of billed 4–10 actors, and 97% of pool actors' well-known films (voice roles live
in P725, not P161), but only 40% of obscure films and no posters — film cards would go
typographic. Also owed regardless of money: the attribution notice should use §3's exact
wording, and §1.C's six-month cache limit covers the Reel's stored names and image paths.

## Head-to-head — same start, both sides see the score

*Added 2026-10-26.* The challenge loop, built so it works **without a backend** and gets
better as the service and accounts land — not blocked on them.

1. **A sends a challenge** — a `SharedChain` link (start, links, points, sharer id, name).
2. **B plays the same start** and, at game over, sees the head-to-head on their phone:
   most links wins, points break a tie (`Scoring.isNewRecord`'s rule).
3. **B sends it back** — a reply link carrying both runs; A opens it and sees the same
   head-to-head. Manual, like Pass & Play, and needs no server.
4. **A rivalry list** on each phone, keyed by the other player's sharer id: "You vs Sam,
   3–2", with each match.

**Identity is a display name, not a username** — asked the first time someone challenges
("what should friends call you?"), not unique, not searchable; people find each other by
link. The sharer id already tells two Sams apart.

**Decided 2026-10-27** (talked through before building):
- **Every share is a challenge.** There's no separate Challenge button. The name prompt
  comes on your first share.
- **B sees A's links *and* points before playing**, not the route. Points are part of
  the score to chase. Most links wins; points break a tie.
- **One try per challenge.** Opening the same link again shows the result, not a replay.
- **Dailies aren't challengeable.** A daily's share stays the plain brag (no challenge
  link), so the daily and challenges stay separate modes.
- **Strictly one-to-one.** A posts once to a group chat; A gets B, C and D as separate
  matches; B, C and D each see only A. Nothing to build for groups; the screens just
  have to take several replies arriving at once.
- **No rematch feature.** A new challenge on a new start is the rematch.
- **Challenge runs count** toward your best and your Reel, like any Hardcore run.
- **The rivalry list is a "Rivals" pill on the home header**, next to the Reel and the
  gear, shown once you've had a match. Not in the Reel, which stays the collection.
- **Names update by link.** B's phone keeps the latest name it saw from A's sharer id,
  so a rename shows when A's next link arrives. A live, synced name is what accounts
  ([0.9.0](#090--accounts)) add; not worth pulling accounts forward for.

**Built 2026-10-27** (`Rivals.swift`, `HeadToHead.swift`; see
[`ARCHITECTURE.md`](ARCHITECTURE.md#head-to-head--rivalsswift--headtoheadswift)). The
mechanic works end to end between two simulators. **To switch it on in Release:** set
`Config.shareBaseURL` to `https://playunspool.com`, add the associated-domains
entitlement (`applinks:playunspool.com`), and have the site serve
`apple-app-site-association` for `/c` plus a fallback page. **Then a design pass**:
the challenge line on the home, the result on game over, the reply sheet, the Rivals
list and the name prompt are first-pass, built for the mechanic.

**Rethink 2026-10-28** (Abraham, after seeing all sixteen screens on the flow canvas:
"I don't like a lot of it"):
- **No gate on challenging** (settled the same evening, after a first pass that gated
  sending): sharing is what brings people in, so neither sending nor receiving a
  challenge needs an account. The pattern stands: every share is a challenge, the name
  asked on the first share.
- **Identity: one id from day one, and the name lives on a profile.** The thing to nail
  down before the service holds more data. Today nothing about a challenge touches the
  service: the link carries everything, the sharer id is a random UUID on the phone, and
  `results` is keyed by `device_id`. The shape that makes accounts a non-event:
  1. **Supabase anonymous sign-in at first launch**, silently. Every player holds an
     `auth.users` id from the start; it replaces the local sharer id and
     `results.device_id`. Signing in at 0.9.0 *links* Apple, Google or email to that
     same id, so A's id on B's phone is still A's id afterwards — nothing to track back.
  2. **A `profiles` table** keyed by that id: `display_name`, and later anything an
     account carries. "What should friends call you?" writes it, for anonymous players
     too, so the prompt isn't scaffolding: it's the profile, and sign-in adds a credential,
     not a name. Once the app reads names from `profiles`, a rename shows everywhere;
     until then names update by link, as now.
  3. **Second phone: sign in, pull the account down, discard that phone's anonymous id.**
     The standard pattern; nothing more. A rival row someone holds for the discarded id
     goes stale, which is cosmetic and rare (the app asks "already have an account?" on
     a fresh device before it matters). If it ever shows up as a complaint, a
     `merged_into` forwarding column on `profiles` fixes it later.
  Everything else (results, matches, groups) stores the user id and nothing else: never
  an email, never a device fingerprint. Decide this while `results` is small, since
  `device_id` can simply become the auth id.
- **The screens need to be *theirs*, not the normal screen with different text.** The
  daily and a challenge are the two things the game is sold on, and right now each is a
  pill and a line of copy. The design pass (below) treats them as distinct modes with
  their own home state and their own game over — see the Tweak run's *Mode identity*.

**Upgrades as the platform grows:** the service ([0.8.0](#080--the-service)) returns B's
result automatically with a push ("Sam beat your chain"); accounts
([0.9.0](#090--accounts)) carry the list across phones; friend groups
([0.11.0](#0110--friend-groups)) are this, for more than two.

**Needs:** universal links on playunspool.com (the association file on the site, and the
Apple Developer account) with a web page for anyone without the app — otherwise every
challenge dead-ends for exactly the people it should recruit.

## The decisions this plan rests on

Settled 2026-08-08, so they don't get re-litigated mid-build:

- **Launch scope is the full loop.** Endless game + the Daily Chain + friend groups, all
  before the App Store. The goal is to own the complete cycle — publish, tracking, auth,
  backend, devops — not to get to market fastest.
- **No public release before launch — but a TestFlight beta, yes** *(revised
  2026-10-23)*. Nothing goes on the App Store before 1.0, but the waitlist becomes a
  TestFlight beta well before it, because the launch decision is made from beta
  retention (see the [launch track](#the-launch-track--runs-alongside-the-milestones)).
- **Global leaderboards are dropped permanently.** An AI can produce a valid long chain on
  request, and our designed anti-cheat (server-side re-validation) only catches
  *fabricated* chains, not *assisted* ones. A number from a stranger can't be trusted, so
  we don't build anything whose value depends on a stranger believing one. Competition is
  friend-scale only. Precedent: NYT added a leaderboard to Wordle in April 2025 — **friends
  only, joined by invite link, no global ranking** — despite having every resource to
  build a global board.
- **Roughly 5–10 hours a week**, which puts this plan at 6–9 months.

**The principle that spans all of it** (carried over from the sociality design in
`ARCHITECTURE.md`): the game stays **fully playable and fun solo, with no account**.
Every social layer is additive on top of the login-free core, never a gate in front of
it. *(Note the one qualification this re-cut introduces: the Daily Chain needs
connectivity to fetch a puzzle. Cache it locally so a round survives losing signal, and
keep the endless mode as the always-available path.)*

---

## The launch track — runs alongside the milestones

Added 2026-10-23, from a solo builder's launch playbook (Chris Raroque's "how to start an
app" and "launch framework" videos). The milestones below are the product; this is
how it reaches people. None of it is versioned and most of it isn't code — it runs in
parallel, and the early items matter *because* they take months to pay off.

**Now:**
- **Waitlist page — live (2026-10-26).** https://playunspool.com, built by hand in its own
  repo ([`abematt/unspool-site`](https://github.com/abematt/unspool-site)) on Cloudflare
  Workers, not Framer. Signups go to the D1 database `unspool-waitlist` (table `signups`);
  no FormSpark or Loops. It measures interest, becomes the TestFlight beta pool, and is the
  first announcement list at launch. What the app owes the site (privacy section, Settings
  links, stable screenshot flags, true claims) is in the site's [`docs/handover-app.md`](https://github.com/abematt/unspool-site/blob/main/docs/handover-app.md).
- **Reddit and forums.** Participate genuinely in r/movies, r/Letterboxd, r/trivia,
  r/iosgaming *before* mentioning the app — this channel takes months, and a link drop
  on launch day gets destroyed.
- **Build in public.** The dev diary already captures every session; cut it into short
  posts. A screen recording of a real run is a complete video (timer, deck, shake,
  near-miss) — see [`GROWTH.md`](GROWTH.md#5-two-plays-that-need-no-build).

**Before the beta:**
- **A feedback board** — **UserJot**, live at https://unspool.userjot.com/ (free plan),
  to be linked from Settings. Requests and upvotes, so what players ask for is visible rather than guessed.
  The 1.0 "Send feedback" email stays for bug reports.
- **The TestFlight beta**, invited from the waitlist: export `signups` from the D1 console
  as CSV and invite those addresses in TestFlight. Runs
  through the rest of the milestones on PostHog.
- **The privacy page covers the app before the first invite goes out.** Testers' play data
  reaches PostHog from their first run, so https://playunspool.com/privacy has to describe
  the app by then (not at App Store launch). The app section is drafted and waiting,
  unmerged, in [unspool-site PR #1](https://github.com/abematt/unspool-site/pull/1) (written from the code at 0.7.0, naming Abraham Mathew as
  controller). Before inviting anyone: re-check it against the app's code, update what's
  changed, then merge it (merging deploys the site). Settle these in the same pass:
  - **Analytics is on by default** with an opt-out. EU rules on storing an identifier on
    a device may expect consent before analytics rather than an opt-out; check whether
    the beta needs a one-time prompt.
  - **No retention period.** Pick one in PostHog and state it on the page.
  - **Deletion can't be traced.** Play data isn't linked to a person, so a deletion
    request can't find it. Show the random ID in Settings, or add a "delete my play data"
    action, and say how on the page. This now covers the service's `results` table too
    (every run, under the device id, kept until deleted), not only PostHog.
  - **Results aren't behind the analytics opt-out.** They're game data (stats), sent
    whatever the analytics setting. Say so on the page, or put them behind it too.
- **An App Review note about TMDB.** External TestFlight builds go through beta review,
  and TMDB apps get rejected under 4.1 / 5.2.1 / 5.2.2 (third-party IP) when the reviewer
  can't see the rights. In App Review Information: the data comes from TMDB's API under
  their terms, attribution is in the Reel and Settings, nothing is sold — and attach
  TMDB's written confirmation if their reply has arrived. Never "TMDB" in the name,
  subtitle or keywords.

**Before 1.0:**
- **App Store screenshots — budget 3–4 days.** They're the first thing a browser judges,
  and Apple gives a new app roughly two weeks of search boost that doesn't come back.
  Plus a careful title, subtitle, description and keywords. **Let names and the game
  carry the shots, not faces:** reviewers have rejected TMDB apps over celebrity photos
  and posters in store screenshots (passing v1, failing an update). Lead with the answer
  dock, the start sentence, the game-over stack; keep the Reel's cards small.
- **Landing page — budget about a week**, reusing the screenshot assets. It shows the app
  and drives downloads. Tweakable after launch, so it doesn't hold launch. *(2026-10-25:
  hand-built rather than in Framer, in its own repo,
  [`abematt/unspool-site`](https://github.com/abematt/unspool-site); until launch its
  form doubles as the waitlist.)*

**The launch decision** comes from the beta: if players drop off after a day, wait; if
they stick around for several days, launch. Judge it on week-1 retention in PostHog.

**Launch week:** start posting a week ahead; on the day, email the waitlist (Loops or Kit, sending from `mail.playunspool.com`, with a PO box as the
postal address),
launch on **Product Hunt**, post to the communities above and the build-in-public
channels, and ask friends to share. Time it so the boost window gets the best listing
we have.

**Community email, later.** Once accounts (0.9.0) give us addresses from players who
opted in, Loops runs sequences too — a welcome, a few "did you know" notes over the
first two weeks, a feedback ask after a week away. Marketing email is **opt-in**,
separate from signing in.

---

## 0.5.0 — Design overhaul

> **Landed in 0.5.0 (2026-10-22), visuals only.** The direction chosen is **Cream
> Neobrutalist** — cream canvas, white cards with a 2pt ink border and a hard offset
> shadow, a coral call-to-action, Fraunces for display type and numerals, blue = actor,
> yellow = movie. The chain is drawn as **cards** (a hero card for the newest link,
> compact cards for earlier ones). **Motion re-tune (landed in 0.5.1):**
> the prototyping below settled on a **Deck** — a physical pile — as the default, and
> rather than deleting the losers, all three treatments (Deck, Cards, Tiles) stay as a
> player setting. Details of what changed are in the
> [changelog](../CHANGELOG.md). The planning notes below are kept as written.

**The current look is placeholder.** It's a competent NYT-Games/Connections pastiche, but
it isn't an identity of its own — and that includes the chain rendering, the app's most
visible element.

**What must survive:** the *structure*, not the styling. The design-system layer exists
precisely so a re-skin is a change to `Theme.swift` + `Components.swift` rather than a
rewrite of every screen:

- `Theme` — color / spacing / radius / motion tokens. Views reference tokens, never
  literals, so retuning is central.
- `Components.swift` — owned primitives (`NodeTile`, `NodeDot`, button styles, juice
  pieces). Screens compose these.
- **Per-node category identity** — the actor/movie distinction (currently blue/purple) is
  a real information channel, not decoration. Whatever replaces it must still encode
  "which kind is this" at a glance.

**In scope:** palette, typography, the chain treatment, tile treatment, and a motion
re-tune to match.

### The open decision at its centre — and how it gets resolved

**How the chain is drawn is still open**, and it's the highest-leverage decision in the
overhaul. Candidates: a **stacked list of cards** (leading), a **filmstrip**, a **literal
linked thread**, a **constellation**.

**Decided 2026-08-08: prototype two or three of them in code and judge them running on a
device.** Motion and density are hard to evaluate on paper, and this is the app's
signature visual — worth the extra work to be right. Build them rough; don't polish
before choosing.

**The constraint that decides it:** vertical room. The chain band is squeezed between the
score hero and the **docked keyboard** (iPhone is portrait-only by design). Cards need far
more room per node than a 44pt bar. Any prototype that ignores the keyboard is not a
prototype of this screen.

**What the current `ChainStack` gets right and probably survives:** it stacks, collapses
older entries into "+N earlier", and emphasises the newest. That information architecture
likely carries into whichever treatment wins — so for cards this is a *tile → card
upgrade*, not a structural rethink.

**Why cards lead:** the app already fetches poster and headshot art for every node
(`imagePath` → `Config.imageURL`), and a card is the natural container for art where a
coloured bar is not. Today that art only surfaces in the Reel — cards put the *film
itself* on screen during play, which is far more on-genre, and they compose better with
the share image at 1.0.

**Also decide:** does the app keep the "puzzle page" register, or move toward something
cinematic? The former is calmer and differentiated; the latter is more on-genre and pairs
with a card/poster direction.

**Traps (all previously paid for — don't rediscover):**
- Every color needs **light + dark** variants in `Assets.xcassets`. `OnAccent` exists
  because text on the pastel tiles must stay legible in *both* themes.
- **Reduce Motion** is honored throughout today (screen pushes degrade to cross-fades,
  staggers and drops become instant). Keep that property.
- The **app icon** is derived from the chain mark — it changes with the redesign, and the
  render must be **opaque, no alpha channel** (iOS rejects icons with alpha).
- iPhone is **portrait-only** because the play screen docks the keyboard. A redesign that
  wants landscape has to solve the keyboard-docking layout first.
- **The app name** is a separate, larger question that shouldn't be drifted into — and
  it's now an ASO decision too. "Chain" stays accurate as *domain* vocabulary regardless
  (`ChainNode`, `bestChain`); only `ChainStack.swift` is presentation-named.

---

## 0.6.0 — Unspool

> **Landed in 0.6.0 (2026-10-23).** Settles the name question the 0.5.0 traps list
> deferred. The film strip's uses (store screenshots, the share card) and the trademark
> check on the name belong to 1.0.

**Why now:** the name and icon were the last placeholder in the identity 0.5.0 built,
and everything after this point (TestFlight, the store listing, share images, the Daily
Chain's share card) carries the name. Renaming after those exist is far more expensive
than renaming before.

**Scope:**

- **The name: Unspool.** Film coming off a reel, and a chain playing out link by link.
  User-facing only — the bundle id stays `abe.movie-quiz`, and the domain vocabulary
  stays "chain" (`ChainNode`, `bestChain`; a *chain* is still a run).
- **The mark:** two overlapping circles, blue (actor) and yellow (movie), with the ink
  overlap as the link between them. It replaces the "oo" in the wordmark. **The icon is
  the mark on a cream tile** — a coral tile with a yellow circle read as Mastercard at
  small sizes. Light, dark and tinted variants; opaque, no alpha. A film-reel-holes
  alternate was drawn and rejected (the holes read as buttons at 29–60px).
- **The home screen is the first turn:** a sentence with a blank — "Chris Hemsworth
  *was in* a movie…", "Inception *starred* an actor…". Tapping the blank hands off to
  play in place (the name, chip and avatar fly into the deck's start card, the blank
  into the answer dock as the keyboard rises); the clock starts when it lands. "Deal
  again" deals a new start; "Pick your own" opens search. The best run is a footer
  line. *(A dealt-card home — headshot card on a pile, PLAY + Shuffle — was built first
  and replaced the same day: the sentence teaches the rule without a button.)* The
  play screen itself is unchanged; it does not become a sentence.
- **The film strip** (blue/yellow frames running into "?" frames) is the supporting
  graphic for the launch screen, store screenshots and share card — never the logo.

**Traps:**
- The handoff is a **flight, not `matchedGeometryEffect`** (`Handoff.swift`): both
  screens report frames into a `HandoffStage`, the root draws copies between them on its
  own `TimelineView` clock, reading the destination live every frame. An animated
  `Animatable` value didn't animate there; a time-based clock did.
- **The first focus of the answer field blocks the main thread** (~150ms, loading the
  keyboard). The flight holds still until it has passed — otherwise its opening frames
  are lost and it jumps. Keep anything else expensive off that moment.
- Long titles: the name shrinks to fit three lines inside a fixed-height region, so the
  blank never moves when a shuffle deals a longer name.
- Check that "Unspool" is clear on the App Store and as a trademark before 1.0's listing.

---

## Ground & Object — the 1.0 look

Landed on `main` 2026-10-24 ([PR #20](https://github.com/abematt/movie-chain/pull/20)); shipped in 0.7.0 (2026-10-26). Cream Neobrutalist read
as "vibe coded" and too close to Claude's ivory, serif and clay. The new direction is
**Ground & Object**, drawn from Bakers Studio's Pera identity and Tinyman visuals: a
paper ground, heavy objects with an ink edge and a hard ink side, blue and yellow living
only on objects and in the answer dock, Archivo in three widths plus mono caps, foil saved
for a new best. It is specced screen by screen on a design canvas (private, on the
personal account), which is the source of truth while it lasts.

**Decided:** dark mode is a dim room (the ground lifts, black stays the side);
Home and Play put the colour in the dock; game over and the share card sit on Night
with the chain as one coin stack, a film spool on the top disc; a new best is game over
on the holo sky; Reel cards stay. **Tabled:** the Reel's disc grid.

**Order:** foundations (tokens, fonts) → components (slabs and sides) → Home → Play →
game over → share card and challenge → the Reel → Settings, search, first run.

---

## 0.7.0 — Foundations & safety net

**Why first:** none of it depends on a design decision, none of it can be wasted, and
until it exists we're blind. The app currently has **zero logging statements and 18
places where an error is caught and discarded** — including the path where a
rate-limited launch leaves the home screen stuck on "Dealing…" forever. A tester saying
"it froze" is currently unactionable.

**Scope:**

- **Back the code up.** A private remote. There isn't one — the project exists on one
  laptop. Also the prerequisite for automated builds.
- **Logging.** `OSLog` with categories (engine / network / storage). Free, no SDK,
  privacy-aware by default, pullable off a real device. Wire it through the 18 silent
  failure paths.
- **Crash reporting.** Start with Xcode's built-in reports — zero work, no SDK, no
  privacy-label change. Add a real tool (Sentry) at 0.8.0 so app and server errors land
  in one place.
- **Product analytics — PostHog, decided 2026-10-22.** Logging says what broke; this
  says what players do. Without it the 1.0 activation event can't be measured, and
  neither can whether the sentence home teaches the rule, where runs end, or day-1/day-7
  return. Rules:
  - **A small, named event set** (~10: `run_started`, `link_landed`,
    `run_ended{reason, links, hardcore}`, `deal_again`, `reel_opened`, …). Autocapture
    and session replay off.
  - **The device id below is the anonymous id**; `identify` with the Supabase user id
    (never an email) on sign-in at 0.9.0, whichever provider. Anonymous first, same as
    accounts.
  - **No ATT prompt** — first-party usage analytics isn't cross-app tracking. The privacy
    label gains Product Interaction + an identifier. An opt-out toggle in Settings.
  - **Fired from the view/app layer, never `GameEngine`** — the same split as haptics and
    sound, so the engine stays pure.
  - **Behind an injected `Analytics` protocol** (like storage), so tests never send events.
  - **Measurement only.** PostHog's feature flags / remote config are not used — tuning
    and the kill switch belong to the service (0.8.0, Job 2). One owner for config.
- **Automated builds → TestFlight.** The release pipeline as a habit rather than an
  event, even though testers come later.
- **Stable device id.** A random identifier generated on first launch and stored locally;
  every score and Reel entry stamped with it. Today the local data has **no owner at
  all**, so there is nothing for a future account to claim. Pass & Play needs one anyway.
- **The merge rule — decided 2026-08-08.** What happens when local data meets account
  data (a device with a best of 11 and 200 Reel entries signing into an account with 7
  and 40):

  > **Highest best score wins. Reels combine. Streak takes the longer one.**

  It exists as a written rule *before* the auth code because the default behaviour of
  most sync implementations is "the server is the truth", which silently deletes the
  player's record. Nothing is ever lost by merging — the rule only ever moves a value
  upward or unions a set.

  **Three sub-cases the headline rule doesn't cover, with defaults:**
  - **Per-entity Reel counters.** `CollectedEntity` carries `timesLogged`; the same actor
    may be on both sides with different counts. **Take the max, don't sum.** Summing is
    more truthful across two genuinely-different devices, but it isn't idempotent — a
    merge that runs twice double-counts. Same for `chainsLogged`. Merging must be safe to
    repeat.
  - **Streaks.** Store the **set of completed days** and recompute the streak from the
    union, rather than merging the streak number itself. Same answer as "longer wins" in
    the normal case, and correct in the cases where it isn't.
  - **Two results for the same day.** One attempt per day is a rule; two devices is the
    loophole. **Highest wins**, and the daily should read its "already played today" state
    from the server once accounts exist.
- **Disk-cache the deal pool.** A cold launch fires ~24 concurrent TMDB requests (5
  `discover` pages + 1 page and 18 cast fetches for the derived actor pool), the pools
  are in-memory only, and it repeats every launch. The pool is a fixed
  `vote_count.desc` query — near-static and identical for every player. A ~24h disk cache
  removes most of that burst with no server. See [`GROWTH.md`](GROWTH.md) for the full
  rate-limit derivation.

---

## 0.8.0 — The service

**One deployment, three jobs over its life:** proxy TMDB (now), serve publishable content
(0.10.0), hold accounts and groups (0.9.0 / 0.11.0). Don't run three things.

**The platform: Supabase** *(decided 2026-10-23)*. Postgres, Auth (Apple, Google and
email built in), Storage for published puzzles, and Edge Functions for the proxy and
push — one vendor covers all three jobs. **Check before committing:** how the proxy
caches responses (Edge Functions have no built-in response cache — a cache table or a
CDN in front), and the free tier's pausing of idle projects.

**The safety rules — Supabase's real risk is configuration, not the platform.** The
key the app ships (`anon`) is public by design, so **row-level security is the only
thing between a table and the internet**; most Supabase leaks are a table left without
it. So:
- **RLS on every table, deny by default.** A table without policies doesn't merge.
- **The `service_role` key never enters the app** or the repo — it lives only in
  Edge Function secrets, like the TMDB token.
- **Writes that matter go through Edge Functions**, not straight table inserts — a score
  is re-validated server-side before it's stored (the anti-cheat already planned for
  friend groups).
- **Run Supabase's security advisor** before every schema change ships, and keep a test
  that tries to read and write each table with only the public key. *Both are
  `scripts/supabase-check.py` (2026-10-27), held to `supabase/access.toml`.*

**Why it's the first backend:** the proxy job is small, well-defined, genuinely needed,
and **nobody's data is at risk if it falls over.** It's the right place to learn hosting,
secrets, caching, deploys and monitoring — before the service that holds people's
accounts.

### Job 1 — the TMDB proxy

**The problem.** The TMDB token ships inside the `.ipa` and can be extracted, and every
install shares one key. Per the derivation in
[`GROWTH.md`](GROWTH.md#8-two-hard-gates-on-any-of-it): ~24 requests per cold launch
against a ~50 req/s key ceiling is roughly **two cold launches per second** before
saturation — and the failure mode is the home screen hanging on "Dealing…". Retries
amplify it (`prepareSeeds` retries 3×, `Config.candidateLoadAttempts = 3`).

**The fix:** a thin proxy holding the key and **caching the near-static responses**.
Because the deal pool is a fixed query identical for every player, one cached upstream
response serves the entire player base; cast and filmography for popular titles are
near-static too. Plausibly removes well over 90% of TMDB calls. **It also has to:** TMDB's
only rate limit is ~40 requests/second **per IP** (staff, 2026-03), so today every phone
gets its own allowance and the proxy concentrates everyone onto one. Keep cached
responses under the terms' six-month limit.

**Architecturally this is a new `MovieDataProvider` implementation, not an engine
change.** That protocol is exactly why this is cheap — keep the engine/provider split
clean and it stays that way.

### Job 2 — publishable content

**The point of a service is the boundary between what you can change and what needs an
App Store review.** Anything behind it changes instantly, for everyone, without a build.
What it should own:

- **Daily puzzles** — publish ahead, and fix a bad one the same day.
- **Themed packs** — a decade week, a genre run, a director's filmography. Content you
  publish, not code you ship.
- **Community puzzles** — a player sends a good pair, you publish it Tuesday.
- **Tuning** — round clock, par length, difficulty dials. These *will* change after the
  playtest and after launch; none of it should need a release.
- **A message channel and a kill switch** — "today's puzzle was broken, here's a
  replacement", or a maintenance notice when TMDB is down.

**The shape: separate authoring from serving.**

```
generator script  →  queue  →  [you approve]  →  published  →  CDN  →  app
   (your Mac,          (drafts)                   (immutable)
    via the proxy)
```

Three rules that matter:

- **A human approves before it publishes.** The generator walks a real path, so the game
  chose every node on it — a walk that wanders somewhere obscure strands everyone at once,
  publicly. Five seconds glancing at tomorrow's pair is very cheap insurance against the
  drift trap ([`ASSISTED-MODE.md`](ASSISTED-MODE.md#the-trap-worth-remembering-drift)). It
  also lets you hand-author a puzzle whenever you want — which you'll want for launch day.
- **Published content is immutable.** Once a daily has gone out, people have results
  against it. Corrections publish a *replacement*, they don't mutate the original.
- **Generation is idempotent.** Running the job twice must not produce two puzzles for the
  same date.

### Job 3 — accounts and groups

Lands with 0.9.0 and 0.11.0 on the same deployment.

### Client-side rules

- **Fetch ahead and cache.** Pull a week of puzzles at a time and keep them on device. Once
  there's a service, its uptime is your problem — design so an outage *degrades* rather
  than breaks, and the game keeps its offline character.
- **Config must never be able to brick the client.** Validate remote values against sane
  bounds locally; a bad number pushed to everyone is the classic remote-config incident.
- **The service is the only source of remote config.** Not PostHog's flags, even though
  the SDK is in the app — two config sources is two places to look when a value is wrong.

**Also lands here:** Sentry so app and server errors share one view. **The domain exists**
(2026-10-26): `playunspool.com`, Cloudflare Registrar. Put the service on a subdomain
(e.g. `api.playunspool.com`), never the bare domain or `www`, which are the site. Know that
on football match days Spanish ISPs block Cloudflare IP ranges (check
https://hayahora.futbol), so a service behind Cloudflare's proxy is unreachable from Spain
then, testing included.

*A detailed service design gets its own doc when it's built — this section is scope and
rationale, not architecture.*

---

## 0.9.0 — Accounts

**Why:** durable identity, so scores attach to a *person* rather than a device — the
prerequisite for friend groups (0.11.0).

**Shape — anonymous first, upgradeable:**
1. The **stable device id** from 0.7.0 is already carrying local data.
2. **Three ways to sign in** *(decided 2026-10-23)*, all through Supabase Auth:
   - **Sign in with Apple** — lowest friction on iOS, and required by App Store rules
     once Google login is offered.
   - **Google.**
   - **Email with a one-time code** (magic link / OTP) — no passwords, so no password
     storage, resets or breach exposure.

You can play forever without an account; signing in is a migration, never a gate.
**Built 2026-10-31** (`PlayerSession.swift`, migration `players`): every install is an
anonymous user; the rest of this paragraph is the design it follows.
**Preferred shape (2026-10-28): Supabase anonymous sign-in at first launch**, so every
player has an `auth.users` id from day one (it replaces the local sharer id and
`results.device_id`) and signing in *links* a provider to that same user instead of
migrating data between two ids; the display name lives on a `profiles` row from the
first share. The identity model is spelled out under the
[head-to-head rethink](#head-to-head--same-start-both-sides-see-the-score). Decide before
`results` fills up.
Accounts also give the community email list (see the
[launch track](#the-launch-track--runs-alongside-the-milestones)) — with **a separate,
unticked opt-in**, because signing in is not consent to marketing.

**Traps:**
- **Migration must merge, not clobber** — apply the rule written at 0.7.0.
- Sign in with Apple gives a **stable but app-specific** user id, and the email may be a
  private relay — don't use email as the identity key. To email relay addresses at all,
  the sending domain must be registered with Apple's private relay service.
- **One person, three providers:** someone who signs in with Google on one device and
  email on another must not get two accounts. Decide the linking rule (Supabase links
  identities by verified email) before the first real user exists.
- **Account deletion is an App Store requirement** once you offer accounts, and the
  privacy nutrition label changes.

---

## 0.10.0 — The Daily Chain

**The headline mode.** Two names and a par score, same for everyone that day; build the
**longest** chain that still reaches the target before the clock stops. One attempt.

**Fully specced in [`DAILY-CHAIN.md`](DAILY-CHAIN.md)** — rules, scoring, outcomes, the
share card, the engine changes, and the puzzle-generation job.

**Three things to restate here:**

- **Build every daily replayable** — a date-derived id and a stored puzzle, so a paid
  archive needs no rework ([Monetization-ready](#monetization-ready--built-in-switched-off)).
- **⚠️ Playtest before building.** Two people and index cards answer the open risks
  (padding, stranding, whether extend-or-bank is a real decision) for free. That test can
  happen *now* — it doesn't depend on any milestone above.
- **The generator inherits the drift obligation.** The puzzle is built by walking a real
  path, which means the game chose every node on it — so the walk must apply the
  familiarity standard at **every** step, not just the start. This is precisely how the
  removed Assisted mode failed; see [`ASSISTED-MODE.md`](ASSISTED-MODE.md#the-trap-worth-remembering-drift).

### Notifications — built as a system, measured from day one

Added 2026-10-23. A daily game only works if people come back each day, and nothing
reminds them. Build notifications as one system with one owner, not a scatter of
one-off calls, because every later layer (friend pushes, replaced-puzzle notices) adds
another kind of notification.

**The pieces:**
- **One `Notifications` owner** (injected, like storage and `Analytics`) that knows
  every kind of notification, schedules and cancels them, and handles opens through
  `UNUserNotificationCenterDelegate`. Each kind has an id, a Settings toggle and an
  analytics name.
- **The permission ask comes after the first completed Daily Chain**, never at launch.
  The context ("want a nudge when tomorrow's is ready?") is what gets a yes, and iOS
  only lets you ask once.
- **Local first, no server needed:**
  - *Daily ready* — "Today's chain is ready", at a fixed morning time.
  - *Streak protection* — an evening nudge ("your 12-day streak ends at midnight"),
    **only** when today isn't played yet. Streaks are stored as a set of completed
    days (0.7.0 merge rule), so the device can decide this itself; finishing today's
    chain cancels the pending nudge.
- **Server push (APNs) arrives with the service** — the message channel's "today's
  puzzle was replaced" at 0.8.0, friend pushes at 0.11.0. The device token is stored
  against the device id, then the account.
- **Push goes to APNs directly from a Supabase Edge Function — no Firebase**
  *(decided 2026-10-23)*. On iOS, Firebase Cloud Messaging is a relay in front of APNs;
  it would add a second vendor and SDK for nothing. One `.p8` key in the function's
  secrets is enough. Revisit only if Android ever happens.
- **Every kind can be turned off on its own in Settings**, and a turned-off kind is
  never sent.

**Metrics (PostHog, from the first build that has it):**
`notification_permission_prompted` / `_granted` / `_denied`, `notification_scheduled`
`{kind}`, `notification_opened{kind}`, `notification_kind_disabled{kind}`, and the iOS
authorization status read on each launch (people turn it off in system Settings without
telling the app). The questions they answer: what share say yes, which kinds get opened,
which kinds get turned off (a kind that gets turned off more than opened is spam — cut
it), and whether players with reminders on come back more.

**Traps:**
- Local notifications can't report "delivered" — only scheduled and opened. Don't build
  a metric that assumes delivery.
- A reminder for a puzzle that failed to fetch is worse than none: schedule *daily
  ready* only once tomorrow's puzzle is cached.
- Time zones: the day rolls over at the player's **local midnight**
  ([`DAILY-CHAIN.md`](DAILY-CHAIN.md#when-the-day-turns-over)). Streak protection fires a
  few hours before it, in whatever time zone the phone is in at the time — reschedule
  on a time-zone change, or a traveller gets the nudge at the wrong hour.

---

## 0.11.0 — Friend groups

**Not a leaderboard.** A group you join by **invite link with a code** — no usernames, no
search, no directory, no strangers. Everyone's daily result, and a challenge you can send
to one person ("here's my exact puzzle, beat my number").

**Why this shape:** cheapest possible group membership (no friend requests, no
moderation, no abuse surface), and it reuses the same link machinery as sharing and
challenges. It's also the model NYT converged on for Wordle.

**Anti-cheat is not a solved problem here and shouldn't be pretended otherwise.**
Server-side re-validation proves the links are real; it cannot prove they were recalled.
What makes friend-scale work isn't detection, it's **motive** — there's no prize and the
audience knows you. Design accordingly: no prizes, no ranked tiers, no stakes that would
reward inflating a number.

**Friend pushes** go through the notification system from 0.10.0 — "Sam beat your chain",
"Sam sent you a challenge". Each is its own kind with its own toggle and metrics.

**Decide before starting:**
- ~~What's compared — links, points, or both?~~ **Decided 2026-10-22: links, with
  points breaking a tie** — the same rule as the solo record (`Scoring.isNewRecord`).
- Group size cap, and what happens when someone leaves.
- Who can see whose history.

---

## 1.0.0 — Launch

The shipping checklist, plus the last player-facing pieces.

**Still to build:**
- **Share card with a link in it.** Both `shareSummary` and `CollectionStore.shareText`
  currently produce a nice artifact with **no URL** — the app's best organic asset
  converts at exactly zero. Add it the moment a listing exists.
- **Rendered share images.** SwiftUI `ImageRenderer` over the existing node components.
  **The trap:** `ImageRenderer` is synchronous, so any `AsyncImage` renders as its
  placeholder and poster art comes out empty — art must be fetched into memory first and
  handed in as a concrete `Image`. It's `@MainActor`, and `scale` must be set to the
  display scale or output looks soft. Keep the text card as a fallback.
- **Install tracking.** App Store Connect campaign links (`ct=`) — free, no SDK, no
  privacy-label change.
- **Activation event defined.** Proposed: first run reaching a chain of ≥ 3. (The engine
  already treats ≥ 2 as "a real combination landed" — it's the Reel-logging condition in
  `endGame()`.)
- **Scripted onboarding demo.** The app types the first link or two itself — hand-authored,
  ~15 seconds, skippable, once ever. **Safe because nothing is generated**: a fully
  authored demo can't drift, unlike a tutorial that picks links from live data. Pair with
  a **curated first seed**. Read [`ASSISTED-MODE.md`](ASSISTED-MODE.md) before touching
  this.
- **The app name**, and the store listing built around it.
- **Rating prompt** (`requestReview`) after a good moment — a new best, a third completed
  daily — never after a loss. iOS caps how often it actually shows.
- **"Send feedback" in Settings** — opens an email with the version and device id filled
  in, so "it froze" arrives with something to look up in the logs.

**Checklist:**
- **Real device testing.** Everything so far is simulator-verified. Haptics, audio session
  behaviour under the silent switch, and thermals/network on cellular need real hardware.
- **TestFlight beta with players who aren't you** — decided 2026-10-23, run from the
  waitlist well before this milestone (see the
  [launch track](#the-launch-track--runs-alongside-the-milestones)). Its retention is
  what says launch is ready. The case for it is [`ASSISTED-MODE.md`](ASSISTED-MODE.md):
  a mode survived four commits of refinement and died in one playtest.
- **The launch-track items** — screenshots, landing page, launch week.
- **App Store requirements:** privacy manifest / nutrition label (note: accounts and the
  PostHog SDK from 0.7.0 change these answers: Product Interaction, Other User Content
  (typed answers), Device ID, all not linked to identity and not used for tracking), **account deletion** since 0.9.0 ships accounts,
  and the **TMDB attribution** already rendered in the Reel sheet — keep it reachable.
  A **privacy policy URL and a support URL** — both required for the listing. Privacy is
  https://playunspool.com/privacy; it covers the website only until the app's section is
  added (from the app's code, before TestFlight goes beyond Abraham), and it still needs the
  controller's name. Support must be a web page, not a `mailto:`: the site adds `/support`
  before launch; until then, the home page.
- **Changelog + tag** per the process in `CLAUDE.md`.

---

## After 1.0 — the bets

Not scheduled. Ordered by what the players earn.

- **Pass & Play** — the deep-link chain handoff, fully designed in
  [`ARCHITECTURE.md`](ARCHITECTURE.md#direction-pass--play--a-chain-you-shuttle-between-friends).
  Build it with **Universal Links and a web fallback page**, not a bare custom scheme: as
  specced with `moviechain://` it's dead for anyone without the app, which makes it a
  retention feature. With a fallback page every handoff becomes an install path.
- **Practice mode** — unlimited unranked A→B pairs. Cheap once the generator exists, and
  it doesn't touch the daily's integrity.
- **Hints** — the escalating ladder (count → initial → letter blanks) designed in
  [`ASSISTED-MODE.md`](ASSISTED-MODE.md#if-assistance-returns-preserve-the-recall-act).
  **The open question stands: does a stuck player want a hint, or want the run to end so
  they can start fresh?** Test with two people before writing code — that document exists
  because a mode was built before that question was asked.
- **Chain → video renderer** — a macOS companion target that imports a chain and renders
  it offscreen. Content tooling; see [`GROWTH.md`](GROWTH.md).
- **Paid streak freeze** — protect a streak through a missed day, as an in-app purchase.
  Added 2026-10-23; it would be the first thing the app sells, so it opens the
  monetization question the plan has never asked. **The tension to settle first:** friend
  groups rest on "no prizes, no stakes that reward inflating a number". If streaks are
  shown in a group, a bought freeze is paying to protect a number your friends see. Keep
  streaks private, or make a freeze visible ("12 days, 1 frozen"). The free *streak
  protection* reminder at 0.10.0 is separate and ships regardless.
- **Home-screen widget** showing today's two names — a reminder that needs no permission.
- Genre locks, memory-recall every Nth link.

---

*Keep this current: when a milestone lands, move its entry into the changelog as a
released version and delete or rewrite its section here. When a plan changes, change it
here rather than letting the changelog table drift.*
