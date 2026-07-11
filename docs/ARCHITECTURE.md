# Movie Chain — Architecture & Overview

> Detailed source-of-truth for the app's design. `CLAUDE.md` is the lean,
> auto-loaded summary; **this file is the deep reference** — point a chat here to
> get it up to speed, and keep it current when the code changes.

## What the app is

**Movie Chain** (`movie-quiz`) is a single-player recall game. You build a chain
that alternates **actor → movie → actor → movie …**, where every link must be
real: the actor actually appeared in the movie. Your score is the chain length,
and each turn is on a countdown — run out of time and the game ends.

- Bundle ID: `abe.movie-quiz`
- No autocomplete by design — you type from memory; spelling is forgiven, but
  the answer is not.

## Stack & platform

| | |
|---|---|
| Language | Swift 5.0 |
| UI | SwiftUI |
| State | Observation framework (`@Observable`, `@State`) |
| Concurrency | Swift structured concurrency (`async`/`await`, `Task`, `@MainActor`) |
| Min OS | iOS **26.2** deployment target (lower it in build settings for wider support) |
| Platforms | iOS, iPadOS, macOS, visionOS |
| Data | TMDB REST API (live) or a built-in stub graph (offline demo) |
| Project | `movie-quiz.xcodeproj` (project, not workspace); app target + `movie-quizTests` unit-test target, single shared scheme |
| File inclusion | `PBXFileSystemSynchronizedRootGroup` — drop `.swift` files under `movie-quiz/`, no `.pbxproj` edits |

## The core idea: bounded candidate sets

The whole design turns on one observation: **at every turn there is exactly one
small, known set of valid answers.**

- After a **movie**, the only valid answers are that movie's **cast**.
- After an **actor**, the only valid answers are that actor's **filmography**.

That bounded set is what makes two otherwise-hard problems easy:

1. **Validation** — checking a link is just membership in a ~10–50 item list, not
   a global graph query.
2. **Spelling tolerance** — because the target set is tiny and known, we can fuzzy
   match typed text against *only that set* with high tolerance and near-zero
   false positives. No global fuzzy search, no autocomplete that would spoil the
   recall challenge.

## Module map

All source is in [`movie-quiz/`](../movie-quiz/).

### Domain types — [`Models.swift`](../movie-quiz/Models.swift)
- `Person { id: Int, name, popularity? }` and `Movie { id: Int, title, year?,
  popularity? }` — `id` is the stable **TMDB id**, which is what makes validation
  and dedup exact (equality/hashing are **id-only**, so the same entity compares
  equal regardless of fetched metadata). `popularity` is optional TMDB popularity,
  used only for the obscurity scoring bonus (`nil` on the offline stub graph).
- `ChainNode` — enum `.actor(Person) | .movie(Movie)`, one link in the chain.
  - `id: String` → `"p<id>"` / `"m<id>"` (namespaced so actors and movies never
    collide in `usedIds`).
  - `displayName` (year-decorated for movies) vs `matchText` (bare title, what the
    player actually spells).
  - `nextKind` — actor→movie, movie→actor.
- `NodeKind { actor, movie }` — plus UI `prompt` / `placeholder` strings.

### Data abstraction — [`MovieDataProvider.swift`](../movie-quiz/MovieDataProvider.swift)
The engine knows **only this protocol**, never a concrete source:
```swift
searchActors(_:) / searchMovies(_:)   // global — seed node ONLY
cast(of:)                             // bounded set after a movie
filmography(of:)                      // bounded set after an actor
```
`DataProviderError` covers missing key / bad HTTP / decode failures.

`filmography(of:)` drops **self-appearance credits** (TMDB `character` of "Self",
incl. "Self - Host" etc.) — making-of featurettes, talk-show and documentary
appearances are not film roles and must not be valid chain links (e.g. Jack
Black's "Making of School of Rock" was being accepted for a typed "School of
Rock").

- [`TMDBProvider.swift`](../movie-quiz/TMDBProvider.swift) — live over
  `https://api.themoviedb.org/3`. Supports both v4 Bearer tokens and v3 `api_key`
  query auth (`Config.usesBearerToken`). Private `Decodable` DTOs map TMDB JSON to
  the domain types. Seed search results are **sorted by TMDB `popularity`** so the
  canonical record leads: TMDB returns a canonical record *plus* near-empty stubs
  sharing the same name (two "Tom Cruise" entries — one with 94 credits, one with
  1), and seeding on a stub would reject films the actor was really in. Identity is
  the **TMDB id, never the name**, so same-name records are *not* collapsed
  (legitimate homonyms must stay selectable); only records with **no evidence of
  being real** — zero popularity *and* no `known_for` — are dropped.
- [`StubProvider.swift`](../movie-quiz/StubProvider.swift) — a small, deliberately
  connected hardcoded movie/cast graph so the game is fully playable with **no
  network or key**. Person ids are derived deterministically from names so the
  same actor resolves consistently across queries.

### Matching — [`FuzzyMatch.swift`](../movie-quiz/FuzzyMatch.swift)
Pure, stateless. `bestMatch(for:in:nameOf:threshold:)` returns the best candidate
clearing a threshold (default **0.72**), else `nil`.
- `normalize` — diacritic-fold, case-fold, elide apostrophes, punctuation→space,
  canonicalize Roman-numeral tokens to Arabic digits, collapse whitespace
  (`"Jóhn  Malkóvich!"` → `"john malkovich"`, `"Mission: Impossible III"` →
  `"mission impossible 3"`). The Roman→Arabic step fixes sequel matching: TMDB
  titles sequels in Roman while players type Arabic, and character-level edit
  distance otherwise treats `"3"` as closer to `"ii"` (2 edits) than `"iii"` (3),
  so `"mission impossible 3"` used to resolve to *Mission: Impossible II*. Folding
  both sides to a digit is validated by round-trip, so non-sequel single letters
  ("Malcolm X", "X-Men", "I Am Legend") still match themselves.
- Base score = Levenshtein similarity in `[0,1]`, then three boosts:
  1. all typed words are whole words in the name **and** ≥1 is a "content word"
     (≥4 chars, so stopwords like "the" can't carry it) → 0.9
  2. a single ≥4-char query word is a prefix of a name word ("malkov"→"malkovich")
     → 0.82
  3. typed text fully contains the candidate name ("the movie inception") → 0.85
- **Tie-break on the raw score.** The boosts are flat floors, so two candidates
  can hit the *same* boosted score (e.g. "school of rock" is a whole-word subset
  of both "The School of Rock" and "Making of School of Rock" → both 0.9). When
  boosted scores tie, the higher *raw* Levenshtein similarity wins (the title with
  fewer extra words), so the result never depends on candidate order.

### Scoring & feedback (the gamification layer)
The engine stays pure; all "juice" is layered on top and fired from the **view**
in reaction to engine state (never from the engine — that keeps it UIKit-free and
testable).
- [`Scoring.swift`](../movie-quiz/Scoring.swift) — pure, stateless, unit-tested.
  `score` (chain length) is the headline metric; `points` is a richer secondary
  score = `base + speedBonus(secondsRemaining) + obscurityBonus(popularity)`.
  `flameTier(links:)` still exists and is unit-tested, but the current
  Connections-treatment UI no longer renders a flame (kept as a tuned rule for
  potential reuse). Mirrors `FuzzyMatch`/`ActorRanking`: pure rules in their own
  type so balance can be tuned under test.
- **Share card** — `GameEngine.shareSummary` (pure `String`) renders the finished
  run as a spoiler-free Connections-style card: score/points + a 🟦🟪 square chain
  (🟦 actor, 🟪 movie), fed to a SwiftUI `ShareLink` at game over.
- [`Haptics.swift`](../movie-quiz/Haptics.swift) — UIKit feedback wrapper
  (`correct(streak:)` ramps intensity with the chain, `wrong()`, `celebrate()`);
  `#if os(iOS)` no-op elsewhere.
- [`Sound.swift`](../movie-quiz/Sound.swift) — `SoundPlayer` synthesises short
  sine tones via `AVAudioEngine` (no bundled assets); a correct link chimes a note
  cycled through a pentatonic scale *within one octave* — it varies link-to-link
  but deliberately does **not** climb ever higher (an unbounded rise read as shrill
  and annoying on long chains). `.ambient` session so it mixes and honours the
  silent switch. Toggled by `@AppStorage("soundEnabled")`.

### Game engine — [`GameEngine.swift`](../movie-quiz/GameEngine.swift)
`@MainActor @Observable final class` — owns **all** game state; UI is a pure
function of it.

- **State:** `phase` (`.seed`/`.playing`/`.gameOver`), `chain: [ChainNode]`,
  `score` (chain length), `points`, `lastGain`/`lastAnswerFast` (for the "+N"
  flourish), `secondsRemaining`, `expectedKind`, transient `feedback`, `isChecking`.
- **Records & recap:** `bestChain`/`bestPoints` (persisted via `UserDefaults`),
  `isNewBest` (celebration trigger), `missedAnswer` (a valid answer left ungiven on
  the turn that timed out — the "you were one away" near-miss, captured in
  `endGame()` from the still-loaded `candidates`; `nil` on a manual quit), and
  `endedByQuit` (so the summary shows "Chain ended" rather than "Time's up").
- **Private:** injected `provider`, current `candidates`, `usedIds: Set<String>`
  (no-repeat rule), the `countdownTask`, and a monotonic `generation` token that
  guards async candidate loads (see below).
- **Flow:** `search` (seed only) → `startGame(with:)` → `submit(_:)` per turn →
  `reset()`. `loadCandidates(for:)` refreshes the bounded set after each accepted
  link. `quit()` ends the run in place — it routes through `endGame()` to the
  game-over summary (committing records) rather than resetting to the seed picker.
- **Timer correctness:** the countdown is a cancellable `Task`. `submit` **stops
  the clock during the candidate fetch** so a slow network load can't fire
  game-over on an answer that was submitted in time, and re-checks `phase ==
  .playing` after every `await` in case `reset()` ran mid-flight.
- **Stale-load safety (`generation`):** every lifecycle transition
  (`startGame` / `endGame` / `reset`, the latter two covering timeout **and**
  quit) bumps a monotonic `generation` token. `loadCandidates` captures it before
  awaiting the provider and **drops its result if the token has moved on** — so a
  slow fetch from an abandoned/quit game can't resume later and install the
  previous node's cast/filmography into a *new* round. The `phase == .playing`
  guard alone can't catch this, because the new game is also `.playing`. Regression-
  tested in `GameEngineTests` with a provider that holds the first fetch open while
  a new game starts.
- **Rejections** (don't advance): off-list answer, or an id already in `usedIds`.

### Design system — [`Theme.swift`](../movie-quiz/Theme.swift) + [`Components.swift`](../movie-quiz/Components.swift)
An **editorial, puzzle-page treatment** (NYT Games / Connections): paper-warm
neutrals, near-black ink, and two "category" accents — **blue for actors, purple
for movies** — used the way Connections uses its group colors. A serif wordmark +
system sans carry the type; there is no flame, confetti, or radial-heat.
- **Color** lives in `Assets.xcassets` as named sets with light+dark variants —
  `Canvas`, `Ink`, `Tile` (warm grey surface), `Hairline`, `ActorBlue`,
  `MoviePurple`, `Good` (correct-link green), and `OnAccent` (near-black text that
  stays legible on the pastels in *both* themes). `Theme.Color` just names them;
  muted text still uses Apple's semantic `.secondary`/`.tertiary`.
- `Theme` — token namespaces: `Color`, `Spacing`, `Radius`, `Motion` (incl.
  `drop`, the spring a new tile lands on). Views reference these, never literals.
- `NodeKind` / `ChainNode` extensions give each kind one `accent` (blue/purple),
  a `tileLabel` ("ACTOR"/"MOVIE"), and a `symbol`, eliminating color/label logic
  that was duplicated across views.
- `Components.swift` — owned, reusable primitives (the app's shadcn-equivalent):
  `PrimaryButtonStyle` (`.buttonStyle(.primary)`, an ink-filled pill),
  `GhostButtonStyle` (`.ghost`, outlined), `CardModifier` (`.card()`), `NodeTile`
  (the Connections category tile — the atom of the chain), `NodeDot` (small
  category chip), plus the juice pieces `Shake` (`.shake(trigger)` for a rejected
  answer) and `FloatingGain` (the rising "+N").
- Feature components in their own files: [`ChainStack.swift`](../movie-quiz/ChainStack.swift)
  is the signature visual — the chain as a **rising Tetris-style stack of category
  tiles**: each accepted link drops in from the top and the column builds; in the
  play window older links collapse into "+N earlier" to fit the band above the
  keyboard, while the game-over recap shows the whole chain numbered.
  [`TimerBar.swift`](../movie-quiz/TimerBar.swift) is the slim linear countdown
  (drains in ink, shifts to a warning red in the final quarter).
- App-wide `.tint(.accentColor)` (ink) is applied once at the root in
  `movie_quizApp`; **no `.fontDesign`** — the look pairs the system serif (wordmark,
  game-over number) with the default sans for UI. The accent is defined for
  light/dark in `Assets.xcassets/AccentColor` (near-black / off-white).

### UI — SwiftUI, routed by phase
- [`movie_quizApp.swift`](../movie-quiz/movie_quizApp.swift) — `@main` entry.
- [`ContentView.swift`](../movie-quiz/ContentView.swift) — owns the single
  `@State GameEngine` and switches `SeedView` / `GameView` / `GameOverView` on
  `engine.phase` (animated with `.snappy`).
- [`SeedView.swift`](../movie-quiz/SeedView.swift) — the branded, **play-first**
  start screen: an ambient mini-chain lockup + **serif wordmark**, a best-chain
  badge, two big **Actor / Movie category choice tiles** (the selected one ringed)
  that set the mode and focus the search, an in-app-styled search field (debounced),
  and warm-tile result rows with a category dot. Built on the shared design system
  over a plain canvas, rather than a stock `NavigationStack`/`List`/`.searchable`,
  which read as an iOS-Settings screen.
- [`GameView.swift`](../movie-quiz/GameView.swift) — the turn, laid out around the
  **always-present software keyboard** (the dominant constraint of a typing game):
  compact chrome (sound · seconds · quit) + `TimerBar` up top, a centered **serif
  score hero** (chain number + points) filling the band above the rising
  `ChainStack`, a "Name a movie X was in" hint, and the answer input **docked via
  `.safeAreaInset(.bottom)`** directly above the keys (auto-focused; the keyboard's
  Go submits). Reacts to `engine.score` / `engine.feedback` to fire haptics, sound,
  the "+N" pop and the shake.
- [`GameOverView.swift`](../movie-quiz/GameOverView.swift) — final score (serif) +
  points, a quiet "a new best" mark (a serif-italic green pill, no confetti), the
  **Personal best fenced between hairlines** so it never reads as this run, the
  "you were one away" near-miss, the full chain revealed as a numbered `ChainStack`
  recap, and **Play again** + **Share** (the 🟦🟪 card).

### Config & secrets — [`Config.swift`](../movie-quiz/Config.swift)
- `secondsPerTurn = 30` and other tunables.
- `makeProvider()` → `TMDBProvider` when a token is present, else `StubProvider`.
- Token is loaded **at runtime** from a gitignored
  `movie-quiz/TMDBSecrets.plist` (key `TMDBToken`, optional `UsesBearerToken`).
  Copy `TMDBSecrets.example.plist` to set one up. **Never commit the token.**

## Game loop at a glance

```
SeedView            GameView (repeats)                       GameOverView
─────────           ─────────────────────────────           ────────────
pick seed  ──▶  candidates = cast/filmography of last node
                        │
                player types answer
                        │
                FuzzyMatch.bestMatch(in: candidates)
                   ├─ no match ......... feedback, stay
                   ├─ already used ..... feedback, stay
                   └─ match ─▶ append, score++, load next
                                candidates, restart timer
                        │
                timer hits 0 ─────────────────────────▶  phase = .gameOver
```

## Key design decisions (the "why")

- **Engine / provider / UI are fully decoupled.** The engine depends on the
  `MovieDataProvider` protocol only, so the stub and TMDB are drop-in swappable
  and the engine is unit-testable without a network.
- **Everything resolves to a stable TMDB id.** Validation and the no-repeat rule
  are exact id comparisons, never string comparisons.
- **Fuzzy matching is scoped to the bounded set, not global.** This is what lets
  misspellings resolve without false positives and without an autocomplete that
  would spoil the game.
- **The clock pauses across network fetches.** Prevents a slow load from
  wrongly ending a game on a timely answer.

## Extending it

Planned fan-out modes — genre locks, memory-recall every Nth link, leaderboards —
all layer on this same engine. The rule of thumb: **keep the engine/provider
split clean.** New rules live in `GameEngine`; new data sources implement
`MovieDataProvider`; new screens read engine state and call engine methods.

## Dev workflow

- Day to day: Xcode — ⌘B build, ⌘R run, ⌘U test. `#Preview` blocks drive canvas.
- Run on an **iOS 26.x** simulator (the deployment target is 26.2), not 18.x.
- Command line (see `CLAUDE.md` for full `xcodebuild` invocations):
  ```bash
  xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
    -destination 'platform=iOS Simulator,name=iPhone 16' build
  ```
- **Unit tests** live in [`movie-quizTests/`](../movie-quizTests/) (target
  `movie-quizTests`, `@testable import movie_quiz`): `FuzzyMatchTests` locks the
  matcher (incl. the Roman→Arabic sequel fix), `ActorRankingTests` locks
  `ActorRanking.rank` (canonical-first, homonyms preserved, stubs dropped),
  `ScoringTests` locks the point math + flame-tier thresholds, and
  `GameEngineTests` locks the stale-load safety with a gated stub provider. Run
  with ⌘U or the `xcodebuild … test` invocation above.

---

*Keeping this current: when the architecture, a provider, the game rules, or the
stack changes, update this file. It is the detailed doc that `CLAUDE.md` points
to.*
