# Changelog

All notable changes to **Movie Chain** are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html) — read as
`MAJOR.MINOR.PATCH` on the *marketing version* (`MARKETING_VERSION`), with the build
number (`CURRENT_PROJECT_VERSION`) incrementing independently per submitted build.

**1.0.0 means launch.** The solo game loop is complete and tested, but six major
workstreams are planned *before* a public release — so the pre-1.0 minor versions are
allocated as milestone signals rather than picked by feel. **Each milestone is
documented in [`docs/ROADMAP.md`](docs/ROADMAP.md)** (scope, rationale, decisions to
settle, and the traps). **The plan was re-cut on 2026-08-08** — launch scope is now the
full loop (game + daily + friend groups), global leaderboards are dropped, and the
[Daily Chain](docs/DAILY-CHAIN.md) is the new headline mode:

| Version | Milestone |
|---|---|
| **0.4.0** | Solo game complete — engine, matching, providers, collection, tests |
| 0.5.0 | [**Foundations & safety net**](docs/ROADMAP.md#050--foundations--safety-net) — backup, logging, crash reporting, build pipeline, device id + merge rule, deal-pool disk cache |
| 0.6.0 | [**Design overhaul**](docs/ROADMAP.md#060--design-overhaul) — the real visual identity (today's look, including the chain treatment, is placeholder) |
| 0.7.0 | [**The service — TMDB proxy first**](docs/ROADMAP.md#070--the-service) — takes the shared key out of the app and caches it |
| 0.8.0 | [**Accounts**](docs/ROADMAP.md#080--accounts) — Sign in with Apple over the device id, with a merge that doesn't clobber |
| 0.9.0 | [**The Daily Chain**](docs/ROADMAP.md#090--the-daily-chain) — one puzzle a day: longest route from A to B ([spec](docs/DAILY-CHAIN.md)) |
| 0.10.0 | [**Friend groups**](docs/ROADMAP.md#0100--friend-groups) — invite-code groups, no global ranking |
| 1.0.0 | [**Launch**](docs/ROADMAP.md#100--launch) — share images + links, onboarding demo, store listing |

Until 1.0, breaking internal changes land in minor bumps. The order above is a plan,
not a contract — if milestones land out of order, the version follows the work.

## [Unreleased]

### Added

- **Design overhaul prototype: Cream Neobrutalist** (0.6.0 groundwork, on a branch).
  White cards with a 2pt ink border and a hard offset shadow on a cream canvas, a
  coral call-to-action, and a neobrutalist press where the shadow collapses. Actor
  stays blue and movie moves from purple to yellow, the most colour-blind-safe
  pairing. Every color has a dark variant, with cream borders on charcoal.
- **The chain drawn as cards** on the play screen: the newest link gets a hero card
  with its poster or headshot, the two before it get compact cards, and older links
  collapse into "+N earlier". Sized to fit above the docked keyboard on an iPhone 16.
  Settings → Chain style flips back to the tile stack so the two can be judged side
  by side on a device, which is how the roadmap says the chain treatment gets chosen.
- **One type system across every screen.** Three voices replace the old ad-hoc sizes:
  a bold serif with an italic flourish for numerals, names and the wordmark ("Movie
  *Chain*"), a sans body at two sizes, and one tracked uppercase label recipe in place
  of seven. Every figure is the serif, whatever its size: the timer, "2 links · 89
  pts", the Reel counts. Before, the same kind of number changed voice with its size. Movie years are an italic flourish everywhere instead of parentheses. The
  game-over recap reuses the play screen's compact cards, so the chain looks like one
  object from first link to last. Thin rules, soft shadows and the Reel's gradient
  name scrim are gone. Everything except the big numerals still scales with Dynamic
  Type.

### Changed

- **Lowered the iOS deployment target from 26.2 to 18.0**, roughly doubling the
  installable audience at no code cost. The 26.2 minimum was never a requirement — it
  was Xcode's default (current SDK) from project creation. An audit at successively
  lower targets found the true floor is **iOS 17.0**, blocked only by `@Observable`;
  18.0 is "current major plus one back" (Apple's numbering jumped 18 → 26) and keeps
  iOS 18 APIs available. The full suite passes on both an **18.0** and a **26.x**
  simulator. macOS/visionOS minimums are unchanged at 26.2.

## [0.4.0] — 2026-07-25

First versioned snapshot: a complete, playable solo game — engine, matching, data
providers, collection, and tests, behind a placeholder visual treatment. Everything
below predates versioning (19 commits, 2026-07-09 → 2026-07-25) and is collapsed into
this one entry; from here on, changes are recorded as they land. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for how it all fits together.

### Added

- **Core game loop** — a chain alternating actor → movie → actor, where each link
  must be real. Score is chain length; every turn is on a countdown.
- **Bounded-set validation** — each turn's valid answers are exactly one movie's
  cast or one actor's filmography, which is what makes validation exact and spelling
  tolerance safe.
- **Fuzzy matching** (`FuzzyMatch`) — diacritic-folded, punctuation-stripped
  Levenshtein with whole-word/prefix/containment boosts, so misspellings resolve
  without an autocomplete that would spoil recall. Roman-numeral sequel titles are
  normalised to digits (`"Mission: Impossible III"` ↔ `"mission impossible 3"`).
- **Data layer** — `MovieDataProvider` protocol with a live `TMDBProvider` and a
  hand-built offline `StubProvider`, so the game is playable with no network or API
  key. The TMDB credential loads at runtime from a gitignored plist.
- **Recognizability-tuned deal pools** — most-*watched* films via
  `discover?sort_by=vote_count.desc` (TMDB's trending endpoints surface
  viral-but-obscure titles), with the actor pool derived from those films' top-billed
  casts.
- **Scoring & juice** — points (base + speed + obscurity) alongside the headline
  chain length, plus haptics and synthesised sound (no bundled audio assets).
- **"Your Reel"** — a local, login-free collection of every actor/movie logged
  through play, with poster/headshot art, count stats, and the required TMDB
  attribution.
- **Play-first home** — leads with a *dealt* start ("Start with ⟨name⟩"), a Shuffle
  that deals fresh, and search demoted to an opt-in link. Fresh deal on every launch
  and resume, with recently-dealt starts avoided.
- **Design system** — an editorial NYT-Games/Connections treatment: `Theme` tokens,
  owned components, a warm-paper palette with blue = actor / purple = movie, and the
  signature `ChainStack` (the chain as a rising stack of category tiles).
- **Motion** — a direction-free forward screen carousel, a once-ever cold-launch
  intro, tile drops, staggered reveals, and a slim linear countdown; all honour
  Reduce Motion.
- **Share card** — a spoiler-free 🟦🟪 Connections-style recap.
- **Game-over summary** — final score, personal best fenced off from the run, the
  "you were one away" near-miss, a numbered chain recap, and "+N new to your Reel".
- **Settings sheet** — sound toggle and the app version (this release).
- **App icon** — a zigzag stack of alternating actor/movie tiles on ink.
- **Unit tests** — 42 covering matching, seed ranking, scoring, the deal policy,
  collection logging, and engine async-safety.

### Fixed

- **Stuck turns.** A stalled candidate fetch could freeze a turn indefinitely: the
  clock is deliberately paused across the fetch and no request timeout was set, so a
  hung connection sat on URLSession's ~60s default. Requests now time out quickly,
  transient failures retry silently, and an exhausted load surfaces a manual
  **Retry** that restarts the turn clock fresh.
- **Stale candidate loads.** A slow fetch from an abandoned or quit game could
  install the previous node's cast into a *new* round. Guarded by a monotonic
  `generation` token — a `phase == .playing` check alone can't catch it, because the
  new game is also playing.
- **Behind-the-scenes credits accepted as links.** TMDB movie credits include
  making-of and talk-show appearances where the person plays "Self"; those are no
  longer valid chain links.
- **Sequel mismatches.** `"mission impossible 3"` used to resolve to *Mission:
  Impossible II*, since character-level edit distance puts `"3"` closer to `"ii"`
  than `"iii"`.
- **Same-name TMDB stubs.** Seeding on a near-empty duplicate person record gave an
  almost-empty filmography and rejected real films. Records are now ranked
  canonical-first while genuine homonyms stay selectable (identity is the TMDB id,
  never the name).
- **Ambiguous fuzzy ties.** Two candidates hitting the same boosted score now
  tie-break on raw similarity, so results don't depend on candidate order.
- **A partial deal pool cached for the whole session.** The actor and movie sides now
  load independently and a failed side retries instead of being cached as loaded.
- **Timer could end a game on a timely answer** — the clock stops across the
  candidate fetch.
- **Main-thread hitches** — JSON now decodes off the main actor, and the
  haptic/audio engines warm on the idle home screen rather than mid-transition.

### Changed

- `filmography(of:)` is sorted most-popular first, so the "you were one away"
  near-miss surfaces a film the player would actually recognise.
- The deal pool loads ~100 titles instead of ~40, so a run of shuffles stops
  recycling the same few films.
- iPhone is portrait-only (the play screen docks the keyboard by design); iPad keeps
  all orientations.

### Removed

- **Assisted mode** (multiple-choice difficulty). Built, unit-tested, refined over
  four commits, playtested — and removed, because it served neither audience: it
  still confounded newcomers (the hard part isn't recognising a name, it's knowing
  who was in what) while removing the act of recall that *is* the accomplishment for
  the enthusiast. The reasoning, the "drift" trap any link-picking feature inherits,
  and the hint-shaped design to build instead are recorded in
  [`docs/ASSISTED-MODE.md`](docs/ASSISTED-MODE.md); the code remains recoverable
  from git.

<!--
  Version headings are intentionally un-linked: this repo has no remote yet. Once
  one exists, add compare links here, e.g.
  [0.4.0]: https://github.com/<owner>/movie-quiz/releases/tag/v0.4.0
-->

