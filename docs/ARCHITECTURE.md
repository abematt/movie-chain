# Unspool — Architecture & Overview

> Detailed source-of-truth for the app's design. `CLAUDE.md` is the lean,
> auto-loaded summary; **this file is the deep reference** — point a chat here to
> get it up to speed, and keep it current when the code changes.

### The doc set

| Doc | What it's for |
|---|---|
| [`../CLAUDE.md`](../CLAUDE.md) | Lean auto-loaded summary + commands, versioning process, conventions |
| **this file** | How the app works today: modules, rules, design decisions, the "why" |
| [`ROADMAP.md`](ROADMAP.md) | The planned path to 1.0 (launch) — six milestones, each with scope, decisions to settle, and known traps |
| [`DAILY-CHAIN.md`](DAILY-CHAIN.md) | Spec for the headline mode: one puzzle a day, longest route from A to B — **not yet playtested or built** |
| [`../CHANGELOG.md`](../CHANGELOG.md) | What changed per version (Keep a Changelog + SemVer); its header holds the version↔milestone table |
| [`ASSISTED-MODE.md`](ASSISTED-MODE.md) | Postmortem of a removed mode — **read before building anything that picks chain links for the player** |
| [`GROWTH.md`](GROWTH.md) | Growth mechanics as a build catalog — the share/daily/challenge/replay features that make distribution possible, sized and mapped to the code |

Current version **0.5.0**; **1.0.0 means launch**. When you change the architecture,
providers, rules, or stack, update *this* file; when you land a user-visible change,
add a changelog entry; when a plan changes, edit the roadmap.

## What the app is

**Unspool** (`movie-quiz`; called Movie Chain until 0.6.0) is a single-player recall game. You build a chain
that alternates **actor → movie → actor → movie …**, where every link must be
real: the actor actually appeared in the movie. Your score is the chain length,
and each turn is on a countdown — run out of time and the game ends.

- Bundle ID: `abe.movie-quiz`
- No autocomplete by design — you type from memory; spelling is forgiven, but
  the answer is not.
- A multiple-choice "Assisted" mode was built and **removed** after playtesting —
  see [`ASSISTED-MODE.md`](ASSISTED-MODE.md) for why (it served neither audience)
  and what to build instead if assistance returns.

## Stack & platform

| | |
|---|---|
| Language | Swift 6 language mode; tests use Swift Testing |
| UI | SwiftUI |
| State | Observation framework (`@Observable`, `@State`) |
| Concurrency | Swift structured concurrency (`async`/`await`, `Task`, `@MainActor`); builds with **MainActor-default isolation** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| Min OS | iOS **18.0** deployment target (true floor is 17.0 — `@Observable` blocks 16; APIs above 18.0 need `if #available`). macOS/visionOS minimums remain 26.2 |
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
  films ≈ the most widely seen), `Config.seedMoviePoolPages` pages (~100). Loaded
  once per session, so the extra pages are cheap and buy real variety — at two pages
  a run of shuffles recycled the same ~40 titles.
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
> decoding through a `@concurrent static func decode(...) async` helper (runs on the
> cooperative pool, off main — a plain `nonisolated async` would *not*: under
> Approachable Concurrency it runs on the caller's actor), and the private DTOs are
> `nonisolated` so their
> `Decodable` conformance isn't MainActor-bound (same pattern as `Collection.swift`).

The TMDB implementation of `filmography(of:)` drops **self-appearance credits**
(TMDB `character` of "Self", incl. "Self - Host" etc.) — making-of featurettes,
talk-show and documentary appearances are not film roles and must not be valid
chain links (e.g. Jack Black's "Making of School of Rock" was being accepted for
a typed "School of Rock"). Note this lives in `TMDBProvider`, not the protocol —
a new provider must apply the same rule itself (the stub graph simply has no
such credits). `filmography` is also **sorted most-popular first** (`cast` is left
in TMDB **billing order** — already its recognizability signal): this is what makes
the "you were one away" near-miss at game over surface a film the player would
actually know, since `endGame` takes the first unused candidate. Every TMDB request also carries a
short `Config.requestTimeout` so a stalled fetch fails fast instead of freezing a
turn (the clock is paused across candidate loads — see the engine's retry note).

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
- **Records & recap:** `bestChain`/`bestPoints` (persisted via an injectable
  `UserDefaults`, `.standard` in the app). The finished run's facts ride on the
  phase itself — `.gameOver(Summary)` — so they can't exist outside a game-over:
  `isNewBest` (celebration trigger), `missedAnswer` (a valid answer left ungiven on
  the turn that timed out — the "you were one away" near-miss, captured in
  `endGame()` from the still-loaded `candidates`; `nil` on a manual quit), and
  `reelAdditions` (how many brand-new entities this run added to the collection —
  the "+N to your Reel" figure). `ContentView` hands the summary to `GameOverView`.
- **Run reset:** `startGame` and `reset` both go through one `resetRun()`, so the
  per-run fields can't drift apart between the two.
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
- **Candidate-load resilience:** `loadCandidates` **retries** a failed fetch
  (`Config.candidateLoadAttempts`, short backoff) — a shared-key rate limit or a
  stalled request would otherwise empty `candidates` and leave the turn with
  nothing to answer — nothing validates, so the run is stuck (the reported "stuck
  turn"). Retries
  run while the clock is paused, so they cost no time; combined with the per-request
  `requestTimeout`, a hiccup self-heals instead of freezing. If retries are
  exhausted, `awaitingRetry` flips true and the UI shows a manual **Retry**
  (`retryTurn`, which reloads and restarts the turn clock fresh — the failure
  wasn't the player's fault), rather than a silently dead turn.
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
  place." Pure count stats (no TMDB rarity/obscurity): a hero total + blue/purple
  category split, "your regulars" (most-logged), the Actors/Movies tabs, decade and
  genre menus (`ReelFilter`, options drawn from the Reel itself; an actor matches
  through a linked film), and the **deck**: actors as playing cards earned through
  the films linked through them (`links`, recorded from adjacent chain pairs),
  movies as framed posters. No numbers are printed on the fronts. Tapping either
  lifts it out and flips it to the other side of its links — an actor's films, a
  movie's actors. Genres come from `genre_ids` on every TMDB movie response
  (`Movie.genreIDs`), named from a fixed table (`ReelGenre`). Finishes (paper /
  inked at 5 links / holo at 11) come from `ReelTier`, so the Reel costs no TMDB
  requests. Three across: cards and frames are drawn once at a design width and
  scaled (`ReelCanvas`), which makes the lift a pure zoom. The lifted card makes
  the whole trip itself, drawn above the grid: each grid card records its on-screen
  frame (`SlotFrames`), and `LiftFlight` scales and moves the lifted card from that
  slot to rest and back, the grid card staying unseen in place until it lands.
  Once out, an actor card tips with the gyro or a finger (`CardTilt`): only small
  leaf views read the per-frame tilt, everything moves by transform, and the tilt
  eases in after the card settles and flattens before it flies home.
  (`matchedGeometryEffect` was tried first; it flies the *grid's* card, which
  travels under the dim layer and under later grid cells.) Art reads through
  `ArtCache` (memory + disk cache, off-main decode) so a reopened Reel draws at
  once; the first screen is warmed at launch. Cards, frames and tiers live in
  `ReelCards.swift`. Also
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

> ⚠️ **The current visual treatment is placeholder**, including the chain rendering —
> a full design overhaul is the next milestone: **[`ROADMAP.md` →
> 0.5.0](ROADMAP.md#050--design-overhaul)**, which holds the options still being
> explored (a stacked list of cards is currently leading) and the constraints. Read it
> before changing anything visual — the direction is **not settled yet**.
> Treat what follows as a description of *what exists today*, not a settled identity.
> The **structure** is what's meant to survive: tokens in one place, owned components,
> and per-node category identity — so a re-skin is a `Theme`/`Components` change
> rather than a rewrite of every screen.

**Vocabulary (fixed app-wide):** a *chain* is one whole run, from the dealt start
to the end; a *link* is one correct answer, and the score counts links; the dealt
*start* is not a link. Copy, numbering and the recap all follow this, so the last
link number always equals the score.

**Cream Neobrutalist** (0.5.0): a cream canvas, white surfaces with a 2pt ink border and a hard unblurred
offset shadow, one coral call-to-action, and two category accents — **blue for
actors, yellow for movies** (the most colour-blind-safe pair). Dark mode flips the
borders to cream on a warm charcoal canvas. A bold serif with an italic flourish
carries display type in **Fraunces**, bundled in `movie-quiz/Fonts/` as four static
cuts (bold and italic at a 72pt and a 24pt optical size) with its SIL OFL license, and
registered at first use by `FontRegistry` in `Theme.swift`. Body, buttons and labels
stay in SF rather than the spec's Inter, since SF is the iOS-native equivalent. Two
other deliberate deviations: everything but the big numerals scales with Dynamic Type,
and icons are SF Symbols rather than Phosphor. UI labels are
small, bold, uppercase and tracked.
- **Color** lives in `Assets.xcassets` as named sets with light+dark variants —
  `Canvas` (cream), `Ink` (text and every border), `Tile` (white surface),
  `Shadow` (the hard offset shadow), `Hairline` (muted track), `Coral` (the CTA),
  `ActorBlue`, `MovieYellow`, `Good` (correct-link green), and `OnAccent`
  (near-black text for the light accents; actor blue takes white instead, via
  `NodeKind.onAccent`). `Theme.Color` just names them;
  muted text still uses Apple's semantic `.secondary`/`.tertiary`.
- `Theme` — token namespaces: `Color`, `Spacing`, `Border`, `Shadow` (`small`
  2pt for chrome, `large` 4pt for primary cards and the CTA), `Font` (the whole
  type system: serif `display`/`heading` with an italic `flourish`, sans `body`/
  `bodyStrong`/`small`, and the tracked uppercase `label` — everything but the big
  numerals rides a Dynamic Type text style), `Radius`, `Motion` (incl.
  `drop`, the spring a new tile lands on; `screen`, the soft spring the
  screen-to-screen carousel rides; `intro`, the seed cold-launch reveal; and
  `cascade`, the springy wave a staggered group of siblings rises in on).
  Views reference these, never literals. `AnyTransition.screenPush(reduceMotion:)`
  (also here) is the router's directional page push — see the UI section.
- `NodeKind` / `ChainNode` extensions give each kind one `accent` (blue/yellow), an `onAccent` text colour,
  a `tileLabel` ("ACTOR"/"MOVIE"), and a `symbol`, eliminating color/label logic
  that was duplicated across views.
- `Components.swift` — owned, reusable primitives (the app's shadcn-equivalent):
  `.metaLabel()` (the one uppercase-label recipe), `NodeName` (a name with the
  movie year as an italic flourish, never a parenthetical),
  `.neoSurface(...)` (the neobrutalist atom: fill, ink border, hard shadow, and a
  `pressed` state that collapses the shadow), `PrimaryButtonStyle`
  (`.buttonStyle(.primary)`, coral with a 4pt shadow), `GhostButtonStyle`
  (`.ghost`, white with a 2pt shadow), `PressScaleStyle` (`.pressScale` — a
  near-imperceptible press squish+dim for buttons that carry their own chrome but
  lacked an `isPressed` state, e.g. the in-game "Go"), `CardModifier` (`.card()`), `NodeTile`
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
- Feature components in their own files: [`ChainDeck.swift`](../movie-quiz/ChainDeck.swift)
  is the signature visual — every link is one card for its whole life: a new one is
  dealt in from below and pushes the last back into a pile that peeks out above it,
  sized to the room above the keyboard. [`ChainCards.swift`](../movie-quiz/ChainCards.swift)
  holds the pieces it shares with the game-over recap (`CompactChainCard`, `KindChip`,
  `ChainArt`). The original `ChainStack` tile stack, and the Cards style that briefly
  replaced it, sat behind a Settings → Chain style picker until the Deck won; both
  were removed.
  [`TimerBar.swift`](../movie-quiz/TimerBar.swift) is the slim linear countdown
  (drains in ink, shifts to a warning red in the final quarter).
- App-wide `.tint(.accentColor)` (ink) is applied once at the root in
  `movie_quizApp`; **no `.fontDesign`** — the look pairs the system serif (wordmark,
  game-over number) with the default sans for UI. The accent is defined for
  light/dark in `Assets.xcassets/AccentColor` (near-black / off-white).
- **Brand art** (0.6.0, Unspool) is supplied as finished assets, not drawn in code:
  the **two-circle mark** (blue actor + yellow movie, the ink overlap is the link) as
  `LogoMark`; the **`Wordmark`** ("unspool" in outlined Fraunces Display Bold with the
  mark as its "oo"); the **`FilmStrip`** supporting graphic (launch screen, store
  screenshots, share card — never the logo). All are SVG with "Preserve Vector Data"
  and an on-dark variant. The **app icon** (`AppIcon.appiconset`) is the mark on a
  cream tile, one 1024 universal entry plus iOS 18 **dark** (ink tile) and **tinted**
  variants. Every icon bitmap is **opaque (no alpha channel)** — iOS rejects icons
  with alpha at archive/upload; verify with `sips -g hasAlpha`.

### UI — SwiftUI, routed by phase

> ⚠️ Same caveat as the design system above: **the visuals described here are
> placeholder.** The routing, state ownership, and layout *constraints* (keyboard
> docking, portrait-only, Reduce Motion) are real and load-bearing; the styling is not
> settled, and the chain's replacement is still an open question. See **[`ROADMAP.md` →
> 0.5.0](ROADMAP.md#050--design-overhaul)** before changing anything visual.

- [`movie_quizApp.swift`](../movie-quiz/movie_quizApp.swift) — `@main` entry.
- [`ContentView.swift`](../movie-quiz/ContentView.swift) — owns the single
  `@State GameEngine` **and the shared `@State CollectionStore`** (injected into
  the engine so it can record, and passed to the screens that display it), and
  switches `SeedView` / `GameView` / `GameOverView` on `engine.phase` with a
  **direction-free forward carousel**: the app is a one-way loop (seed → playing →
  gameOver → *play again* → seed), so every change is a forward push on one
  horizontal axis via `.transition(.screenPush(reduceMotion:))` on
  `Theme.Motion.screen` — new screen in from the trailing edge, old out to the
  leading edge; no "back" (Play again is the next lap, not a retreat). The one
  exception is seed → playing, a cross-fade under the handoff flight (the home
  becomes the play screen rather than being left). Reduce Motion degrades every push
  to a cross-fade. `ContentView` also owns the `HandoffStage` and draws
  `HandoffFlight` above the screens, and owns `seedIntroDone`, the
  persisted (`@AppStorage`) once-ever flag for the seed intro (below) — kept here,
  above `SeedView` (recreated on each `.seed` re-entry), so every launch after the
  first, and every Play-again re-entry, correctly starts assembled.
- [`SeedView.swift`](../movie-quiz/SeedView.swift) — the home, written as **the
  first turn**: a sentence with a blank, not a search box or a button. Since 0.6.0
  (Unspool): a header of the **`Wordmark`** asset with the Reel and gear pills
  overlaid on its trailing edge; the dealt start as the head of a sentence (round
  avatar + kind chip, the name in Fraunces display, "*was in*" for an actor or
  "*starred*" for a movie); the **blank** ("a movie…" / "an actor…" over an ink rule,
  with a coral arrow); "Deal again" and "Pick your own" links; and a footer line with
  the best run and "tap the blank to start". The Reel pill is always reachable (count
  hidden when empty) because the Reel sheet hosts the TMDB attribution.
  - **The sentence's head** sits in a fixed-height region pinned to its bottom, so the
    blank never moves: a long name grows upward and shrinks to fit three lines. Only
    the head deals on Deal again (`AnyTransition.dealSentence`, keyed by
    `.id(seed.id)`: flicked off to the leading side, turning; the new one lands from
    just below on `Theme.Motion.drop`). Reduce Motion → cross-fade.
  - **The deal** is owned by the engine (`engine.dealtSeed`, dealt on every
    appearance and on resume — see the engine's "Seed deal" note). Each start warms
    its w185 art, and once it has sat on screen for 400ms the engine
    **prefetches its candidates** (`prefetchCandidates`; `startGame` uses them if the
    played start matches), so the first turn is answerable on arrival.
  - **Tapping the blank** starts the game through the handoff (below). Under Reduce
    Motion it just starts, and the screens cross-fade.
  - **Search flow** (`searching` state, behind the link) reuses the prior pieces —
    the Actor/Movie **segment**, the in-app-styled debounced field (auto-focused
    on open), and warm-tile result rows — with a "‹ Deal a start" back affordance.
    It's the flexible region (`maxHeight: .infinity`) so keyboard avoidance shrinks
    it and the field stays clear of the keys. iPhone is **portrait** (project
    setting); iPad keeps all orientations.
  - **Cold-launch intro** (once ever): the wordmark fades up centered and 1.5×
    (an animatable top spacer + an alignment that animates center → leading), then
    on `Theme.Motion.intro` rises to the header while the rest (the start → the
    blank → the links → the footer) assembles via the `ControlReveal` cascade. Gated
    by the `introDone` binding from `ContentView` — a Play-again re-entry starts
    fully assembled. Reduce Motion shows it at once, and a full-screen tap catcher
    lets a tap **skip to the assembled screen**.
- [`Handoff.swift`](../movie-quiz/Handoff.swift) — the **home → play handoff**. Not
  `matchedGeometryEffect` (which, in the Reel, flew the wrong copy under other
  layers): a flight. `HandoffStage` (`@Observable`, owned by `ContentView`, in the
  environment) collects frames in one named coordinate space — the home reports its
  avatar, chip, name, verb and blank, keyed by the start they belong to so a start
  dealing *out* can't overwrite them; the deck's start card (`DeckCard`, while it is
  the only card) reports its card, chip, art and name, and `GameView` its dock.
  `begin(with:)` freezes the home's frames; `HandoffFlight`, an overlay above both
  screens, draws copies from the tap on — held at the home's frames until play has
  laid out **and the answer field's first focus has passed** (it blocks the main
  thread for ~150ms loading the keyboard; flying through it lost the opening frames).
  Then, on its own `TimelineView` clock sampling `Theme.Motion.handoffSpring`, each
  frame draws every piece between its start and its destination *as laid out that
  frame* — the keyboard rising moves the deck and dock mid-flight. The avatar
  reshapes circle → rounded rect into the card's art; the name flies as two copies at
  a shared letter size (the home's lines fading out, the card's line fading in), since
  text can't reflow mid-flight; the card's surface and start sticker assemble in
  place around them; the blank crossfades into a still of the dock. At
  `handoffDuration` (0.55s — it plays every run, so it stays short) the stage
  finishes and the real start card and dock appear in the same frame the copies go,
  with a selection haptic; `GameView` then releases the first turn's clock
  (`playerReady`). The name's and the blank's crossfades carry a 2pt blur at their
  midpoint (`bridge`), so the two copies read as one shape changing. Underneath, the
  home's chrome fades out fast (`layoutOut`, 150ms) and play's fades in a beat later
  (`layoutIn`), so they never sit half-faded over each other. The blank presses
  through `\.blankPressed` (the arrow's neo press, no row scale) so the release frame
  matches the flight's first. Fallbacks: launch after 450ms without the focus, and give up (show
  play) after 1s without destinations. `ContentView` makes seed → play a cross-fade
  under it rather than a push.
- [`GameView.swift`](../movie-quiz/GameView.swift) — the turn. The chrome (sound ·
  seconds · quit) + `TimerBar`, the centered **serif score hero** (chain number +
  points), the `ChainDeck`, and the next-up hint, with the answer input
  **docked via `.safeAreaInset(.bottom)`** directly above the keys (auto-focused;
  the keyboard's Go submits) — laid out around the **always-present software
  keyboard**, the dominant constraint of a typing game. A **Retry** button replaces
  the input when `engine.awaitingRetry` (a candidate load failed, so typing would be
  futile — nothing would validate). Reacts to `engine.score` /
  `engine.feedback` to fire haptics, sound, the "+N" pop and the shake.
- [`GameOverView.swift`](../movie-quiz/GameOverView.swift) — final score (serif) +
  points, a quiet "a new best" mark (a serif-italic green pill, no confetti), the
  **Personal best fenced between hairlines** so it never reads as this run, the
  "you were one away" near-miss, **a "+N new to your Reel" line that opens the
  collection sheet**, the full chain revealed as a numbered recap of
  compact cards, and **Play again** + **Share** (the 🟦🟪 card).
- [`SettingsView.swift`](../movie-quiz/SettingsView.swift) — the app's settings
  surface, a `.sheet` opened from a **gear pill** on `SeedView` (mirroring the Reel
  pill on the opposite corner). A small on-brand card layout (not a stock grouped
  `Form`), `@AppStorage`-backed: currently the **sound toggle** (which also still
  lives inline in the game chrome), and the established home for settings to come.

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

> **The planned path to launch is [`ROADMAP.md`](ROADMAP.md)** (re-cut 2026-08-08) —
> foundations, design overhaul, the service / TMDB proxy, accounts, the
> [Daily Chain](DAILY-CHAIN.md) and friend groups, then launch, each with scope,
> decisions to settle, and known traps. Global leaderboards are dropped and Pass & Play
> moved after 1.0. The "Direction" sections below predate the re-cut: they remain the
> technical designs, and the roadmap is the plan of record over them.

The collection ("Your Reel") is the first fan-out built on top of the loop —
a local, login-free registry that layers on the engine without touching the
engine/provider split (it's just another observable store the engine records
into at game over). Still planned: genre locks, memory-recall every Nth link,
the Daily Chain and friend groups (accounts arrive at 0.9.0 — local
session/collection data is forward-compatible with that sync). The rule of thumb: **keep the
engine/provider split clean.** New rules live in `GameEngine`; new data sources
implement `MovieDataProvider`; new screens read observable state and call methods.

> **Read [`ASSISTED-MODE.md`](ASSISTED-MODE.md) before building any feature that
> picks chain links on the player's behalf** (a daily seeded chain, a tutorial, an
> easier mode). A multiple-choice Assisted difficulty was built, playtested, and
> removed; that doc records why it served neither audience, the **drift** trap any
> link-picking feature inherits (and why local ordering can't fix it), and the
> hint-shaped design to build instead.

### Direction: "Pass & Play" — a chain you shuttle between friends

The mode we most want to build next is an **asynchronous, pass-the-chain
multiplayer**: when your run ends you hand the chain to a friend, who continues it
and passes it on — **one shared chain that bounces between any number of players,
indefinitely** (a round-robin), each keeping it alive on their turn. It's the
social hook the single-player loop is missing, and it fits the architecture almost
suspiciously well — noting the intended shape here so it's not re-derived from
scratch:

- **Transport is a deep link, not a backend.** A finished chain encodes into a
  `moviechain://` link shared via the system share sheet (the same surface as
  today's `shareSummary` card). No accounts, no server — the link *is* the game
  state. This keeps the login-free, offline-friendly character of the app.
- **The payload is a pure `Codable` value + a codec**, in the same family as
  `FuzzyMatch`/`SeedDeal`/`CollectedEntity`: a versioned wire type (a `players`
  roster, a `turn` counter, and the ordered chain with each link tagged by its
  owner) plus a pure URL⇄payload transform (base64url in a query param),
  unit-tested for round-trip / malformed→nil / newer-version-rejected. Nothing
  UIKit- or network-bound.
- **The handoff is pass-on-run-end.** No separate "mode" to pick up front and no
  new turn logic: you play a normal run, and game-over simply offers "Pass to a
  friend" alongside "Share". Receiving a link (via `onOpenURL`) is what puts you
  into a pass game.
- **Continuing reuses the existing loop verbatim.** A new engine entry point
  rebuilds `chain` + `usedIds` from the payload and drops into `.playing` — so the
  no-repeat rule and bounded-set validation automatically span the **whole shared
  history**, and the receiver's app re-validates every link locally (no trust
  problem: a lie in the link just fails validation on arrival). The stale-load
  `generation` guard and clock-pause behaviour carry over unchanged.
- **Attribution is "hybrid" and keyed on a stable per-device id, not a name or a
  roster index** — so the same person coming back around the round-robin isn't
  duplicated and the per-player contribution split stays correct after any number
  of handoffs. Ownership lives on the *pass payload / engine*, **not** on
  `ChainNode` (which stays a pure domain link).
- **Two rules keep the existing stats honest.** A shared chain must **never write
  the solo best** (`bestChain`/`bestPoints`) — a co-op effort isn't a personal
  record. And the Reel ("Your Reel" is a "how many *you* know" hook) must log
  **only the links you personally added**, never a friend's — i.e. filter the
  chain by owner before recording.
- **Known gotchas to plan for.** (1) Registering a custom URL scheme needs a
  `CFBundleURLTypes` entry, which can't be expressed as an `INFOPLIST_KEY_*`
  build setting — it requires a real `Info.plist`, and that plist must live
  **outside** the synchronized `movie-quiz/` group (e.g. the project root) or the
  `PBXFileSystemSynchronizedRootGroup` also copies it into the bundle as a resource
  and the build fails with "Multiple commands produce … Info.plist". Keep
  `GENERATE_INFOPLIST_FILE = YES` — it merges the generated keys on top of the
  partial plist. (2) A **custom scheme** is the cheap path but has real UX limits:
  Messages shows a system "open in app?" prompt and no rich preview, and the link
  is dead for anyone without the app installed. **Universal Links** (a real domain
  + an `apple-app-site-association` file) fix both and are the eventual target —
  and since the codec already speaks URLs, only the transport changes.

Accounts arrive at 0.9.0 on the roadmap; the per-device player id (now a 0.7.0
foundation), plus the local session/collection data, are all
forward-compatible with a future sync.

### Direction: sociality as a core gamification axis

Pass & Play is really the first step of a larger bet: **the strongest retention
and gamification lever for this game is other people, not just points.** A recall
game is inherently social — the fun of "wait, who else was in that?" is a shared
fun — so the roadmap should treat sociality as a spectrum to build across, not a
single feature:

- **Hyper-local — friends & direct handoffs.** The tightest loop: you and people
  you actually know. Pass & Play (above), a shared chain between a small named
  group, "beat my chain" challenges sent to a specific friend, seeing a friend's
  daily result. Low stakes, high trust, no discovery problem — this is where the
  first social features should land, because the deep-link handoff needs no
  accounts or backend to work.
- **Local/area & affinity groups.** A middle tier: a regional or cohort
  leaderboard (your city, your campus, a film-club group code), a "chain of the
  day" that a bounded community all plays and compares. Enough of a crowd to feel
  alive, small enough that a good run can actually top the board — which keeps it
  motivating in a way a global list rarely is for most players.
- **Global — the whole player base.** All-time and daily global leaderboards, a
  shared daily seed everyone plays (a Connections/Wordle-style "same puzzle for
  everyone today" that makes the 🟦🟪 share card comparable), longest-chain halls
  of fame, spectating record chains. High ceiling, but on its own it's motivating
  mostly for the top few — which is exactly why the local/affinity tier matters.

These tiers stack rather than compete: the same finished-run data feeds a friend
handoff, a group board, and a global daily. Practically, this is **the point where
accounts + a backend become worth it** (identity that persists across devices,
authoritative leaderboards, anti-cheat via server-side re-validation of a chain) —
and it's the reason the app already resolves everything to stable TMDB ids and
keeps the engine/provider/UI split clean and re-validatable: a submitted chain can
be verified server-side with the same bounded-set logic the client uses. The local
collection, best scores, and the per-device player id are all forward-compatible
with that sync. **Design principle to preserve as this grows:** the game must stay
fully playable and fun *solo and offline* — every social layer is additive on top
of the login-free core, never a gate in front of it.

## Dev workflow

- **Versioning:** the app is versioned (currently **0.5.0**; **1.0.0 means launch**,
  with each remaining pre-launch milestone allocated a minor version — see the
  roadmap table in the changelog header) and every notable change is recorded in
  [`CHANGELOG.md`](../CHANGELOG.md) (Keep a Changelog + SemVer). `MARKETING_VERSION`
  / `CURRENT_PROJECT_VERSION` in build settings are the source of truth; code reads
  them from the bundle via `Config.appVersion`/`buildNumber`/`versionString` and
  Settings displays the result, so the shown version can't drift from the built one.
  See "Versioning & changelog" in `CLAUDE.md` for the bump/tag steps.
- Day to day: Xcode — ⌘B build, ⌘R run, ⌘U test. `#Preview` blocks drive canvas.
- Deployment target is **iOS 18.0**, so any 18.x+ simulator works; the suite is
  verified on both 18.0 and 26.x. Run the tests against an **18.x** simulator as well
  as the newest when touching version-sensitive code — 18.0 is the floor the shipped
  build must honour (command in `CLAUDE.md` → "Running it").
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
  retried, a loaded side isn't re-fetched; the **candidate-load retry**: a transient
  failure is retried transparently, an exhausted load flips `awaitingRetry` and
  `retryTurn` recovers; and Reel logging on a completed chain),
  `CollectionStoreTests` locks the "Your Reel" logging rule (length ≥ 2, seed
  counted once a link lands, dedup by id, `timesLogged` per-chain), and
  `SeedDealTests` locks the home-screen deal policy (actor/movie bias, recent-id
  avoidance with full-pool fallback, other-kind fallback, empty→nil). Run with ⌘U
  or the `xcodebuild … test` invocation above.

---

*Keeping this current: when the architecture, a provider, the game rules, or the
stack changes, update this file. It is the detailed doc that `CLAUDE.md` points
to.*
