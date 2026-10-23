---
id: inception
label: Movie Chain
span: Jul 9 – Oct 21
versions: → 0.4.0
accent: blue
order: 1
sessions: 
start: 2026-07-09
end: 2026-07-25
---

## Era: Inception → design overhaul kickoff (2026-07-09 → 2026-10-21)

**Sources:** git history a80d086 → 5f8b60a (31 commits, full bodies), CHANGELOG.md (0.4.0 entry + the in-era `[Unreleased]` block as of 5f8b60a), docs/ASSISTED-MODE.md, docs/ROADMAP.md and its history (94153f8 → f812f1b), docs/GROWTH.md (b529fd5), docs/DAILY-CHAIN.md + docs/DESIGN-BRIEF.md (f812f1b), ARCHITECTURE.md additions (582750c), old Claude memory notes in `~/.claude/projects/-Users-abrahammathew-dev-movie-quiz/memory/`. **No session transcripts and no screenshots exist for this era.** Anything marked *(inferred)* is my reading, not stated in a source.

### Arc of this era

A weekend-scale prototype ("Movie Chain", working title) went from an empty Xcode template (Jul 9) to a complete, tested solo game in about a week (Jul 10–16): engine/provider split, fuzzy matching against a bounded candidate set, TMDB + offline stub data, scoring/juice, a collection ("Your Reel"), an NYT-Games/Connections-style skin, and a play-first "deal a start" home. Then came the era's defining detour: an **Assisted (multiple-choice) mode** built across four commits on Jul 24–25, playtested with a non-movie person, and **removed ~37 hours after its first commit**, leaving behind a postmortem (`docs/ASSISTED-MODE.md`) whose "drift" lesson shapes every later link-picking feature. The same day (Jul 25) the app got versioned for the first time (0.4.0), a roadmap, and an empirically-audited deployment target (26.2 → 18.0). Aug 8 was a planning day: a growth build catalog (GROWTH.md) and — per the docs — a planning conversation that re-cut the roadmap (dropped global leaderboards, added the Daily Chain). Then ~2.5 months of silence in git, and on **Oct 21** the re-cut docs were committed and the design overhaul began in earnest: a **Cream Neobrutalist** prototype with a card chain, a unified type system, and serif numerals, on branch `feature_cream-neobrutalist`.

Co-author trailers trace the tooling too: "Claude Opus 4.8" (Jul 10–16), one "Claude Fable 5" (0a74c5e, Jul 13), "Claude Opus 5" (Jul 24 removal onward through Aug 8), "Claude Opus 5.5" (Oct 21). Codex was used as an **adversarial reviewer** from Jul 11 on (203e8cb, 439c2e3, 7fc5762).

Test count over the era: 0 → 12 (9c55bd1) → 22 (dabe62e) → 39 (439c2e3) → 52 (98c0a7d) → 58 (190b962) → **42** after Assisted was removed (79f5d88).

---

### 2026-07-09 — Initial commit

- `a80d086` 19:09 — Xcode template only: `ContentView.swift`, `movie_quizApp.swift`, asset catalog, pbxproj (8 files, 520 lines). Bundle id `abe.movie-quiz`. Deployment target came in at **iOS 26.2** (Xcode's default — this matters on Jul 25). Swift 5 language mode at this point (Swift 6 came much later, outside this era).

### 2026-07-10 — The core game loop, architecture doc, first tests, design-system layer

Four commits in one day.

**`bca93e8` 10:42 — "Implement Movie Chain core game loop"** (14 files, ~1,136 lines)
- `MovieDataProvider` protocol with live `TMDBProvider` and offline `StubProvider` (hand-built graph: Ocean's Eleven, Fight Club, 12 Years a Slave-ish Fassbender/Ejiofor/Nyong'o cast, The Departed, Good Will Hunting, Inception…).
- `GameEngine` (`@MainActor @Observable`): seed → playing → gameOver, per-turn timer (`Config.secondsPerTurn = 30`), no-repeat rule, score = chain length.
- `FuzzyMatch`: spelling-tolerant matching **only against the bounded candidate set** (one movie's cast or one actor's filmography), threshold **0.72**, with whole-word/prefix/containment boosts (0.9 / 0.85 / 0.82).
- Screens: `SeedView`, `GameView`, `GameOverView` routed by `ContentView`.
- First CLAUDE.md, including a **Scope note** telling Claude to ignore the ancestor Measure Protocol `CLAUDE.md` files (the repo sits inside a work workspace).
- "Hardening from adversarial review" already in the very first feature commit:
  - TMDB credential loaded at runtime from gitignored `TMDBSecrets.plist`; absent → falls back to stub demo data.
  - **Pause the countdown during async candidate loads** so a slow fetch can't end the game on an in-time answer.
  - Tightened fuzzy boosts so trivial fragments ("a", "the") no longer match.

**Decisions**
- **No autocomplete; fuzzy match against a bounded set instead** — autocomplete "would spoil a recall game"; because each turn's valid answers are small and known, spelling tolerance is safe ("John Malkovic" resolves without global fuzzy search or false positives). This is the founding design insight of the app.
- **Engine/provider split from day one** — lets the game run offline (stub) and later lets a TMDB proxy be "a new provider implementation, not an engine change" (that payoff is cited repeatedly in later roadmap docs).
- **Token never committed** — runtime plist + example file.

**`8d1ce43` 11:48 — docs/ARCHITECTURE.md created** as the deep module-by-module reference; CLAUDE.md made lean and points at it. Adds `Models.swift` domain types (`Person`, `Movie`, `ChainNode`, `NodeKind`).
- Decision: two-tier docs — CLAUDE.md = intent/why/gotchas (auto-loaded), ARCHITECTURE.md = depth. Backed by Abraham's July feedback memory "keep-claude-md-current": *"He treats CLAUDE.md / the architecture doc as the durable, auto-loaded memory every chat reads, so stale docs silently mislead every future session."*

**`9c55bd1` 13:19 — "Fix sequel/actor matching, add unit test target"** (first tests: 12)
- **Bug: "mission impossible 3" resolved to *Mission: Impossible II*.** Character-level edit distance scored Arabic "3" closer to "ii" (2 edits) than "iii" (3). Fix: normalize Roman-numeral tokens to Arabic in `normalize`, **round-trip-validated** so "Malcolm X", "X-Men", "I Am Legend" still match themselves.
- **Bug: duplicate near-empty TMDB person stubs** were tappable at seed search and gave an almost-empty filmography. Fix: pure `ActorRanking.rank` — rank by TMDB popularity, identity is TMDB id never the name (homonyms preserved), drop only provably-empty stubs (zero popularity AND no known work).
- Main-actor isolation warning fixed by resolving the default provider **in the init body, not a default argument** (Config is `@MainActor` under MainActor-default isolation) — this becomes a permanent CLAUDE.md rule.
- `movie-quizTests` target + shared scheme added.

**`d51864e` 15:10 — SwiftUI design-system layer**
- `Theme.swift` (spacing/radius/motion tokens; per-node icon + accent identity on `NodeKind`/`ChainNode`, killing an icon closure duplicated across three views) and `Components.swift` (`PrimaryButtonStyle`, `.card()`, `NodeGlyph`, `ChainPill`).
- Built on Apple semantic primitives (system fonts, semantic colors, 8-pt grid) so Dynamic Type and light/dark come free; rounded font design app-wide.
- `#if DEBUG` QA hooks: `-uiDemoChain` / `-uiDemoGameOver` launch args to drive UI states without typing.
- Decision: tokens + owned components first, so later re-skins are a `Theme`/`Components` change rather than a rewrite. (The 0.4.0 roadmap later explicitly cites this as "what must survive" a redesign.)

### 2026-07-11 — Gamification, the NYT/Connections redesign, Your Reel, cold-launch intro

**`c057968` 00:57 — gamification layer + fixes** (`Scoring.swift`, flame tiers, haptics, synthesised audio, timer ring, streak flame)
- Scoring (pure, unit-tested): `base = 10` per link + **speed bonus = 1 pt per second left** + **obscurity bonus = 30 / (1 + popularity/8)**, clamped 0…30 (A-listers popularity ~40–120 earn little; deep cuts in single digits earn most). "Fast" = ≥66% of the clock left. Flame tiers: 0–2 none, 3–4, 5–7, 8–11, 12+.
- Sound: synthesised sine tones via `AVAudioEngine`, no bundled assets; correct-link chime walks a major pentatonic scale. **Bug/feel fix: the chime used to climb endlessly and "read as shrill on long chains" — capped to cycle within a single octave.** `.ambient` session so the silent switch mutes it.
- FuzzyMatch: boosted-score ties now break on raw similarity, so "school of rock" prefers the film over a "Making of…" featurette regardless of candidate order.
- TMDBProvider: drop "Self" credits (making-of/talk-show appearances aren't film roles).
- Quit now ends the run in place and shows the summary ("Chain ended", no near-miss) instead of resetting.
- **Stale-load race (found by adversarial review):** a slow fetch from an abandoned/quit game could install the previous node's cast into a *new* round. Fixed with a **monotonic `generation` token**; the changelog notes a `phase == .playing` check alone can't catch it "because the new game is also playing." Regression test with a gated stub provider.
- The near-miss ("you were one away", `missedAnswer`) first appears here.
- Seed screen rebuilt as a branded landing instead of stock NavigationStack/List/searchable.
- **Removed a serpentine `SnakeChainView` from the play screen (cluttered)** — first of several chain-visualization attempts that got cut.

**`dabe62e` 13:12 — "Redesign UI in an NYT-Games / Connections treatment"** (22 files)
- Paper-warm neutrals, near-black ink, **blue = actor, purple = movie**, serif wordmark + system sans, "no flame/confetti/radial-heat" (i.e. the gamification visuals from 12 hours earlier were mostly ripped out: `StreakFlame.swift` and `TimerRing.swift` deleted).
- New color sets (Canvas, Ink, Tile, Hairline, ActorBlue, MoviePurple, Good, OnAccent — light+dark).
- `ChainStack.swift`: the chain as a rising **Tetris-style stack of tiles** (new links drop in, older collapse to "+N earlier"). `TimerBar.swift`: slim linear countdown replacing the ring.
- GameView laid out around the **always-present keyboard** (input docked via `safeAreaInset(.bottom)`); fix for tile text scaling down as the chain filled (natural-height stack clipped from the top instead of compressed).
- GameOverView: number-only serif hero, "a new best" pill, numbered recap, Share.
- `shareSummary`: spoiler-free text card: `Movie Chain 🎬 / N links · P pts / 🟦🟪🟦…`.
- 22 tests.
- Decision: editorial "puzzle page" register over juicy-arcade. *(The roadmap later calls this "a competent NYT-Games/Connections pastiche, but it isn't an identity of its own" — placeholder.)*

**`a99333e` 16:13 — "Your Reel" collection**
- Local, login-free registry of every actor/movie logged — "a 'look how many you know' retention hook."
- `CollectedEntity` (pure Codable, deduped by TMDB id) + `CollectionStore` (`@MainActor @Observable`), JSON snapshot in Application Support. Writes go through a serial queue so the newest snapshot always wins; `flush()` on scenePhase background.
- **The one logging rule: `record(chain:)` only when `chain.count >= 2`** — encodes "successful combinations only; seed counts once a link lands; a bare seed logs nothing". `timesLogged` counts distinct chains.
- Pure count stats, explicitly **no rarity**. Art via `AsyncImage` (system-cached, never stored).
- Decision: JSON file, not SwiftData — small bounded data, matches the engine's UserDefaults style (per CLAUDE.md).

**`203e8cb` 21:57 — seed cold-launch intro + polish**
- First-run intro: centered lockup → mini-chain drop-in → rise-and-assemble control cascade; skippable; Reduce-Motion aware.
- **Codex adversarial review** caught: intro controls were focusable/activatable by VoiceOver/Switch Control before they were visible → gated accessibility + enabled state on the same reveal flag. Also corrected docs that said "once-per-launch" when the behavior is **once-ever** (persisted).

### 2026-07-13 — Home as hero + live search; doc audit

**`af4ca14` 11:50**
- SeedView reshaped from a form-like landing into a home: wordmark, tagline, best/Reel stats; keyboard-aware collapse (`heroCollapsed = focused || non-empty query`).
- Two big category tiles replaced by a compact actor/movie `SegmentButtonStyle` toggle; **bug: the old `.plain` button dropped touches on its padding** → `.contentShape`. Selection haptic.
- Adversarial-review fixes: seed-search errors had been writing `GameEngine.feedback` (gameplay feedback), and a stale debounced search could "buzz mid-round" → cancel `searchTask` on start/disappear. VoiceOver `.isSelected`.
- **Decision: lock iPhone to portrait** — the docked-keyboard play screen couldn't clear the keyboard in landscape; iPad keeps all orientations. (Becomes a permanent hard constraint, restated in every design doc.)

**`0a74c5e` 12:00 — docs: code-vs-doc review** (co-authored "Claude Fable 5"). Full scan found "no incorrect or misleading claims, but a few real omissions": MainActor-default isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) "silently shapes all new code", where `ActorRanking` lives, that "Self" filtering is provider behavior not a protocol guarantee, the DEBUG launch args, haptics/sound pre-warm.

### 2026-07-16 — "Deal a start": play-first home; four motion beats

**`439c2e3` 16:54 — play-first home** (19 files, ~980 lines; 39 tests)
- **Deal pool = most-watched films** via TMDB `discover?sort_by=vote_count.desc`, plus **actors derived from those films' top-billed casts** (`seedActorSourceMovies = 18`, `seedTopBilledPerMovie = 5`). Why: TMDB "trending"/`*/popular` surfaced obscure/unfamiliar names; vote count = how widely *watched*, i.e. recognizability.
- `SeedDeal` (pure, unit-tested): actor bias `0.6`, avoids recently dealt starts (`seedRecentWindow = 8`).
- Per-side pool cache with independent load/retry — **bug: a failed/rate-limited side used to stick a partial (movie-only) pool for the whole session.**
- SeedView rebuilt around one ink **"Start with ⟨name⟩"** button (Play + seed fused; name auto-fits one line so Shuffle deals in/out cleanly). Search demoted to an opt-in link; Reel shrunk to an always-reachable corner pill; personal best moved into the Reel sheet.
- **Main-thread hitch on seed→play**: JSON decode moved off the main actor (nonisolated DTOs) and haptic/audio warm-up moved to the idle seed screen with deferred keyboard focus.
- **TMDB attribution** (logo + non-endorsement disclaimer) added to the Reel sheet — and that's *why* the Reel pill must always be reachable, even empty.
- First app icon: a chain-tile mark on ink, opaque (no alpha channel).
- "Reviewed via two Codex adversarial passes; all findings resolved."

**`7fc5762` 17:50 — four restrained motion beats**
- Ran a `find-animation-opportunities` pass ("Emil Kowalski's skill, adapted from web to SwiftUI"); shipped only the four that survived its frequency/purpose/speed/function gate: (1) game-over recap staggers in; (2) sound toggle glyph `.symbolEffect(.replace)` in a fixed-width slot; (3) `PressScaleStyle` on the in-game "Go" button; (4) one-shot score bounce on a new best.
- Codex review fixes: PressScaleStyle honors Reduce Motion; bounce is a `keyframeAnimator` whose resting scale is always 1 (can't stick oversized if Reduce Motion toggles); **bounce delayed 450ms** to clear the carousel push.
- Motion tokens at this point: `drop` spring(0.34, 0.62), `screen` spring(0.45, 0.86), `intro` spring(0.62, 0.82), `cascade` spring(0.5, 0.72).
- Decision: restraint — reject most animation candidates.

### 2026-07-24 — Pass & Play + sociality written down; Assisted mode built

**`582750c` 00:12 — docs: Pass & Play + sociality as future direction** (ARCHITECTURE.md +94 lines)
- Pass & Play: async pass-the-chain multiplayer; transport = `moviechain://` deep link (no backend, "the link *is* the game state"); pure versioned Codable payload + base64url URL codec; pass-on-run-end (no mode to pick); receiver re-validates every link locally ("a lie in the link just fails validation on arrival"); attribution keyed on a stable per-device id; **shared chain never writes the solo best; Reel logs only your own links.**
- Gotcha recorded in advance: a custom URL scheme needs a real `Info.plist` *outside* the synchronized `movie-quiz/` group or the build fails with "Multiple commands produce … Info.plist"; custom schemes show an "open in app?" prompt, no preview, dead without the app → Universal Links eventually.
- Sociality spectrum: hyper-local (friends) → local/affinity (city, campus, film-club code) → **global leaderboards** (all-time + daily). Principle: "the game must stay fully playable and fun solo and offline — every social layer is additive."
- Note: **global leaderboards were planned here and dropped on Aug 8** (see below) — a clean reversal for a post.

**`ef2603b` 00:38 — Assisted difficulty: engine** — session-level difficulty at `startGame`; each turn shows `optionCount = 3` options (1 correct from the candidate set + recognizable distractors from cached deal pools, **zero extra network**), tap to answer; wrong tap docks `assistedWrongPenalty = 8` seconds; pure seeded-RNG `Choices.build`; distractors exclude every candidate id ("a wrong option is never secretly right"); **split record tracks** (`bestChainAssisted`/`bestPointsAssisted`), "forward-compatible with the planned split leaderboards."

**`3af5d28` 10:07 — Assisted UI**: Hardcore/Assisted `DifficultyToggle` on home (persisted `@AppStorage`), gear pill → new `SettingsView` (default difficulty + sound toggle), GameView bottom band branches: keyboard vs three tappable option tiles (uniform color so the answer never leaks; wrong tap shakes), "· Assisted" tag on game over and share card.

**`98c0a7d` 11:24 — "three field-reported refinements"** (52 tests)
1. **Stuck turn**: a stalled/rate-limited candidate fetch froze the turn — clock is paused across the load, URLSession's ~60s default let a hung request hang the game, and a thrown fetch emptied options with no recovery. Fix: `Config.requestTimeout = 12`s, `candidateLoadAttempts = 3` silent retries (paused clock = no time cost), exhausted load → `awaitingRetry` → manual **Retry** (`retryTurn` restarts the clock fresh). Applies to both modes.
2. **Obscure correct answers**: filmography sorted most-popular first; correct option picked from the top `assistCorrectPoolSize = 8`.
3. Option thumbnails (`NodeThumbnail`, headshot/poster).

### 2026-07-25 — Assisted mode diagnosed, then removed; versioning; deployment-target audit; doc map

The busiest and most consequential day of the era.

**`190b962` 13:42 — "gate every chain step on familiarity; stop polluting the Reel"** (58 tests)
- **Chain drift** (reported from play): "a Bollywood star with one Hollywood credit" legitimately enters the recognizable actor pool, but stepping onto her strands the chain — her candidate set is non-mainstream, its casts are non-mainstream, and the no-repeat rule forbids retreating.
- The previous fix (ordering that node's own candidates) "cannot escape it: ordering a set that is 95% unfamiliar still yields something unfamiliar."
- Real diagnosis: **"The game curated recognizability for the seed (step 0) and then abandoned it for every step after — that inconsistency, not a tuning miss, was the bug."**
- Fix: `Choices.FamiliarityGate` at every step — `.topBilled` on actor turns (`assistTopBilled = 6`; the current film already passed the gate so its leads are recognizable by construction) and `.minVoteCount` on movie turns (`assistMinVoteCount = 4_000`; vote_count = stable "how widely seen", unlike right-now popularity; tuned to keep the global canon incl. non-English films while excluding regional-only hits). Self-reinforcing. Replaced `assistCorrectPoolSize`. Added `Movie.voteCount`; widened the movie pool to ~100 titles (`seedMoviePoolPages = 5`) because at 2 pages "the same ~40 recycled as distractors."
- **Reel pollution**: Reel logging made Hardcore-only — "tapping a recognized name isn't recall."

**`79f5d88` 14:15 — "Remove Assisted mode; keep the findings in docs/ASSISTED-MODE.md"** (15 files, +315/−1,008; 42 tests)
- "Playtested (including with a non-movie-person) and removed. It served neither audience, which is a design conclusion rather than a tuning miss."
  - Newcomer: "the hard part isn't recognizing a name, it's knowing WHO WAS IN WHAT."
  - Enthusiast: "tapping from a list deletes the act of recall that IS the accomplishment."
- Removed: `Difficulty`, `Choices.swift` + `FamiliarityGate`, `currentOptions`/`select`/split records, option panel, `DifficultyToggle`, `NodeThumbnail`, `Movie.voteCount`, assisted tests. "Keeping it in-tree bought nothing while taxing every future GameEngine change."
- **Kept** (not assisted-specific): candidate-load retry + `requestTimeout` + `retryTurn`/`awaitingRetry` (fixed a freeze that hits Hardcore too), popularity-sorted filmography (better near-miss), `seedMoviePoolPages = 5`, `SettingsView` + gear pill.
- Orphaned UserDefaults keys (`bestChainAssisted`, `bestPointsAssisted`, `difficulty`) deliberately left in place "so a revival would find its old records intact."
- Lifespan: first commit 2026-07-24 00:38 → removal 2026-07-25 14:15 ≈ **37.5 hours, 4 commits**.

**docs/ASSISTED-MODE.md — the postmortem (key content for a post)**
- Recovery SHAs: `ef2603b` (engine + Choices + tests), `3af5d28` (UI), `98c0a7d` (stuck-turn fix, recognizability ordering, thumbnails), `190b962` (FamiliarityGate + Hardcore-only Reel). `git show 190b962` = the feature at its most refined.
- **"The asymmetry of responsibility"**: "In Hardcore the player chose to type that name, so they knowingly entered that neighborhood. The moment the game *offers* the node, the game owns where the player ends up." Applies to any link-picking feature: daily seeded chain, tutorial, AI opponent, Pass & Play validation.
- **Replacement design — a hint ladder, not multiple choice**: "assistance must narrow the answer space while the player still produces the answer." Tap 1: "12 valid answers left"; tap 2: first initial "J—"; tap 3: letter blanks "J _ _ _ M _ _ _ _ _ _ _ _". Zero extra network (drawn from `candidates` minus `usedIds`); never chooses the next node, so drift can't arise. Includes a sketch `enum Hint` pure type.
- Closing line: "does an enthusiast who is stuck actually want a hint, or do they want the run to end so they can start a fresh one? Test that with two people before writing code — **this whole document exists because a mode was built before that question was asked.**"

**`94153f8` 14:35 — "Start versioning at 0.4.0"**
- `MARKETING_VERSION` had been Xcode's default 1.0. CHANGELOG.md created (Keep a Changelog + SemVer); the 0.4.0 entry reconstructs the **19 pre-versioning commits** (Jul 9 → Jul 25). `Config.appVersion/buildNumber/versionString` read from the bundle; Settings shows it.
- Original roadmap (5 milestones before 1.0): **0.5.0 design overhaul, 0.6.0 login/session, 0.7.0 social (Pass & Play), 0.8.0 leaderboards, 0.9.0 share images + TMDB proxy.** "0.4.0 places today past prototype (the engine, providers, matching, collection and tests survive a redesign) while leaving honest room ahead."
- How the number was chosen — from memory note `derive-claims-from-evidence.md` (dated 2026-07-25): Abraham pushed back twice on proposed versions: *"technically what we have wouldn't be 0.1.0"*, then *"are we sure on 0.9.0, how do we determine that?"* The useful answer was to "expose the reasoning framework and let him supply the product input (his pre-launch feature list is what made the version number derivable)." → 5 workstreams before launch, each a minor version → 0.4.0 today. (The exact order Claude proposed 0.1.0 then 0.9.0 is *(inferred)* from the quote order in the note.)
- Visual design recorded as **placeholder** in CLAUDE.md and ARCHITECTURE.md.
- Roadmap traps written down early: `ImageRenderer` silently drops `AsyncImage` content (fetch art into memory first); icon renders must be alpha-free; every color needs light+dark; and "the deployment target is iOS 26.2, which is near-unshippable as-is."

**`03d34bf` 14:42 — "audit the deployment target, open up the chain metaphor"**
- The "near-unshippable" claim was challenged (memory note: "a severity claim about the iOS deployment target being 'near-unshippable' that I'd asserted without checking adoption or auditing the APIs"). **Audit: build at successively lower targets.** True floor = iOS 17.0, blocked only by `@Observable`; 17.0 and 18.0 both build clean. "26.2 was never a requirement — just Xcode's default at project creation." The overstated claim was replaced with findings.
- 0.5.0: "the chain metaphor itself is open" — stack of cards a live candidate (app already fetches art; cards suit share images; cost = vertical room vs docked keyboard); "chain" stays domain vocabulary regardless.

**`6ce9429` 14:52 — Lower deployment target to 18.0**
- Why 18.0 not 17.0: "17.0 buys almost no extra devices (17 and 18 support the same hardware), only users who declined two updates, while 18.0 keeps iOS 18 APIs available." "Current major plus one back" since Apple jumped 18 → 26.
- Verified on a real iOS 18.0 simulator and 26.x — 42 tests pass on both. Gotcha: "xcodebuild rejects an 18.x destination while the project declares a 26.2 minimum, so a build-setting override alone couldn't prove it."
- macOS/visionOS left at 26.2 (visionOS not installed locally, couldn't verify).
- Changelog later frames it as "roughly doubling the installable audience at no code cost."

**`b7d8d99` 23:39 — doc-set map** in CLAUDE.md + ARCHITECTURE.md (four docs now; ROADMAP wasn't mentioned until line 524 of ARCHITECTURE). Audit: removed Assisted symbols appear only in ASSISTED-MODE.md; all four recovery SHAs resolve.

**`94e35f1` 23:47 → `b88b903` 23:49 — the card direction, decided then un-decided two minutes later**
- 94e35f1 (from "a visual reference"): 0.5.0 replaces the tile stack with a **stacked list of cards** — rear cards collapsed to a title bar, front card expanded with art + pill metadata chips. Notes: ChainStack's IA already matches (tile→card upgrade, lower risk); hard constraint = vertical room vs 44pt bars; chips must not leak a future answer. Also put the "placeholder" warning at the UI section and ChainStack entry so a *partial* read (grep/offset) can't miss it.
- b88b903: "I recorded the stacked-card direction as settled; it isn't — it's still being played with." Downgraded to "leading candidate"; filmstrip / linked thread / constellation restored as live options. *(Inferred: Abraham corrected the framing between the two commits.)*

### 2026-08-08 — Growth catalog, motion skills, and (per the docs) the roadmap re-cut conversation

**`b529fd5` 11:58 — docs/GROWTH.md**
- "An external research dossier on @maubaron's app-growth playbook (Prayer Lock, solo, TikTok-only) reconfigured against this codebase as an engineering backlog rather than a marketing read."
- Three findings: (1) **every share is a dead end** — `shareSummary`/`shareText` have no URL, and the grid isn't comparable because every run starts from a different seed ("🟦🟪🟦🟪 conveys a length and nothing else"); (2) **no wire format** — `Person`/`Movie`/`ChainNode` aren't Codable; the Pass & Play codec is shared infrastructure for four plays; (3) `startGame(with:)` is a single clean entry point — daily, challenge link, rematch, received chain are the same call.
- Three bets: **A — the daily (Wordle path)**, **B — the challenge loop**, **C — the content factory** (chain→video Mac tool). "Framed as options, not a plan."
- §8 hard gate, the TMDB rate math: cold launch = **24 concurrent requests** (5 discover pages + 1 page + credits for 18 films) vs ~50 req/s key → **~2 cold launches/second saturates it**; "a video driving 10K installs in an hour is ~2.8 launches/s — over the line." Retries (3× pool, 3× per turn) amplify; failure surface = home stuck on "Dealing…". Cheap fix: disk-cache the pool with a TTL; real fix: TMDB proxy.
- Content licensing: TMDB doesn't own posters/stills; "make the app's own screen the creative."
- "Every code claim, file reference and arithmetic step in the doc was verified against the tree at 0.4.0."

**`c2a2d90` 12:00 — three motion/design skills checked in** (`.claude/skills/`): `apple-design`, `find-animation-opportunities`, `animation-vocabulary`. Reason: 0.5.0 is the design overhaul and the chain treatment is open; "keeps that work from drifting into over-animation." Caveats: recipes are web (CSS/Framer Motion), need translating to `Theme.Motion` + SwiftUI springs; `find-animation-opportunities` references sibling skills not checked in (dangling).

**The re-cut decisions (dated 2026-08-08 in the docs, committed 2026-10-21 in f812f1b)** — ROADMAP: "This plan was re-cut on **2026-08-08** after a planning conversation…" and "Settled 2026-08-08, so they don't get re-litigated mid-build." DAILY-CHAIN.md: "came out of a design conversation on 2026-08-08." *(Inferred: the conversation happened Aug 8 alongside GROWTH.md; the docs weren't committed until Oct 21 — no transcript survives to say whether they were drafted then or reconstructed later.)* Content is under Oct 21 below.

### 2026-08-09 → 2026-10-20 — gap

No commits for ~74 days. Nothing in the sources says why.

### 2026-10-21 — Roadmap re-cut committed; design overhaul begins (Cream Neobrutalist)

**`f812f1b` 19:20 — "re-cut the roadmap to 1.0 and add the Daily Chain spec"** (7 files, +801/−270; adds DAILY-CHAIN.md 269 lines, DESIGN-BRIEF.md 159 lines)

New milestone order (as committed here):
| 0.5.0 Foundations & safety net | 0.6.0 Design overhaul | 0.7.0 The service (TMDB proxy first) | 0.8.0 Accounts | 0.9.0 Daily Chain | 0.10.0 Friend groups | 1.0.0 Launch |
(Later, outside this era, the design overhaul actually landed first and took 0.5.0; the changelog notes "the version follows the work.")

"The decisions this plan rests on" (settled 2026-08-08):
- **Launch scope is the full loop** — endless + Daily Chain + friend groups before the App Store. "The goal is to own the complete cycle — publish, tracking, auth, backend, devops — not to get to market fastest."
- **No release before launch** (open question whether the pre-launch TestFlight round still stands).
- **Global leaderboards dropped permanently.** "An AI can produce a valid long chain on request, and our designed anti-cheat (server-side re-validation) only catches *fabricated* chains, not *assisted* ones. A number from a stranger can't be trusted, so we don't build anything whose value depends on a stranger believing one." Precedent: NYT's April 2025 Wordle leaderboard — friends only, invite link, no global ranking.
- **~5–10 hours a week → 6–9 months.**
- Pass & Play moved to after 1.0 (with Universal Links + web fallback, so each handoff is an install path rather than a retention-only feature).

Foundations milestone findings: "**zero logging statements and 18 places where an error is caught and discarded**" (incl. the home stuck on "Dealing…" forever); **no remote — "the project exists on one laptop"**; local data has no owner (no device id). **Merge rule** decided: "Highest best score wins. Reels combine. Streak takes the longer one." Sub-rules: per-entity counters take max not sum (idempotent merge), streaks stored as a set of completed days, two results same day → highest wins.

Design overhaul section: chain treatment candidates — cards (leading), filmstrip, linked thread, constellation. **"Decided 2026-08-08: prototype two or three of them in code and judge them running on a device."** "Any prototype that ignores the keyboard is not a prototype of this screen." App name flagged as a separate, larger (ASO) question.

The service: one deployment, three jobs (proxy → publishable content → accounts/groups). Proxy first because "nobody's data is at risk if it falls over" — learn hosting/secrets/caching/deploys there. Content pipeline: generator script → queue → **human approves** → immutable publish → CDN; idempotent generation. "Config must never be able to brick the client."

**DAILY-CHAIN.md** (specced, not playtested, not built): two actor names + par, same for everyone; build the **longest** chain that still reaches the target before one round clock (start at ~3 min) stops; one attempt; not connecting = no score ("Didn't connect — built N", modelled on Wordle's X/6). "The game is not racing to the target. It's seeing how far out of your way you can go and still get home before the clock stops." Example: Tom Hanks → *Saving Private Ryan* → Matt Damon → *We Bought a Zoo* → Scarlett Johansson (par 4). Generation walks a path backwards (guarantees solvability, par for free) applying the familiarity standard **at every step** (the Assisted-mode drift lesson); can't run on-device because devices would diverge ("the fatal one"). Not shortest-path ("Six Degrees of Kevin Bacon is lookupable, solved… Longest produces a distribution"). Open risks: padding, stranding ("I blew it" vs "that was unfair"), whether extend-or-bank is a real decision at all.

**DESIGN-BRIEF.md**: written "for Figma / a fresh redesign" — product, rules, screens and constraints, *deliberately* silent on palette/type/shape/chain/motion. Hard constraints: portrait iPhone, check every play layout with the keyboard occupying the bottom ~40%, actor vs movie glanceable, light+dark, Reduce Motion, no autocomplete, opaque icon, TMDB attribution reachable, 20+ node chains.

**`871ea38` 19:32 — "Prototype the Cream Neobrutalist design and a card chain"** (branch `feature_cream-neobrutalist`; labelled "0.6.0 prototype" at the time)
- Tokens retuned: cream canvas, white surfaces with **2pt ink border + hard unblurred offset shadow** (2pt chrome / 4pt primary), **coral** CTA, **blue actor / yellow movie** ("the most colour-blind-safe pair" — purple dropped), dark variants with cream borders on charcoal. New colors Coral, MovieYellow, Shadow; MoviePurple deleted.
- `.neoSurface` modifier (fill + border + hard shadow + pressed state collapsing the shadow) shared by buttons, cards, inputs.
- `ChainCards.swift`: **hero card** for the newest link (art, kind chip, display-type name) + **two compact cards** + "+N earlier". `maxEarlier = 2` because "Two is what fits on an iPhone 16 with the keyboard docked while keeping the '+N earlier' marker on screen; a third gets clipped off the top." Newest sits at the bottom, nearest the input.
- **Settings → Chain style** toggles back to the tile stack for side-by-side device comparison — exactly the "prototype and judge on device" decision.
- Serif = system New York "standing in for Fraunces" (Fraunces bundled later, outside this era).

**`e94550e` 19:41 — unify typography**: three voices — serif display/heading with italic flourish, two-size sans body, one tracked uppercase label (`metaLabel()`, replacing seven ad-hoc recipes). Movie years as italic flourish via shared `NodeName` (instead of parentheses). Game-over recap reuses the compact chain cards ("the chain looks like one object from first link to last"); personal best and Reel link become cards; hairlines, soft shadows and the Reel's gradient name scrim removed.

**`5f8b60a` 19:48 — every figure in the serif numeral**: `Theme.Font.numeral` on the timer, floating gain, hero card position, best/Reel stats, home Reel count, Reel counts/chips. "Before, the same kind of number changed voice with its size." Buttons/labels/body stay sans "as the spec has them." *(The commits refer to "the spec" — a Cream Neobrutalist design spec; it is not in the repo at 5f8b60a, so its source is unknown from git.)*

End-of-era state: version still 0.4.0; Unreleased changelog lists the prototype + the 18.0 deployment target change. Everything in this block was released as **0.5.0 on 2026-10-22** (next era).

---

## Decision log (this era)

| Date | Decision | Rationale | Source |
|---|---|---|---|
| 07-10 | No autocomplete; fuzzy-match free text against the bounded candidate set (threshold 0.72) | Autocomplete spoils recall; a small known answer set makes spelling tolerance safe | bca93e8, CLAUDE.md |
| 07-10 | Engine/provider split + offline StubProvider | Playable with no key/network; later proxy = new provider, not engine change | bca93e8 |
| 07-10 | TMDB token at runtime from gitignored plist | Never commit the credential | bca93e8 |
| 07-10 | Pause the turn clock across candidate fetches | Slow fetch mustn't end the game on an in-time answer | bca93e8 |
| 07-10 | CLAUDE.md lean, ARCHITECTURE.md deep | Docs are every session's memory; keep current | 8d1ce43, memory note |
| 07-10 | Roman numerals → Arabic in normalize (round-trip validated) | "3" scored closer to "ii" than "iii" | 9c55bd1 |
| 07-10 | Identity = TMDB id, never name; rank stubs out | Same-name stubs gave empty filmographies; homonyms must survive | 9c55bd1 |
| 07-10 | Token + owned-component design system | Re-skins become Theme/Components changes | d51864e |
| 07-11 | Scoring = 10 + secs left + obscurity (≤30); length stays headline | Reward decisiveness and deep knowledge | c057968 |
| 07-11 | Chime cycles within one octave | Endless climb was shrill on long chains | c057968 |
| 07-11 | Monotonic `generation` token on async loads | Stale cast from a quit game leaked into a new round | c057968 |
| 07-11 | Drop "Self" credits | Making-of appearances aren't roles | c057968 |
| 07-11 | Cut the serpentine SnakeChainView | Cluttered | c057968 |
| 07-11 | NYT/Connections editorial skin; remove flame/ring/confetti | Calm puzzle-page register (later judged placeholder pastiche) | dabe62e |
| 07-11 | Reel logs only chains ≥2 links; counts, no rarity; JSON not SwiftData | "Successful combinations only"; small bounded data | a99333e |
| 07-13 | iPhone portrait-only | Docked keyboard can't fit landscape | af4ca14 |
| 07-16 | Deal pool = most-voted films + their top-billed actors | Trending surfaced obscure names; recognizability matters | 439c2e3 |
| 07-16 | Play-first "Start with ⟨name⟩"; search opt-in | Lead with a dealt start | 439c2e3 |
| 07-16 | TMDB attribution in Reel; Reel pill always reachable | TMDB API terms | 439c2e3 |
| 07-16 | Only ship motion that survives a frequency/purpose gate | Restraint | 7fc5762 |
| 07-24 | Pass & Play via deep link; shared chain never writes solo best; Reel logs only own links | No backend needed; honest stats | 582750c |
| 07-24 | Global leaderboards in the sociality plan | Top tier of a hyper-local→global spectrum | 582750c (reversed 08-08) |
| 07-24 | Build Assisted (3-option) mode with split records | Help newcomers | ef2603b, 3af5d28 |
| 07-24 | 12s request timeout, 3 silent retries, manual Retry | Hung fetch froze turns (both modes) | 98c0a7d |
| 07-25 | FamiliarityGate at every step (top-billed 6 / vote_count ≥4,000) | Drift: seed curated, later steps not | 190b962 |
| 07-25 | Reel logging Hardcore-only | Tapping a shown name isn't recall | 190b962 |
| 07-25 | **Remove Assisted mode**; keep retry/timeout, popularity sort, pool=5 pages, Settings | Served neither audience; code recoverable from git | 79f5d88, ASSISTED-MODE.md |
| 07-25 | Future assistance = escalating hint ladder, not selection | Narrow the answer space; player still produces the answer | ASSISTED-MODE.md |
| 07-25 | Start versioning at 0.4.0; minor per milestone; 1.0 = launch | Derived from 5 pre-launch workstreams, not by feel | 94153f8, memory note |
| 07-25 | Deployment target 26.2 → 18.0 | Empirical audit: floor 17.0 (@Observable); 18 = current-plus-one-back | 03d34bf, 6ce9429 |
| 07-25 | Cards = "leading candidate", not decided | Still exploring | b88b903 (reverses 94e35f1) |
| 08-08 | Growth = build catalog with 3 bets; disk-cache the deal pool | Shares are dead ends; launch concurrency vs ~50 req/s | b529fd5 |
| 08-08* | Launch scope = full loop (endless + daily + friend groups) | Own the complete cycle, not fastest to market | f812f1b |
| 08-08* | **Drop global leaderboards permanently**; friend groups only | AI can produce valid chains; re-validation can't prove recall | f812f1b |
| 08-08* | Pass & Play after 1.0, with Universal Links + web fallback | Bare scheme is retention-only | f812f1b |
| 08-08* | Merge rule: highest best wins, Reels union, longer streak; max not sum | Never lose player data; idempotent | f812f1b |
| 08-08* | Daily Chain = longest A→B route, one attempt, generated offline + human-approved | Win condition, comparability, reason to return; drift insurance | f812f1b, DAILY-CHAIN.md |
| 08-08* | Prototype 2–3 chain treatments in code, judge on device | Motion/density can't be judged on paper | f812f1b |
| 10-21 | Cream Neobrutalist; blue/yellow; coral CTA; hard shadows | New identity; most colour-blind-safe pair | 871ea38 |
| 10-21 | Card chain: hero + 2 compact + "+N earlier", toggle vs tiles | Fits iPhone 16 with keyboard; compare on device | 871ea38 |
| 10-21 | Three type voices; all figures serif | One voice per role | e94550e, 5f8b60a |

\* dated 2026-08-08 in the docs; committed 2026-10-21.

## Story material

- **The founding insight**: no autocomplete because it "would spoil a recall game" — and the bounded candidate set is what makes forgiving spelling safe. "John Malkovic" works.
- **Mission: Impossible III bug**: edit distance thinks "3" is closer to "ii" than "iii". Fix had to stay round-trip safe so *Malcolm X*, *X-Men*, *I Am Legend* didn't become numbers.
- **"School of Rock" vs its making-of featurette** — and the related finding that TMDB counts talk-show "Self" appearances as credits.
- **The chime that climbed forever** — synthesised pentatonic tones; capped to one octave because long chains got shrill. No audio assets at all.
- **Gamification built and largely torn out in 12 hours**: flame tiers, timer ring and streak flame at 00:57 on Jul 11; deleted by 13:12 for "no flame/confetti/radial-heat." Plus the SnakeChainView that never made it either.
- **The stale-load race** — "a `phase == .playing` check alone can't catch it, because the new game is also playing."
- **Codex as adversarial reviewer** from week one; it caught accessibility on invisible intro controls and the stale-search buzz.
- **Restraint pass**: ran Emil Kowalski's find-animation-opportunities skill and shipped only 4 beats; the score bounce delayed 450ms to clear the screen push.
- **Recognizability as a data problem**: TMDB "trending" gave strangers; `vote_count.desc` gave household names. Actors derived from 18 films × 5 top-billed.
- **Assisted mode: 4 commits, ~37.5 hours, one playtest.** Quotes: "It worked. The problem was never that it was broken." / "the hard part isn't recognizing a name, it's knowing who was in what" / "tapping from a list deletes the act of recall that IS the accomplishment" / "A middle mode that dilutes the core loop without solving the newcomer's real problem has no audience."
- **Drift**: the Bollywood star with one Hollywood credit. "Ordering a set that is 95% unfamiliar still yields something unfamiliar." "The game curated recognizability for the seed (step 0) and then abandoned it for every step after."
- **Asymmetry of responsibility**: "The moment the game *offers* the node, the game owns where the player ends up." This lesson resurfaces in the Daily Chain generator and the onboarding demo ("safe because nothing is generated").
- **The question that should have come first**: "this whole document exists because a mode was built before that question was asked."
- **The good parts outlived the failed feature**: the retry/timeout fix for a freeze that also hit Hardcore came out of Assisted-mode playtesting.
- **Version-number pushback**: "technically what we have wouldn't be 0.1.0"; "are we sure on 0.9.0, how do we determine that?" → 0.4.0 derived from the remaining workstreams. A working-style lesson about deriving numbers rather than picking them by feel.
- **Deployment target**: 26.2 was just Xcode's default. Claude called it "near-unshippable" without checking; the audit found the real floor (17.0, only `@Observable`); chose 18.0. Neat gotcha: xcodebuild won't even run an 18.x simulator while the project says 26.2.
- **Decided, then un-decided in two minutes** (94e35f1 23:47 → b88b903 23:49): "I recorded the stacked-card direction as settled; it isn't."
- **Leaderboard reversal**: global boards were in the July 24 sociality plan; on Aug 8 they were "dropped permanently" because "a number from a stranger can't be trusted" in a world where an AI can produce a valid chain. NYT's friends-only Wordle leaderboard is the precedent.
- **Numbers**: 30s turns; threshold 0.72; base 10 + up to 30 speed + up to 30 obscurity; actor bias 0.6; recent window 8; 18 source films × 5 top-billed; pool 2 → 5 discover pages (~40 → ~100 films); 12s timeout × 3 attempts; Assisted: 3 options, −8s per wrong tap, top-billed 6, vote_count ≥ 4,000; 24 requests per cold launch vs ~50 req/s ≈ 2 launches/s; 10K installs/hour ≈ 2.8 launches/s; 18 swallowed-error sites, 0 log lines; 5–10 hrs/week → 6–9 months; tests 12 → 58 → 42.
- **"The project exists on one laptop"**: no remote as of the Oct 21 roadmap.
- **Daily Chain pitch line**: "The game is not racing to the target. It's seeing how far out of your way you can go and still get home before the clock stops." And: "Designing the failure out of the game is the wrong goal; making it unremarkable is the right one."
- **The 74-day gap** (Aug 8 → Oct 21), then three design commits in 28 minutes (19:20–19:48).
- **The model trailers** change over the era (Opus 4.8 → Fable 5 → Opus 5 → Opus 5.5).

## Retroactive screenshot candidates

There are no screenshots from this era. Worth checking these out and capturing (with `-uiDemoChain` / `-uiDemoGameOver` where available, from d51864e on):

| SHA | Screen | Why |
|---|---|---|
| bca93e8 | Seed, Play, Game Over | The very first stock-SwiftUI version (NavigationStack/List) |
| c057968 | Play screen with timer ring + streak flame; branded seed landing | The short-lived gamification look, gone 12 hours later |
| c057968^ (d51864e) | Play screen | Last state with the serpentine SnakeChainView, if it renders |
| dabe62e | Play (ChainStack tiles, docked keyboard), Game Over | First NYT/Connections skin, blue/purple tiles |
| a99333e | Your Reel sheet | First collection UI (hero total, regulars, poster grid) |
| 203e8cb | Seed cold-launch intro (record video) | The once-ever intro animation |
| af4ca14 | Home with actor/movie segmented toggle + live search | Hero+search home before "deal a start" |
| 439c2e3 | Home "Start with ⟨name⟩" + Shuffle; app icon | Play-first home; first app icon |
| 190b962 | Assisted mode play screen (3 option tiles with thumbnails), home Hardcore/Assisted toggle | The removed mode at its most refined — key for the postmortem post |
| 79f5d88 | Settings sheet | What survived from Assisted |
| 5f8b60a (Chain style = cards) vs same SHA (Chain style = tiles) | Play screen side by side | The on-device comparison the roadmap called for; first Cream Neobrutalist look |
| e94550e / 5f8b60a | Game Over recap with compact cards; Reel sheet | Type-system unification before Fraunces |
