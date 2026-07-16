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
| Concurrency | Swift structured concurrency (`async`/`await`, `Task`, `@MainActor`); builds with **MainActor-default isolation** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| Min OS | iOS **26.2** deployment target (lower it in build settings for wider support) |
| Platforms | iOS, iPadOS, macOS, visionOS |
| Data | TMDB REST API (live) or a built-in stub graph (offline demo) |
| Project | `movie-quiz.xcodeproj` (project, not workspace); app target + `movie-quizTests` unit-test target, single shared scheme |
| File inclusion | `PBXFileSystemSynchronizedRootGroup` — drop `.swift` files under `movie-quiz/`, no `.pbxproj` edits |

> **MainActor-default isolation shapes new code.** Because everything is
> implicitly `@MainActor`, code that must run off the main actor opts *out*
> explicitly: `CollectedEntity`/`CollectionSnapshot` are marked `nonisolated` so
> their `Codable` conformances can encode on the background save queue, and
> `GameEngine.init` resolves `Config.makeProvider()` in its body rather than as a
> default argument (default arguments evaluate in a nonisolated context). Keep
> this in mind for any new background work or `Sendable`/`Codable` value types.

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
- `Person { id: Int, name, popularity?, imagePath? }` and `Movie { id: Int, title,
  year?, popularity?, imagePath? }` — `id` is the stable **TMDB id**, which is what
  makes validation and dedup exact (equality/hashing are **id-only**, so the same
  entity compares equal regardless of fetched metadata). `popularity` is optional
  TMDB popularity, used only for the obscurity scoring bonus (`nil` on the offline
  stub graph). `imagePath` is the TMDB `profile_path`/`poster_path` (nil-safe), used
  to render the collection grid; `nil` → typographic placeholder tile.
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
searchActors(_:) / searchMovies(_:)   // global — seed SEARCH (opt-in "pick your own")
popularActors() / popularMovies()     // popularity pool — the home-screen DEAL
cast(of:)                             // bounded set after a movie
filmography(of:)                      // bounded set after an actor
```
`DataProviderError` covers missing key / bad HTTP / decode failures.

`popularActors`/`popularMovies` back the home screen's *dealt start* (see
`SeedDeal` and `SeedView` below), and are tuned for **recognizability**, not
recency. TMDB's `*/popular` endpoints are a *trending-right-now* metric that
surfaces viral-but-obscure titles and unfamiliar (often international/TV) people;
Letterboxd's "popular" instead reflects member watch activity, which we can't
access (their API is partner-only). So we approximate "most-*watched* of all time"
with the closest public signal — **vote count**:
- **Movies** come from `discover/movie?sort_by=vote_count.desc` (the most-rated
  films ≈ the most widely seen), two pages (~40).
- **Actors** have no all-time endpoint, so the pool is **derived from the casts of
  the most-watched films**: the top-billed few (`Config.seedTopBilledPerMovie`) of
  the top `Config.seedActorSourceMovies` titles, deduped by id (highest popularity
  wins), most-popular first. The leads of the films everyone's seen *are* the
  recognizable actors, and the actor/movie pools stay consistent.

The cast fetches run **concurrently** (`withThrowingTaskGroup`) so the whole pool
resolves in well under a second — it loads from `SeedView`'s `.task` on the first
frame, overlapping the cold-launch intro, and is cached for the session
(`poolLoaded`) so shuffles/resumes are instant. The stub deals from its whole
hand-picked graph.

> **JSON decode runs off the main actor.** `TMDBProvider` is MainActor-isolated
> (project default), so a naive `JSONDecoder().decode` parses on the main thread.
> That was invisible for one-at-a-time fetches but became a real hitch once the
> deal fired ~18 concurrent cast decodes and popular seeds carried 100+ credit
> filmographies — the decode stuttered the seed→play transition. `fetch` now routes
> decoding through a `nonisolated static func decode(...) async` helper (runs on the
> cooperative pool, off main), and the private DTOs are `nonisolated` so their
> `Decodable` conformance isn't MainActor-bound (same pattern as `Collection.swift`).

The TMDB implementation of `filmography(of:)` drops **self-appearance credits**
(TMDB `character` of "Self", incl. "Self - Host" etc.) — making-of featurettes,
talk-show and documentary appearances are not film roles and must not be valid
chain links (e.g. Jack Black's "Making of School of Rock" was being accepted for
a typed "School of Rock"). Note this lives in `TMDBProvider`, not the protocol —
a new provider must apply the same rule itself (the stub graph simply has no
such credits).

- [`TMDBProvider.swift`](../movie-quiz/TMDBProvider.swift) — live over
  `https://api.themoviedb.org/3`. Supports both v4 Bearer tokens and v3 `api_key`
  query auth (`Config.usesBearerToken`). Private `Decodable` DTOs map TMDB JSON to
  the domain types. Seed search results are **sorted by TMDB `popularity`** so the
  canonical record leads — the rule is `ActorRanking.rank`, a pure type that lives
  in this same file (extracted so it's unit-testable without a live round-trip):
  TMDB returns a canonical record *plus* near-empty stubs
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

### Seed deal — [`SeedDeal.swift`](../movie-quiz/SeedDeal.swift)
Pure, stateless (same family as `FuzzyMatch`/`ActorRanking`/`Scoring`), so the
home-screen deal policy is unit-tested with a seeded RNG — no network.
`pick(actors:movies:recentIds:actorBias:using:)` deals a *fresh, familiar* start:
- **familiar** is the caller's job (it passes the popularity pools);
- **fresh** is this type's job — it avoids `ChainNode.id`s in `recentIds` (falling
  back to the full pool for a kind if *all* of it is recent, so a tiny pool never
  deals nothing), and mixes actors/movies by `actorBias` (falling back to the
  other kind if the chosen pool is empty). Returns `nil` only if both pools are
  empty. Tunables live in `Config` (`seedActorBias = 0.6`, `seedRecentWindow = 8`).

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
  (`correct(streak:)` ramps intensity with the chain, `wrong()`, `celebrate()`,
  `selection()` — the detent tick for the seed actor/movie toggle);
  `#if os(iOS)` no-op elsewhere. Generators are long-lived and **pre-warmed**:
  `Haptics.prepare()` + `SoundPlayer.warm()` are fired from `SeedView`'s
  `warmFeedbackWhenIdle()` — on the **home screen, once its entrance animation has
  settled**, not from `GameView`. `AVAudioEngine.start()` (and the audio-session
  activation) briefly **block the main actor**, and firing them from `GameView`'s
  `.task` landed that block right on the seed→play push, hitching the transition.
  Warming on the idle seed screen keeps the cost off every animation; `GameView`'s
  `.task` now only raises the keyboard, and only *after* the push settles (a focus
  set mid-push triggers keyboard-driven safe-area relayout that fights the spring).
  If a player somehow plays before the warm fires, `SoundPlayer.play`'s lazy
  `startIfNeeded` is the safety net (first chime just pays the latency once).
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
  `endGame()` from the still-loaded `candidates`; `nil` on a manual quit),
  `endedByQuit` (so the summary shows "Chain ended" rather than "Time's up"), and
  `reelAdditions` (how many brand-new entities this run added to the collection —
  the "+N to your Reel" figure).
- **Collection recording:** in `endGame()`, when `chain.count >= 2`, the run is
  logged into the injected `CollectionStore` (see below). The `>= 2` guard is the
  whole logging rule: it means at least one link validated, so the seed (chain[0])
  counts only once a real combination lands off it, and a seed-then-quit logs
  nothing.
- **Private:** injected `provider`, current `candidates`, `usedIds: Set<String>`
  (no-repeat rule), the `countdownTask`, and a monotonic `generation` token that
  guards async candidate loads (see below).
- **Seed deal:** the home screen leads with a *dealt* start, not a search. The
  engine caches the popularity pools (`popularActors`/`popularMovies`, loaded
  once), owns the `dealtSeed: ChainNode?` the home renders, and keeps a bounded
  `recentSeedIds` ring buffer. `prepareSeeds()` (called from `SeedView`'s `.task`
  on every appearance) loads the pool then deals; `shuffleSeed()` deals on demand
  (Shuffle button); `dealFreshOnResume()` re-deals when the app returns from the
  background on the home screen (`ContentView` scenePhase). All route through the
  private `deal()`, which delegates the *policy* to the pure `SeedDeal.pick` and
  only owns the pool cache + recent buffer. Search (`search`) remains as the
  opt-in "pick your own start" path.
  - **Pool-load robustness (per-side):** the actor and movie pools track load
    state *independently* (`actorsLoaded` / `moviesLoaded`; `poolReady` = either,
    `poolComplete` = both). `loadSeedPoolsIfNeeded` fetches only the side(s) not
    yet loaded, concurrently, and marks a side loaded **only when it returns
    entries** — an empty result (a failed/rate-limited fetch, incl. the
    derived-actor task group swallowing per-cast failures) leaves that side
    unloaded so it **retries**, rather than caching a partial *movie-only* pool for
    the whole session (the derive-from-casts pool is exactly what a shared-key rate
    limit throttles first — see `Config.makeProvider`'s TODO). A *cancelled* load
    (leaving the seed screen) commits nothing. `prepareSeeds` retries with backoff
    until both sides land; `shuffleSeed`/`dealFreshOnResume` deal from whatever's
    ready and quietly refill a missing side in the background.
- **Flow:** `prepareSeeds`/`shuffleSeed` (deal the seed) → `startGame(with:)` →
  `submit(_:)` per turn → `reset()`. `loadCandidates(for:)` refreshes the bounded
  set after each accepted link. `quit()` ends the run in place — it routes through
  `endGame()` to the game-over summary (committing records) rather than resetting
  to the seed picker.
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

### Collection / "Your Reel" — [`Collection.swift`](../movie-quiz/Collection.swift) + [`CollectionView.swift`](../movie-quiz/CollectionView.swift)
The registry of every actor/movie the player has logged through play — a
"Pokédex" retention hook ("look how many you know"). Follows the same
pure-value + observable-store split as the rest of the app:
- `CollectedEntity` — a pure `Codable` value (`kind`, `tmdbID`, `name`, `year`,
  `imagePath`, `firstSeen`/`lastSeen`, `timesLogged`). `id` matches
  `ChainNode.id` (`"p<id>"`/`"m<id>"`) so keys line up with the game's no-repeat
  ids. Unit-tested with no container.
- `CollectionStore` (`@MainActor @Observable`) — owns `[String: CollectedEntity]`
  + a `chainsLogged` counter, persisted as a JSON `CollectionSnapshot` in
  Application Support (**not** SwiftData — the data is a small bounded dictionary,
  matching the engine's lightweight `UserDefaults` records). Writes go through a
  **serial** `DispatchQueue`, so calls (always from the main actor, hence already
  ordered by mutation) land FIFO and the newest snapshot always wins — an older
  in-flight write can't clobber a newer one. `flush()` drains the queue and is
  called from `ContentView`'s `scenePhase` hook so the latest snapshot is
  guaranteed on disk before the app is suspended/killed. Exposes the rollups the view reads: `actorCount`/`movieCount`/`total`,
  `sortedActors`/`sortedMovies` (most-logged first), `mostLoggedActor`/`Movie`,
  `addedThisWeek`, and `newThisSession` (the "New" badge). Injected into the
  engine and shared from the app root.
- **The one logging rule** lives in `record(chain:)`: every node upserted once
  (so `timesLogged` counts distinct chains, never submissions), deduped by id,
  returning the count of brand-new additions. Called only from `endGame()` on
  chains of length ≥ 2 — see the engine's "Collection recording" note for why
  that single condition encodes "successful combinations only; seeds count once a
  link lands; nothing logged on a bare seed".
- `CollectionView` — the grid screen, presented as a `.sheet` from `SeedView`
  (a top-trailing corner pill) and `GameOverView` ("+N new to your Reel"). Takes
  `bestChain:` and shows **personal best** here (a trophy line under the category
  split) now that it's off the home hero — this is where "best + Reel live in one
  place." Pure count stats (no rarity/obscurity): a hero total + blue/purple
  category split, "your regulars" (most-logged), a filter, and the tile grid. Also
  hosts the **`TMDBAttribution`** view (TMDB logo + the required non-endorsement
  disclaimer) in both its populated and empty states — TMDB's API terms require
  in-app attribution. Because of that, the seed-screen Reel pill is shown
  **regardless of `collection.total`** (count hidden when 0): a first-run player is
  already being served TMDB-powered dealt seeds, so the attribution must be
  reachable before any chain is logged — gating the pill on `total > 0` hid it. Tiles stream art via `AsyncImage` from
  `Config.imageURL(path:)` (system-cached, never stored on disk); no path → the
  category-tinted typographic placeholder. Motion polish: art **fades in** as it
  streams (the phase-based `AsyncImage(transaction:)`), the hero numbers **roll up
  from 0** on appear (`numericText` gated by `statsIn`), the Actors/Movies filter
  **cross-fades** (`.id(filter)` + `.transition(.opacity)`) instead of reflowing
  in place, and grid tiles **stagger in** via `.appear(i)` — all off under Reduce
  Motion.

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
  `drop`, the spring a new tile lands on; `screen`, the soft spring the
  screen-to-screen carousel rides; `intro`, the seed cold-launch reveal; and
  `cascade`, the springy wave a staggered group of siblings rises in on).
  Views reference these, never literals. `AnyTransition.screenPush(reduceMotion:)`
  (also here) is the router's directional page push — see the UI section.
- `NodeKind` / `ChainNode` extensions give each kind one `accent` (blue/purple),
  a `tileLabel` ("ACTOR"/"MOVIE"), and a `symbol`, eliminating color/label logic
  that was duplicated across views.
- `Components.swift` — owned, reusable primitives (the app's shadcn-equivalent):
  `PrimaryButtonStyle` (`.buttonStyle(.primary)`, an ink-filled pill),
  `GhostButtonStyle` (`.ghost`, outlined), `CardModifier` (`.card()`), `NodeTile`
  (the Connections category tile — the atom of the chain), `NodeDot` (small
  category chip), plus the juice pieces `Shake` (`.shake(trigger)` for a rejected
  answer), `FloatingGain` (the rising "+N"), and `StaggeredAppear` (`.appear(i)` —
  fades + lifts a view in on appear, delayed by its position, so a group of
  siblings assembles one-after-another; drives both the seed intro's control
  reveal and the Reel grid tiles from one place, and honors Reduce Motion). Its
  `enabled:` flag keeps the stagger for a first-run reveal but skips it on
  ordinary re-insertions — the seed controls stagger during the cold-launch intro
  yet arrive **solid** on a "Play again" re-entry, so they don't run their own
  motion *while the carousel is already pushing the screen in* (that clash read as
  whiplash).
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
- **App icon** (`Assets.xcassets/AppIcon.appiconset/icon-1024.png`) distills the
  `ChainStack`/lockup identity: a bold zigzag stack of alternating actor-blue /
  movie-purple rounded tiles on ink. Rendered from the same palette via a
  CoreGraphics script (kept in the scratchpad, not the repo — regenerate if the
  mark changes); a single 1024 universal iOS entry. The bitmap is **opaque
  (no alpha channel)** — iOS app icons with alpha are rejected at archive/upload —
  so the render uses a `noneSkipLast` context; verify with `sips -g hasAlpha`.

### UI — SwiftUI, routed by phase
- [`movie_quizApp.swift`](../movie-quiz/movie_quizApp.swift) — `@main` entry.
- [`ContentView.swift`](../movie-quiz/ContentView.swift) — owns the single
  `@State GameEngine` **and the shared `@State CollectionStore`** (injected into
  the engine so it can record, and passed to the screens that display it), and
  switches `SeedView` / `GameView` / `GameOverView` on `engine.phase` with a
  **direction-free forward carousel**: the app is a one-way loop (seed → playing →
  gameOver → *play again* → seed), so every change is a forward push on one
  horizontal axis via `.transition(.screenPush(reduceMotion:))` on
  `Theme.Motion.screen` — new screen in from the trailing edge, old out to the
  leading edge; no "back" (Play again is the next lap, not a retreat). Reduce
  Motion degrades it to a cross-fade. `ContentView` also owns `seedIntroDone`, the
  persisted (`@AppStorage`) once-ever flag for the seed intro (below) — kept here,
  above `SeedView` (recreated on each `.seed` re-entry), so every launch after the
  first, and every Play-again re-entry, correctly starts assembled.
- [`SeedView.swift`](../movie-quiz/SeedView.swift) — the branded, **play-first**
  home that leads with a **dealt start**, not a search box (that's what made it
  read as a movie-logging app). Layout: the mini-chain lockup + **serif wordmark**
  + tagline hero, then the signature control — a single ink **"Start with ·
  ⟨name⟩" button** (Play and the seed fused into one; the dealt seed is a category
  dot + name, blue = actor / purple = movie) that starts the round on tap — a
  **"→ Name a movie they were in" hint** (reuses `NodeKind.prompt`), and a
  **Shuffle** ghost button. A quiet **"or search for your own start"** link drops
  down to the (now demoted) search flow, and **Your Reel** shrinks to a single
  top-trailing corner pill (shown once the player has logged art; personal best
  folded into that sheet via `CollectionView(bestChain:)`, off the hero).
  - **The deal** is owned by the engine (`engine.dealtSeed`, dealt on every
    appearance and on resume — see the engine's "Seed deal" note). The name lives
    on **one line, auto-sized to fit** (`lineLimit(1)` + `minimumScaleFactor`, like
    the in-game `NodeTile`) so the button never reflows — which is what lets
    Shuffle animate as one clean **deal** (`AnyTransition.dealDrop`: old start
    drops out downward, new drops in from above on `Theme.Motion.drop`, keyed by
    `.id(seed.id)`) instead of a janky slot-machine roll that changed height. The
    hint crossfades (`contentTransition(.opacity)`); Reduce Motion → plain swap.
    The button chrome ("START WITH") and frame stay fixed while only the inner
    seed content deals in/out, so the button itself never jumps. Disabled with a
    "Dealing…" placeholder until the first deal lands (pool still loading).
  - **Search flow** (`searching` state, behind the link) reuses the prior pieces —
    the Actor/Movie **segment**, the in-app-styled debounced field (auto-focused
    on open), and warm-tile result rows — with a "‹ Deal a start" back affordance.
    It's the flexible region (`maxHeight: .infinity`) so keyboard avoidance shrinks
    it and the field stays clear of the keys. iPhone is **portrait** (project
    setting); iPad keeps all orientations.
  - **Cold-launch intro** (once ever): the lockup starts centered (an animatable
    top spacer), its mini-chain drops in tile-by-tile via `TileBuild`, then on
    `Theme.Motion.intro` the lockup rises to its header rest and the deal controls
    (start button → hint → shuffle → search link) assemble beneath it via the
    `ControlReveal` cascade. Gated by the `introDone` binding from `ContentView` —
    a Play-again re-entry starts fully assembled. Reduce Motion shows it at once,
    and a full-screen tap catcher lets a tap **skip to the assembled screen** (the
    controls are inert until assembly, so the catcher never eats a real tap).
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
  "you were one away" near-miss, **a "+N new to your Reel" line that opens the
  collection sheet**, the full chain revealed as a numbered `ChainStack`
  recap, and **Play again** + **Share** (the 🟦🟪 card).

### Config & secrets — [`Config.swift`](../movie-quiz/Config.swift)
- `secondsPerTurn = 30` and other tunables.
- `imageBaseURL` + `imageURL(path:size:)` — builds a TMDB image URL from a stored
  `profile_path`/`poster_path` for the collection grid (nil path → nil → placeholder).
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

The collection ("Your Reel") is the first fan-out built on top of the loop —
a local, login-free registry that layers on the engine without touching the
engine/provider split (it's just another observable store the engine records
into at game over). Still planned: genre locks, memory-recall every Nth link,
and leaderboards (the natural point to add accounts — local session/collection
data is forward-compatible with a future sync). The rule of thumb: **keep the
engine/provider split clean.** New rules live in `GameEngine`; new data sources
implement `MovieDataProvider`; new screens read observable state and call methods.

## Dev workflow

- Day to day: Xcode — ⌘B build, ⌘R run, ⌘U test. `#Preview` blocks drive canvas.
- Run on an **iOS 26.x** simulator (the deployment target is 26.2), not 18.x.
- **QA shortcuts (DEBUG only):** launch with `-uiDemoChain` to jump straight into
  a mid-game `playing` state with a sample chain, or `-uiDemoGameOver` for the
  game-over summary — no typing required to inspect those screens. Wired in
  `ContentView.onAppear` to `GameEngine.loadDemoChain()`/`loadDemoGameOver()`
  (also used by the `#Preview`s); compiled out of release builds.
- Command line (see `CLAUDE.md` for full `xcodebuild` invocations):
  ```bash
  xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
    -destination 'platform=iOS Simulator,name=iPhone 16' build
  ```
- **Unit tests** live in [`movie-quizTests/`](../movie-quizTests/) (target
  `movie-quizTests`, `@testable import movie_quiz`): `FuzzyMatchTests` locks the
  matcher (incl. the Roman→Arabic sequel fix), `ActorRankingTests` locks
  `ActorRanking.rank` (canonical-first, homonyms preserved, stubs dropped),
  `ScoringTests` locks the point math + flame-tier thresholds,
  `GameEngineTests` locks the stale-load safety with a gated stub provider (and
  the per-side seed-pool retry: a failed/empty side isn't cached as loaded and is
  retried, a loaded side isn't re-fetched),
  `CollectionStoreTests` locks the "Your Reel" logging rule (length ≥ 2, seed
  counted once a link lands, dedup by id, `timesLogged` per-chain), and
  `SeedDealTests` locks the home-screen deal policy (actor/movie bias, recent-id
  avoidance with full-pool fallback, other-kind fallback, empty→nil). Run with ⌘U
  or the `xcodebuild … test` invocation above.

---

*Keeping this current: when the architecture, a provider, the game rules, or the
stack changes, update this file. It is the detailed doc that `CLAUDE.md` points
to.*
