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
- Language: Swift 5.0, SwiftUI + Observation (`@Observable`), iOS 17+ APIs
- Builds with **MainActor-default isolation** (`SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`) — off-main-actor code must opt out explicitly (e.g. the
  `nonisolated` `Codable` values in `Collection.swift`; resolve `@MainActor`
  defaults in init bodies, not default arguments)
- Deployment target: iOS 26.2 (high — only installs on a 26.x runtime; lower it
  in build settings if broader device/simulator support is wanted)
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

# Run a single test (XCTest)
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:movie-quizTests/FuzzyMatchTests/testArabicSequelMatchesRomanTitle
```

Day-to-day development is normally done in Xcode (⌘B build, ⌘R run, ⌘U test). `#Preview` blocks
drive SwiftUI canvas previews.

## Architecture

> For the full module-by-module breakdown, game-loop diagram, and design
> rationale, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Keep that doc
> current when the architecture, providers, rules, or stack change; the summary
> below should stay lean.

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
and the `missedAnswer` near-miss. A session-level `difficulty` (fixed at
`startGame(with:difficulty:)`) selects **Hardcore** (type → `submit` → fuzzy match)
or **Assisted** (tap `currentOptions`, built each turn by the pure `Choices.build`
from the candidate set + cached pools; `select` accepts or docks time via
`applyWrongTapPenalty`). Both accept paths share a private `accept(_:)`. Records
split by difficulty — assisted runs write only `bestChainAssisted`/`bestPointsAssisted`,
never the hardcore best (`shareSummary` tags them; forward-compatible with split
leaderboards). The assisted correct answer must clear a **`Choices.FamiliarityGate`**
— top-billed leads on actor turns, a TMDB `voteCount` floor on movie turns — so an
assisted chain only ever *steps to* a node the player plausibly knows (the same
standard the seed deal applies at step 0, applied at every step; self-reinforcing,
and it relaxes rather than stalling at a dead end). This is what stops the walk
drifting into a film region the player can't recognize. Assisted runs are also
**never logged to the Reel** (it's a "how many you *know*" hook and the answer was
shown). `loadCandidates` **retries** transient fetch
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
tunables (`secondsPerTurn`, `seedActorBias`, `seedRecentWindow`, `optionCount`, `assistedWrongPenalty`, `assistMinVoteCount`, `assistTopBilled`, `seedMoviePoolPages`, `requestTimeout`, `candidateLoadAttempts`) and loads the TMDB credential at runtime from a
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
you". Pure count stats only (no rarity). Tiles stream art via `AsyncImage`
from `Config.imageURL(path:)` (system-cached, never stored on disk; nil path →
typographic placeholder), fed by the new `imagePath` on `Person`/`Movie`. The
store is owned at the app root and injected into the engine.

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
reflow) + a **Hardcore/Assisted `DifficultyToggle`** + a **Shuffle** button, with
search demoted to an opt-in link, a **gear pill** opening the new `SettingsView`
sheet (default difficulty + sound), and **Your
Reel** shrunk to a corner pill (personal best folded into that sheet; the pill is
always reachable, count hidden when empty, because the Reel sheet hosts the
required **TMDB attribution**). Styling is a
small design-system layer: `Theme.swift` (color/spacing/radius/motion tokens +
per-node category identity — **blue = actor, purple = movie**) and
`Components.swift` (`PrimaryButtonStyle` = ink pill, `GhostButtonStyle`,
`PressScaleStyle` = `.pressScale` subtle press feedback, `.card()`,
`NodeTile`/`NodeDot`, `DifficultyToggle`, plus juice pieces `Shake`/`FloatingGain`/`StaggeredAppear`
(`.appear(i)`)), all built on the
warm-paper palette defined in `Assets.xcassets` (Canvas/Ink/Tile/Hairline/
ActorBlue/MoviePurple/Good/OnAccent, each light+dark). The signature visual is
`ChainStack.swift`: the chain builds as a **rising Tetris-style stack of category
tiles** — a new link drops in and older ones collapse into "+N earlier". The play
screen's bottom band branches on difficulty: **Hardcore** docks the text input via
`.safeAreaInset(.bottom)` above the **always-present keyboard**, **Assisted** swaps
it for a keyboard-free panel of tappable option tiles (each with a `NodeThumbnail`
headshot/poster; with `TimerBar.swift` as a slim linear countdown either way); the full chain is revealed as a numbered recap at game over, its tiles
staggering in (`ChainStack(staggered:)`) and the score popping when the run set a
new best. App-wide
tint (ink) is set once in `movie_quizApp` (no rounded font — the look pairs the
system serif wordmark with the default sans). Prefer reusing these over hardcoded
values.

Remaining fan-out modes (genre locks, memory-recall every Nth link, leaderboards)
all layer on this same engine — keep the engine/provider split clean. Leaderboards
are the natural point to add accounts; the local collection/session data is
forward-compatible with a future sync.

## Running it

Build succeeds for the simulator. Because the deployment target is iOS 26.2, run
on a 26.x simulator runtime (e.g. iOS 26.4), not 18.x. In Xcode: pick an iOS 26+
simulator and ⌘R.
