# Roadmap to 1.0 (launch)

> **1.0.0 means launch.** The solo game loop is complete and tested at
> [`0.4.0`](../CHANGELOG.md). This plan was re-cut on **2026-08-08** after a planning
> conversation that changed the launch scope, dropped global leaderboards, and added a
> new headline mode. Six milestones stand between here and a public release.
>
> This doc is the *planning* layer: scope, rationale, what each milestone touches, and
> the decisions/traps to settle before writing code. Deep technical designs live in
> [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`DAILY-CHAIN.md`](DAILY-CHAIN.md) and are
> linked rather than duplicated. The order is a plan, not a contract — if milestones land
> out of order, the version follows the work.

| Version | Milestone | Depends on |
|---|---|---|
| 0.5.0 | [Foundations & safety net](#050--foundations--safety-net) | — |
| 0.6.0 | [Design overhaul](#060--design-overhaul) | — |
| 0.7.0 | [The service — TMDB proxy first](#070--the-service) | — |
| 0.8.0 | [Accounts](#080--accounts) | 0.5.0 (device id), 0.7.0 (a backend) |
| 0.9.0 | [The Daily Chain](#090--the-daily-chain) | 0.7.0 (generation job) |
| 0.10.0 | [Friend groups](#0100--friend-groups) | 0.8.0 |
| 1.0.0 | [Launch](#100--launch) | all of the above |

## The decisions this plan rests on

Settled 2026-08-08, so they don't get re-litigated mid-build:

- **Launch scope is the full loop.** Endless game + the Daily Chain + friend groups, all
  before the App Store. The goal is to own the complete cycle — publish, tracking, auth,
  backend, devops — not to get to market fastest.
- **No release before launch.** No early TestFlight round for practising the pipeline.
  *(Open: whether the pre-launch TestFlight round in the 1.0 checklist still stands — see
  [1.0](#100--launch).)*
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

## 0.5.0 — Foundations & safety net

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
  privacy-label change. Add a real tool (Sentry) at 0.7.0 so app and server errors land
  in one place.
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

## 0.6.0 — Design overhaul

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

## 0.7.0 — The service

**One deployment, three jobs over its life:** proxy TMDB (now), serve publishable content
(0.9.0), hold accounts and groups (0.8.0 / 0.10.0). Don't run three things.

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
near-static too. Plausibly removes well over 90% of TMDB calls.

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

Lands with 0.8.0 and 0.10.0 on the same deployment.

### Client-side rules

- **Fetch ahead and cache.** Pull a week of puzzles at a time and keep them on device. Once
  there's a service, its uptime is your problem — design so an outage *degrades* rather
  than breaks, and the game keeps its offline character.
- **Config must never be able to brick the client.** Validate remote values against sane
  bounds locally; a bad number pushed to everyone is the classic remote-config incident.

**Also lands here:** the domain (needed for links later), and Sentry so app and server
errors share one view.

*A detailed service design gets its own doc when it's built — this section is scope and
rationale, not architecture.*

---

## 0.8.0 — Accounts

**Why:** durable identity, so scores attach to a *person* rather than a device — the
prerequisite for friend groups (0.10.0).

**Shape — anonymous first, upgradeable:**
1. The **stable device id** from 0.5.0 is already carrying local data.
2. **Sign in with Apple** as the upgrade path. Lowest friction on iOS, no password
   infrastructure, privacy-preserving.

You can play forever without an account; signing in is a migration, never a gate.

**Traps:**
- **Migration must merge, not clobber** — apply the rule written at 0.5.0.
- Sign in with Apple gives a **stable but app-specific** user id, and the email may be a
  private relay — don't use email as the identity key.
- **Account deletion is an App Store requirement** once you offer accounts, and the
  privacy nutrition label changes.

---

## 0.9.0 — The Daily Chain

**The headline mode.** Two names and a par score, same for everyone that day; build the
**longest** chain that still reaches the target before the clock stops. One attempt.

**Fully specced in [`DAILY-CHAIN.md`](DAILY-CHAIN.md)** — rules, scoring, outcomes, the
share card, the engine changes, and the puzzle-generation job.

**Two things to restate here:**

- **⚠️ Playtest before building.** Two people and index cards answer the open risks
  (padding, stranding, whether extend-or-bank is a real decision) for free. That test can
  happen *now* — it doesn't depend on any milestone above.
- **The generator inherits the drift obligation.** The puzzle is built by walking a real
  path, which means the game chose every node on it — so the walk must apply the
  familiarity standard at **every** step, not just the start. This is precisely how the
  removed Assisted mode failed; see [`ASSISTED-MODE.md`](ASSISTED-MODE.md#the-trap-worth-remembering-drift).

---

## 0.10.0 — Friend groups

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

**Checklist:**
- **Real device testing.** Everything so far is simulator-verified. Haptics, audio session
  behaviour under the silent switch, and thermals/network on cellular need real hardware.
- **TestFlight round with players who aren't you.** ⚠️ **Open** — the 2026-08-08 decision
  was "no release before the App Store", which may or may not have been meant to include
  this. The argument for keeping it is [`ASSISTED-MODE.md`](ASSISTED-MODE.md): a mode
  survived four commits of refinement and died in one playtest.
- **App Store requirements:** privacy manifest / nutrition label (note: accounts and any
  analytics SDK change these answers), **account deletion** since 0.8.0 ships accounts,
  and the **TMDB attribution** already rendered in the Reel sheet — keep it reachable.
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
- Genre locks, memory-recall every Nth link.

---

*Keep this current: when a milestone lands, move its entry into the changelog as a
released version and delete or rewrite its section here. When a plan changes, change it
here rather than letting the changelog table drift.*
