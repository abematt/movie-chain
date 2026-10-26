# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope note

This repo lives under `/Users/abrahammathew/dev/`, which is nested inside a Measure Protocol
workspace. Ancestor `CLAUDE.md` files (Measure workspace, Django/Docker services, survey tooling,
etc.) are **not relevant here** — this is a standalone native iOS/SwiftUI app. Ignore the Measure
guidance when working in this repository; only this file and the code apply.

## Project

`movie-quiz` — a SwiftUI game called **Unspool** (it was "Movie Chain" until 0.6.0; the
bundle id and code names stay `movie-quiz`). You build a chain
that alternates actor → movie → actor → movie …, where each link must be real
(the actor appeared in the movie). Score = chain length; each turn is timed.

- Bundle ID: `abe.movie-quiz`
- Language: **Swift 6** language mode (full data-race checking), SwiftUI + Observation
  (`@Observable`), iOS 17+ APIs. Approachable Concurrency is on, so a `nonisolated
  async` function runs on its *caller's* actor — use `@concurrent` to really leave main
- Builds with **MainActor-default isolation** (`SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`) — off-main-actor code must opt out explicitly (e.g. the
  `nonisolated` `Codable` values in `Collection.swift`; resolve `@MainActor`
  defaults in init bodies, not default arguments)
- Deployment target: **iOS 18.0** — the floor is actually iOS 17 (`@Observable`
  is the only thing blocking 16); 18.0 is "current major plus one back", since
  Apple's numbering jumped 18 → 26. New APIs above 18.0 need `if #available`.
  macOS/visionOS minimums are still 26.2 (secondary platforms, unverified)
- Supported platforms: iOS, iPad, macOS, visionOS
- Orientation: **iPhone is portrait-only**; iPad keeps all orientations. The play
  screen docks the keyboard as its primary layout, so the game is portrait by design.
- App target (`movie-quiz`) + `movie-quizTests` unit-test target, one shared scheme.
- Files are auto-included via `PBXFileSystemSynchronizedRootGroup` — just add
  `.swift` files under `movie-quiz/` (or `movie-quizTests/` for tests), no
  `.pbxproj` editing needed.

## Commands

Build/run/test from the command line with `xcodebuild` (project, not workspace):

```bash
# List targets, configs, schemes
xcodebuild -list -project movie-quiz.xcodeproj

# Build for the simulator
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests (target `movie-quizTests`)
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test (Swift Testing — suites are structs, tests have no `test` prefix)
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:movie-quizTests/FuzzyMatchTests/rejectsOffListAnswer()
```

Day-to-day development is normally done in Xcode (⌘B build, ⌘R run, ⌘U test). `#Preview` blocks
drive SwiftUI canvas previews.

## Versioning & changelog

The app is versioned and every notable change is recorded in
[`CHANGELOG.md`](CHANGELOG.md) (Keep a Changelog + SemVer). **Currently `0.7.0`;
`1.0.0` means launch.** Each remaining pre-launch milestone is allocated a minor
version — design overhaul (0.5.0, **landed**; motion re-tune landed as 0.5.1, the Reel as a collection as 0.5.2, its polish as 0.5.3),
the Unspool rebrand (0.6.0, **landed**), Ground & Object with the first foundations (0.7.0, **landed**; logging, crash reporting and the build pipeline still to come), the service /
TMDB proxy (0.8.0), accounts (0.9.0), the Daily Chain (0.10.0), friend groups (0.11.0);
share images ship with launch (1.0.0). Global leaderboards are dropped — **check the
changelog table before choosing a bump**. Each is documented in
[`docs/ROADMAP.md`](docs/ROADMAP.md) (scope, decisions to settle, known traps); read
the relevant section before starting one.

> Note: the visual design is **Ground & Object** (landed 2026-10-24, replacing 0.5.0's
> Cream Neobrutalist; specced on a design canvas — see
> [`docs/ROADMAP.md`](docs/ROADMAP.md#ground--object--the-10-look)): paper ground,
> objects with a hard ink side, blue/yellow only on objects and in the answer dock,
> Night for game over, Archivo + JetBrains Mono caps, no serif or italics. The chain
> is drawn as the **Deck** (`ChainDeck.swift` — a physical pile
> that fills the space above the keyboard); the Cards and Tiles styles that sat behind
> a setting were removed once the Deck won. The motion re-tune landed as 0.5.1. The recurring
> constraint is still vertical room against the docked keyboard. Vocabulary is fixed:
> a *chain* is a whole run, a *link* is one correct answer (the score counts links),
> the dealt start is not a link, and the best run is the most links with points
> breaking ties (`Scoring.isNewRecord`). Reuse `Theme` tokens and `Components` — never
> hardcode fonts, colours or sizes.

- **Where the version lives:** `MARKETING_VERSION` (e.g. `0.4.0`) and
  `CURRENT_PROJECT_VERSION` (the build number) in build settings — set in all four
  configurations in `project.pbxproj`, so the app and test targets agree. Code reads
  them from the bundle via `Config.appVersion` / `buildNumber` / `versionString`
  (**never hardcode a version**), and Settings displays it.
- **When you land a user-visible change:** add a bullet under `## [Unreleased]` in
  the changelog, in the right category (Added / Changed / Fixed / Removed). Say what
  changed *and why it mattered* — the existing entries set the tone.
- **When you cut a version:** rename `[Unreleased]` to the new version + date, bump
  `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` for a submitted build), then
  tag it:
  ```bash
  sed -i '' 's/MARKETING_VERSION = 0.7.0;/MARKETING_VERSION = 0.8.0;/g' \
    movie-quiz.xcodeproj/project.pbxproj
  git tag -a v0.8.0 -m "0.8.0"
  ```
  Bump **minor** when a roadmap milestone lands, **patch** for fixes/polish in
  between. Pre-1.0, breaking internal changes go in a minor bump.
- **Before tagging, run `/diary`** so the version's chapter is written and
  committed with the release (see *Dev diary* below).

## Dev diary

`diary/` is a running dev diary: one chapter per release, written from what actually
happened (sessions, commits, screenshots, phone photos), as raw material for posts.
`diary/README.md` has the layout.

- **Capture is automatic.** A `SessionEnd` hook (`.claude/settings.json`) runs
  `scripts/diary-capture.py`, which saves each session's slimmed transcript to
  `diary/raw/` and copies its scratchpad screenshots and pasted images into
  `diary/media/<sid8>/`. Transcripts age out of `~/.claude` after 30 days and
  scratchpads live in `/tmp`, so without this the material is lost.
- **Writing is `/diary`** (`.claude/skills/diary/`): it backfills captures, writes or
  extends the chapter for the current version, and rebuilds the page with
  `python3 diary/build_html.py`.
- **Phone photos/videos of builds** go in `diary/inbox/`; `/diary` dates and files them.
- **Git:** chapters (`diary/NN-*.md`) and `diary/web/` (downscaled images the chapters
  use) are committed; `diary/raw/`, `diary/media/`, `diary/inbox/` and `index.html`
  stay local. The repo is public, so no secrets or other people's details in a chapter.
- **Never publish the diary page** (artifact, Drop, anything) without asking which
  account to use; it has gone to the work account twice.

## Swift conventions

**Load the `write-swift` skill before writing or reviewing Swift here** (it's committed
under `.claude/skills/`). It's the standard; this section adds the rules this codebase
has actually been bitten by, and how they're enforced.

- **Leaving the main actor needs `@concurrent`.** Approachable Concurrency is on, so a
  `nonisolated async` func runs on its *caller's* actor — main, here. That's how TMDB
  decoding sat on the main thread while its comment said otherwise.
- **`.task` / `.task(id:)`, not `onAppear { Task { … } }`.** `.task` is cancelled when
  the view goes away; an `onAppear` task isn't (a stale celebration fired after a fast
  "Play again"). `try? await Task.sleep` swallows cancellation, so check
  `Task.isCancelled` after it before doing anything visible.
- **`@Sendable` view closures** (`keyframeAnimator`, `visualEffect`, `onGeometryChange`,
  `Shape.path`) copy what they need in a capture list — `{ [reduceMotion] … }` — never
  read `self`.
- **No device locale in matching or parsing** — `locale: nil`, never `.current` (Turkish
  folds "III" to "ııı").
- **Storage is injected** (`UserDefaults`, file URLs, clocks) so tests never touch the
  app's real records.
- **Shared async loads are joined, not duplicated** — keep the in-flight `Task` and
  await it (see `GameEngine.poolLoad`).
- **State that only exists in one phase lives on that phase** (`.gameOver(Summary)`),
  and resets go through one function (`resetRun()`).
- **Tests use Swift Testing** — struct suites, `#expect`, `@Test(arguments:)` for
  tables. XCTest only for UI automation or `XCTMetric`.
- Spell existentials `any P`; prefer `some P` unless it's stored or swapped at runtime.

**Enforcement:**
- **Compiler** — Swift 6 language mode and `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`
  (all configurations), so a data-race or isolation warning fails the build.
- **`scripts/swift-check.py`** — the grep-able rules: `XCTestCase`, `Task.detached`,
  `DispatchQueue.main`, `locale: .current`, `print(`, `ObservableObject`/`@Published`,
  `nonisolated … async` without `@concurrent`, a `Task` inside `onAppear`, PostHog
  outside `Analytics.swift`, and telemetry inside `GameEngine`. A
  deliberate exception carries `// swift-check:ignore — <why>` on the line.
  - Runs after every Claude Code edit to a Swift file (`.claude/settings.json`
    PostToolUse hook) — a violation is reported back immediately; fix it.
  - Runs as a git pre-commit hook on staged Swift. **Enable it once per clone:**
    `git config core.hooksPath .githooks`
- **`/swift-review [base]`** — the judgment pass a script can't do (value vs reference,
  `some`/`any`, reentrancy, structure, test coverage). Run it on a branch before merging.

## The website

The landing page is https://playunspool.com, in its own repo `../unspool-site`
([`abematt/unspool-site`](https://github.com/abematt/unspool-site)). Its
[`docs/handover-app.md`](https://github.com/abematt/unspool-site/blob/main/docs/handover-app.md) is what the app owes it; the parts that bite here:
- **Its hero phones are real screens**, shot by the site's `scripts/screens.py` with these
  DEBUG flags: `-uiDemoChain`, `-uiDemoGameOver [-uiDemoNoBest] -uiDemoClean`,
  `-uiDemoReel -uiOpenReel`. Renaming or changing one breaks it: update `screens.py` too.
- **It makes promises**: free on iPhone, beta invites in November, all from memory (no
  suggestions, no multiple choice), a card per actor and a frame per film, challenge a
  friend from the same start. Changing any of those means changing the site. It never
  advertises unshipped work.
- **Privacy**: https://playunspool.com/privacy covers the website only. Its app section is
  drafted in [unspool-site PR #1](https://github.com/abematt/unspool-site/pull/1) and merges before the first beta invite, after a re-check
  against the code (the roadmap's "Before the beta" lists what else to settle then).

## Analytics

**Every user-facing feature reports through `Telemetry` (PostHog). Read
[`docs/ANALYTICS.md`](docs/ANALYTICS.md) before building one, and update it in the same
change** — a test fails if its event list and `EventName` disagree.

- Views call `Telemetry` (`\.telemetry`); the engine only records plain facts
  (`GameEngine.Turn`, `Summary`) and never sends. Only `Analytics.swift` touches PostHog.
- **A property before an event** — the free tier is 1M events/month and the app spends
  ~47 a session. Screen times ride on the event that ends the screen; settings and the
  game mode are shared context on every event, not events.
- A new area or mode gets its own `Telemetry+<Area>.swift` with its own state struct.
- Durations use the injected clock and are tested with the recording sink.
- Sign-in (0.9.0) calls `Telemetry.signedIn(accountID:)` / `signedOut()`.

## Architecture

> For the full module-by-module breakdown, game-loop diagram, and design
> rationale, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Keep that doc
> current when the architecture, providers, rules, or stack change; the summary
> below should stay lean.
>
> **The rest of the doc set** (each has a distinct job — keep the right one current):
> [`docs/ROADMAP.md`](docs/ROADMAP.md) = the planned path to 1.0, milestone by
> milestone (**re-cut 2026-08-08** — read it before planning any work);
> [`docs/DAILY-CHAIN.md`](docs/DAILY-CHAIN.md) = spec for the planned headline mode (one
> puzzle a day, longest route A→B — specced, **not playtested, not built**);
> [`CHANGELOG.md`](CHANGELOG.md) = what changed per version;
> [`docs/ASSISTED-MODE.md`](docs/ASSISTED-MODE.md) = postmortem of a removed mode,
> **read it before building anything that picks chain links for the player**;
> [`docs/GROWTH.md`](docs/GROWTH.md) = growth mechanics as a **build catalog** (share
> loop, daily chain, challenge links, chain→video), sized and mapped to the code, plus
> the TMDB request-rate gate that constrains any acquisition push;
> [`docs/ANALYTICS.md`](docs/ANALYTICS.md) = the **tracking plan** — every analytics
> event and property, the rules, and the checklist for adding analytics to a feature.

The game logic is fully decoupled from both the UI and the data source.

**Domain types** — `Models.swift` defines the core entities: `Person`, `Movie`,
the `ChainNode` enum (a link is either an actor or a movie) and `NodeKind`. All
are `Identifiable`/`Hashable`/`Sendable` and carry a stable TMDB id, which is
what makes validation and the no-repeat dedup exact.

**Data layer** — everything speaks the `MovieDataProvider` protocol
(`MovieDataProvider.swift`): global `searchActors`/`searchMovies` (the opt-in
"pick your own start" search), `popularActors`/`popularMovies` (the deal pool —
tuned for *recognizability*: movies are the most-*watched* of all time via TMDB
`discover?sort_by=vote_count.desc`, actors are derived from those films' top-billed
casts, since TMDB's trending `*/popular` surfaces obscure/unfamiliar names), plus
`cast(of:)` and `filmography(of:)` (the *bounded candidate sets* used to validate
every subsequent link).
- `TMDBProvider.swift` — live implementation over the TMDB REST API.
- `StubProvider.swift` — a small hardcoded movie/cast graph so the game is
  playable with no network/key. `Config.makeProvider()` picks TMDB when a token
  is set, else the stub.

**Validation & the spelling problem** — players type free text; there is no
autocomplete (that would spoil a recall game). Because the set of valid answers
each turn is small and known (one movie's cast, or one actor's filmography),
`FuzzyMatch.bestMatch` matches the typed text against just that bounded set with
spelling tolerance (diacritic-folded, punctuation-stripped Levenshtein + whole-
word/substring boosts, threshold ~0.72). This is why misspellings like "John
Malkovic" resolve correctly without global fuzzy search or false positives.

**Game engine** — `GameEngine.swift` (`@MainActor @Observable`) owns all state:
`phase` (seed → playing → gameOver), the `chain`, `score` (chain length) +
`points` (base + speed + obscurity bonuses), per-turn countdown, the current
candidate set, `usedIds` (no-repeat rule), persisted `bestChain`/`bestPoints`,
and the `missedAnswer` near-miss. `loadCandidates` **retries** transient fetch
failures (+ a short request timeout) so a rate-limit/stall can't freeze a turn; an
exhausted load surfaces a manual `retryTurn` (`awaitingRetry`). It also owns the **home-screen deal**: the
cached popularity pools, the `dealtSeed` the home renders, and a `recentSeedIds`
ring buffer — `prepareSeeds()`/`shuffleSeed()`/`dealFreshOnResume()` all route
through a private `deal()` that delegates the *policy* to the pure
`SeedDeal.pick` (`SeedDeal.swift`, unit-tested: popularity pool, actor bias,
recent-id avoidance). Every entity resolves to a stable TMDB id, so
validation and dedup are exact. Async candidate loads are guarded by a monotonic
`generation` token (bumped on start/end/reset) so a slow fetch from an abandoned
or quit game can't install stale candidates into a new round. `Config.swift` holds
tunables (`secondsPerTurn`, `seedActorBias`, `seedRecentWindow`, `seedMoviePoolPages`, `requestTimeout`, `candidateLoadAttempts`) and loads the TMDB credential at runtime from a
**gitignored** `movie-quiz/TMDBSecrets.plist` (copy `TMDBSecrets.example.plist`
and paste a token; absent → app falls back to `StubProvider` demo data). The
token is never committed to source.

**Scoring & juice** — the engine stays pure; all feedback is fired from the view
in reaction to engine state. `Scoring.swift` (pure, unit-tested) defines the
point math (base + speed + obscurity); `Haptics.swift` and `Sound.swift`
(synthesised tones, no assets, `@AppStorage("soundEnabled")`) provide the
tactile/audio payoff. `engine.shareSummary` builds a spoiler-free 🟦🟪 share card.

**Collection ("Your Reel")** — `Collection.swift` + `CollectionView.swift`: a
local, login-free registry of every actor/movie the player has logged, a
"look how many you know" retention hook. `CollectedEntity` is a pure `Codable`
value (deduped by TMDB id); `CollectionStore` (`@MainActor @Observable`) owns
the dictionary + a `chainsLogged` counter, persisted as JSON in Application
Support (**not** SwiftData — small bounded data, matches the engine's UserDefaults
style). The single logging rule lives in `record(chain:)`, called from
`endGame()` only when `chain.count >= 2` **and the run is Hardcore** — those two
conditions encode "successful combinations only, seed counts once a link lands, bare
seed logs nothing, and nothing logged for a run where the answers were shown to
you". Pure count stats from your own play — no TMDB rarity. `record` also links
each adjacent pair both ways (`CollectedEntity.links`), so **actors are playing
cards earned through the films linked through them** and **movies are framed
posters**; either flips over to the other side of its links (no progress for movies
— a cast is never completable). An actor card's front carries only its collector
number (`ReelNumber`: the order you first linked them, a set number, not a score) and
five dots toward holo — **no counts on the fronts**; the finish is the reward. Its
photo is printed in the actor's own `Duotone` (one of the foil's five pastels, by
TMDB id), **baked into the cached image off-main by `ArtCache`** — never tint it
with a mask or blend mode, which would push a tilting card offscreen every frame.
`ReelCards.swift` draws both. The Reel narrows by decade and genre (`ReelFilter`:
films match directly, actors through a linked film; genre ids ride along on every
TMDB movie response, names are a fixed table). An actor card's finish comes from the
pure, tested `ReelTier`: paper, pastel at 5 films linked (the face in the
photo's pastel), holo at 11 — **no TMDB data,
no extra request; never add a fetch on Reel open**. Cards and frames are drawn once
at their grid size and scaled (`ReelCanvas`), so a lift is a pure zoom: the lifted
card flies itself out of its measured grid slot and back onto it, drawn above
everything (`ReelCardDetail` + `LiftFlight`) — **not** `matchedGeometryEffect`, which
flew the grid's own card under the dim layer and its neighbours. Art is read
through **`ArtCache`** (memory `NSCache` + a 150MB disk-cached session, off-main
decode), not `AsyncImage`, which has no memory cache; the Reel's first screen is
warmed at launch. The store is owned at the app root and injected into the engine.
A lifted card or framed poster tips with the gyro or a drag (`CardTilt.swift`): the tilt object is
injected through `\.cardTilt` and **read only by leaf views** (foil, parallax, glare,
rotation) — never pass the tilt value into the card, or every frame
re-runs its body. Tilt, its intensity ramps and the drag release all run on
`DisplayLink` with hand-sampled springs (`Theme.Motion.tiltIn/Out/Release`), and the
card is flat whenever `LiftFlight` is flying it.
`-uiDemoReel -uiOpenReel` (DEBUG) opens a demo Reel without touching the saved one;
add `-uiLiftFirst` to lift its first card.

**UI (NYT-Games / Connections treatment)** — `ContentView.swift` routes on
`engine.phase` between `SeedView`, `GameView`, and `GameOverView` with a
**direction-free forward carousel** (`.screenPush` on `Theme.Motion.screen`: the
app is a one-way loop, so every change pushes the new screen in from the trailing
edge — no "back"; Reduce Motion → cross-fade; seed → play alone cross-fades under the handoff). It owns the
shared `CollectionStore` (opened as a `.sheet` from the seed and game-over
screens) and the persisted once-ever `seedIntroDone` flag driving `SeedView`'s
first-run cold-launch intro (the `Wordmark` starts centered and large, then rises to
the header as the rest cascades in). `SeedView` is **the first turn, as a sentence**:
under the wordmark header (Reel pill + gear pill), the *dealt start* reads "⟨name⟩ *was
in* / a movie…" (movies: "*starred* / an actor…") with the name in a fixed-height,
bottom-pinned region so the **blank** never moves. The blank is the start button:
tapping it runs the **handoff** (`Handoff.swift`) — a `HandoffStage` owned by
`ContentView` collects frames both screens report, and `HandoffFlight` draws copies of
the name/chip/avatar/blank flying into the deck's start card and the dock on its own
`TimelineView` clock, waiting for the answer field's first (main-thread-blocking) focus
to pass. Seed → play is a cross-fade under it, not a push. "Deal again" deals on
`.dealSentence`; "Pick your own" opens search; the best run is a centred footer line (no instruction text — the sentence is the
rule, and the blank nudges once for a new player). The engine
prefetches the dealt start's candidates (`prefetchCandidates`) so the first turn is
ready on arrival. `-uiAutoHandoff` (DEBUG) taps the blank two seconds after a deal, to
record the transition. The Reel pill is always reachable (count hidden when empty),
because the Reel sheet hosts the required **TMDB attribution**. Brand art (`Wordmark`, `LogoMark`,
`FilmStrip`, the two-circle `AppIcon`) lives in the asset catalog as SVG/PNG with
dark variants — never redraw it in code. Styling is a
small design-system layer: `Theme.swift` (color/spacing/radius/motion tokens +
per-node category identity — **blue = actor, yellow = movie**) and
`Components.swift` (`.neoSurface` = edge + a hard side straight down,
`DockGround` = the coloured dock, `SlabButtonStyle` = dock slabs, `PrimaryButtonStyle`
= an ink slab, `GhostButtonStyle`, `PressScaleStyle` = `.pressScale` subtle press
feedback, `Heading`, `NodeDot`, plus juice pieces `Shake`/`FloatingGain`/`StaggeredAppear`
(`.appear(i)`)), all built on the Ground & Object palette in `Assets.xcassets`
(Canvas/Ink/Tile/Shadow/Hairline/Socket/Night/Go/ActorBlue/MovieYellow/Good/OnAccent,
each light+dark; dark is a dim room where black stays the side). The chain is the **Deck** (`ChainDeck.swift`: every link is one card for
its whole life — a new one is dealt in from below and pushes the last back into a pile
that peeks out above it, sized to the room above the keyboard); `ChainCards.swift`
holds the pieces it shares with the handoff (`KindChip`, `ChainArt`). The dealt
start wears a holographic sticker (`HoloSticker.swift`) instead of a number; its
foil holds still on the deck — **don't make it gyro-live during play**, which kept a
120Hz main-thread loop running while the player typed. The game screens cap Dynamic
Type at `Theme.Font.gameTypeCap` (the sheets don't), and the deck's card height and
peeks scale with it (`@ScaledMetric`); check `-uiDemoChain -uiWorstCase` at a large
text size on an SE after touching either. The play screen docks the answer dock (coloured for the kind you name next,
carrying the prompt) via `.safeAreaInset(.bottom)` above the
**always-present keyboard** (with `TimerBar.swift` as a slim linear countdown), and
swaps the field for a **Retry** slab if a candidate load failed
(`engine.awaitingRetry`). Game over is on Night (the holo sky for a new best), with the
chain as a `CoinStack` and the recap below; Share sends a `ShareCard` image. A drag on
the stack opens it at a link: its lifts are tweens on its own clock (`Theme.Motion.stack*`),
run only while a coin moves, and **a coin is never drawn above the one on it** and only the
top and chosen coins show a face; keep both rules if you change it. App-wide
tint (ink) is set once in `movie_quizApp`. Prefer reusing these over hardcoded values.

Remaining fan-out modes (the Daily Chain, friend groups, genre locks, memory-recall
every Nth link) all layer on this same engine — keep the engine/provider split clean.
Accounts arrive at 0.9.0 (Apple, Google or email one-time code via Supabase, over a
device id); the local
collection/session data is forward-compatible with that sync. There will be no global
leaderboard.

A multiple-choice **Assisted mode was built, playtested, and removed** (it served
neither the newcomer nor the enthusiast). Read
[`docs/ASSISTED-MODE.md`](docs/ASSISTED-MODE.md) before building anything that picks
chain links *for* the player (easier mode, tutorial, daily seeded chain) — it records
the reasoning, the **drift** trap such features inherit, and the hint-shaped design
to build instead. The code is recoverable from git (SHAs in that doc).

## Running it

Build succeeds for the simulator. The deployment target is **iOS 18.0**, so any
18.x-or-later runtime works — the suite is verified green on both **18.0** and
**26.x**. In Xcode: pick a simulator and ⌘R. When touching anything version-sensitive,
run the tests on an 18.x simulator too, not just the newest, since that's the floor
the App Store build has to honour:

```bash
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' test
```
