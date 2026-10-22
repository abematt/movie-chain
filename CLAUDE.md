# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope note

This repo lives under `/Users/abrahammathew/dev/`, which is nested inside a Measure Protocol
workspace. Ancestor `CLAUDE.md` files (Measure workspace, Django/Docker services, survey tooling,
etc.) are **not relevant here** — this is a standalone native iOS/SwiftUI app. Ignore the Measure
guidance when working in this repository; only this file and the code apply.

## Project

`movie-quiz` — a SwiftUI game (working title "Movie Chain"). You build a chain
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
[`CHANGELOG.md`](CHANGELOG.md) (Keep a Changelog + SemVer). **Currently `0.5.2`;
`1.0.0` means launch.** Each remaining pre-launch milestone is allocated a minor
version — design overhaul (0.5.0, **landed**; motion re-tune landed as 0.5.1, the Reel as a collection as 0.5.2), foundations &
safety net (0.6.0), the service /
TMDB proxy (0.7.0), accounts (0.8.0), the Daily Chain (0.9.0), friend groups (0.10.0);
share images ship with launch (1.0.0). Global leaderboards are dropped — **check the
changelog table before choosing a bump**. Each is documented in
[`docs/ROADMAP.md`](docs/ROADMAP.md) (scope, decisions to settle, known traps); read
the relevant section before starting one.

> Note: the visual design is **Cream Neobrutalist** as of 0.5.0 — no longer
> placeholder. How the chain is drawn is a **player setting** (Settings → Chain style):
> **Deck** (`ChainDeck.swift`, the default — a physical pile that fills the space above
> the keyboard), **Cards** (`ChainCards.swift`) and **Tiles** (`ChainStack.swift`). All
> three are kept on purpose; keep them working when touching the chain. The motion
> re-tune landed as 0.5.1. The recurring
> constraint is still vertical room against the docked keyboard. Vocabulary is fixed:
> a *chain* is a whole run, a *link* is one correct answer (the score counts links),
> the dealt start is not a link, and the best run is the most links with points
> breaking ties (`Scoring.isNewRecord`). Reuse `Theme` tokens and `Components` — never
> hardcode fonts, colours or sizes. See
> [`docs/ROADMAP.md`](docs/ROADMAP.md#050--design-overhaul).

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
  sed -i '' 's/MARKETING_VERSION = 0.5.2;/MARKETING_VERSION = 0.6.0;/g' \
    movie-quiz.xcodeproj/project.pbxproj
  git tag -a v0.6.0 -m "0.6.0"
  ```
  Bump **minor** when a roadmap milestone lands, **patch** for fixes/polish in
  between. Pre-1.0, breaking internal changes go in a minor bump.

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
  `nonisolated … async` without `@concurrent`, and a `Task` inside `onAppear`. A
  deliberate exception carries `// swift-check:ignore — <why>` on the line.
  - Runs after every Claude Code edit to a Swift file (`.claude/settings.json`
    PostToolUse hook) — a violation is reported back immediately; fix it.
  - Runs as a git pre-commit hook on staged Swift. **Enable it once per clone:**
    `git config core.hooksPath .githooks`
- **`/swift-review [base]`** — the judgment pass a script can't do (value vs reference,
  `some`/`any`, reentrancy, structure, test coverage). Run it on a branch before merging.

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
> the TMDB request-rate gate that constrains any acquisition push.

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
— a cast is never completable). No numbers on the fronts; the finish is the reward.
`ReelCards.swift` draws both. The Reel narrows by decade and genre (`ReelFilter`:
films match directly, actors through a linked film; genre ids ride along on every
TMDB movie response, names are a fixed table). An actor card's finish (paper / inked / holo) comes
from the pure, tested `ReelTier`, under a model set in Settings → Reel cards (Rank
default, Share, Plain) while they're compared. Share scales to a well-known-films
snapshot the engine takes from the filmography it already loads — **no extra TMDB
request; never add a fetch on Reel open**. Art streams via `AsyncImage` from
`Config.imageURL(path:)` (system-cached, never stored on disk; nil path →
monogram). The store is owned at the app root and injected into the engine.
`-uiDemoReel -uiOpenReel` (DEBUG) opens a demo Reel without touching the saved one.

**UI (NYT-Games / Connections treatment)** — `ContentView.swift` routes on
`engine.phase` between `SeedView`, `GameView`, and `GameOverView` with a
**direction-free forward carousel** (`.screenPush` on `Theme.Motion.screen`: the
app is a one-way loop, so every change pushes the new screen in from the trailing
edge — no "back"; Reduce Motion → cross-fade). It owns the
shared `CollectionStore` (opened as a `.sheet` from the seed and game-over
screens) and the persisted once-ever `seedIntroDone` flag driving `SeedView`'s
first-run cold-launch intro (the title lockup starts centered, the mini-chain drops in, then
it rises as the controls assemble). `SeedView` is **play-first**: it leads with a
*dealt start* — one ink **"Start with ⟨name⟩" button** (Play + seed fused; the
name auto-fits one line so Shuffle can deal it in/out on `.dealDrop` without
reflow) + a **Shuffle** button, with
search demoted to an opt-in link, a **gear pill** opening the `SettingsView`
sheet (sound), and **Your
Reel** shrunk to a corner pill (personal best folded into that sheet; the pill is
always reachable, count hidden when empty, because the Reel sheet hosts the
required **TMDB attribution**). Styling is a
small design-system layer: `Theme.swift` (color/spacing/radius/motion tokens +
per-node category identity — **blue = actor, yellow = movie**) and
`Components.swift` (`.neoSurface` = border + hard shadow, `PrimaryButtonStyle` = coral, `GhostButtonStyle`,
`PressScaleStyle` = `.pressScale` subtle press feedback, `.card()`,
`NodeTile`/`NodeDot`, plus juice pieces `Shake`/`FloatingGain`/`StaggeredAppear`
(`.appear(i)`)), all built on the
Cream Neobrutalist palette (0.5.0) defined in `Assets.xcassets`
(Canvas/Ink/Tile/Shadow/Hairline/Coral/ActorBlue/MovieYellow/Good/OnAccent, each
light+dark). The chain has three player-selectable styles (Settings → Chain style,
`ChainStyle`): **Deck** by default (`ChainDeck.swift`: every link is one card for its
whole life — a new one is dealt in from below and pushes the last back into a pile
that peeks out above it, sized to the room above the keyboard), **Cards**
(`ChainCards.swift`: a hero card for the newest link, compact cards for the two before
it) and **Tiles** (`ChainStack.swift`: a **rising Tetris-style stack of category
tiles** — a new link drops in and older ones collapse into "+N earlier"). The dealt
start wears a holographic sticker (`HoloSticker.swift`, gyro-lit foil) instead of a
number, as does a new best on game over. The play
screen docks the text input via `.safeAreaInset(.bottom)` above the
**always-present keyboard** (with `TimerBar.swift` as a slim linear countdown), and
swaps it for a **Retry** button if a candidate load failed
(`engine.awaitingRetry`); the full chain is revealed as a numbered recap at game over, its tiles
staggering in (`ChainStack(staggered:)`) and the score popping when the run set a
new best. App-wide
tint (ink) is set once in `movie_quizApp` (no rounded font — the look pairs the
system serif wordmark with the default sans). Prefer reusing these over hardcoded
values.

Remaining fan-out modes (the Daily Chain, friend groups, genre locks, memory-recall
every Nth link) all layer on this same engine — keep the engine/provider split clean.
Accounts arrive at 0.8.0 (Sign in with Apple over a device id); the local
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
