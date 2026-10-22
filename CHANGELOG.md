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
| **0.5.0** | [**Design overhaul**](docs/ROADMAP.md#050--design-overhaul) — the real visual identity: Cream Neobrutalist, Fraunces, the chain as cards (motion re-tune follows as 0.5.x) |
| 0.6.0 | [**Foundations & safety net**](docs/ROADMAP.md#060--foundations--safety-net) — backup, logging, crash reporting, build pipeline, device id + merge rule, deal-pool disk cache |
| 0.7.0 | [**The service — TMDB proxy first**](docs/ROADMAP.md#070--the-service) — takes the shared key out of the app and caches it |
| 0.8.0 | [**Accounts**](docs/ROADMAP.md#080--accounts) — Sign in with Apple over the device id, with a merge that doesn't clobber |
| 0.9.0 | [**The Daily Chain**](docs/ROADMAP.md#090--the-daily-chain) — one puzzle a day: longest route from A to B ([spec](docs/DAILY-CHAIN.md)) |
| 0.10.0 | [**Friend groups**](docs/ROADMAP.md#0100--friend-groups) — invite-code groups, no global ranking |
| 1.0.0 | [**Launch**](docs/ROADMAP.md#100--launch) — share images + links, onboarding demo, store listing |

Until 1.0, breaking internal changes land in minor bumps. The order above is a plan,
not a contract — if milestones land out of order, the version follows the work. (It
already has: the design overhaul landed before Foundations and took 0.5.0.)

## [Unreleased]

### Added

- **Chain style → Deck, now the default.** The chain as a physical pile: each new link is
  dealt in from below and pushes the previous card back (smaller, higher, shadow
  sinking), earlier cards peek out with their names, and the oldest tucks under the
  pile. Nothing cross-fades. Cards and Tiles stay available in Settings → Chain style
  as a player preference (the setting is no longer labelled a prototype). The pile fills whatever
  height the screen can spare above the keyboard — named peeks while they fit, then
  card edges for the pile's thickness.
- **Holographic stickers.** The dealt start wears a foil "START" flag instead of a
  label, and a new best is a foil sticker slapped onto the score card ("New best! —
  was 7") instead of a green pill. It lands lifted, smooths down to a slightly peeled
  corner, and its foil shifts colour and catches the light as you tilt the phone.

### Changed

- **Running out of time now has a moment.** When the clock hits 0 the play screen
  holds for half a second — the input greys out, the pile sags and settles, and the
  miss buzz fires — before game over slides in. It used to slide away the instant
  the clock ran out, so a run never visibly *ended*. Quitting still leaves at once.
- **Your Reel's growth is visible.** Back on the home screen after a run, the Reel
  pill's count rolls up from the number you last saw to the new total, with a small
  bump, instead of already showing it.
- The "you were one away" card now deals in with the chain on game over rather than
  sitting still while everything around it arrives, and the Retry button cross-fades
  in and out of the input's place after a failed load instead of swapping instantly.
- **Chain cards no longer say "Link N".** The score already counts links; the number
  read like a form field. Only the start is marked, with its sticker.
- **The first card's art is already there when a game starts.** The home screen
  pre-fetches each dealt start's poster or headshot, so it no longer loads in (and
  slid against the screen push) as the play screen arrived. Art that does stream in
  later now "develops" — a quick blur-to-sharp fade scoped to the image itself.

- **Network responses are now really decoded off the main thread.** The decode
  helper was `nonisolated async`, which under Approachable Concurrency runs on the
  caller's actor — so every TMDB response, including the ~24 that build the first deal
  and big filmographies mid-run, was being parsed on main. It's `@concurrent` now,
  which should take the edge off the hitch when a link lands and on cold launch.
- **The first deal arrives sooner and costs fewer requests.** A Shuffle tap (or a
  resume) during the first pool load used to start a second, identical load; callers
  now join the one in flight. The five most-watched pages also load in parallel
  rather than one after another.
- **The project builds in the Swift 6 language mode**, so data races are compile
  errors rather than unchecked. It surfaced one real issue (a main-actor value read
  inside a `@Sendable` animation closure), now fixed.
- **Tests moved to Swift Testing** — parameterized where they were tables, and the
  engine tests use their own `UserDefaults` suite instead of writing a best into the
  simulator app's real records.
- The turn clock ticks against fixed deadlines, so scheduling slack no longer
  stretches a 30-second turn.
- **A landing link now hands off visibly.** When you add a link, the previous hero card
  shrinks up into its compact slot rather than fading out while a copy fades in, so the
  chain reads as one object growing. The landing spring is calmer (less wobble across
  the whole stack on every link), and poster art fades in instead of popping.
- **The timer bar drains continuously.** It used to step once a second (move for a
  quarter-second, then sit still); it now flows, and snaps full at the start of a turn
  instead of sliding back. The header's seconds now actually roll.
- **A miss no longer squeezes the chain.** The error message takes over the next-up
  hint's line instead of adding a row above the input, and hands it back as soon as you
  start typing again. The shake settles instead of stopping dead.
- **The first turn's 30 seconds start when the keyboard is up**, not when the screen
  starts sliding in — the push and the keyboard used to cost about a second.
- **Game over plays as one sequence**: the screen lands, then the score and "a new
  best" pill pop together, then the chain deals in, rather than the recap staggering
  in underneath the slide.
- Presses share one fast timing (and gentler scale) across every button; the "+N"
  gain pops in before it drifts away; Reel art fades in on an ease-out.

### Fixed

- **A second identical miss didn't shake or buzz.** The reaction keyed off the error
  text, which doesn't change when two misses in a row produce the same message.
- **Reduce Motion gaps.** The wrong-answer shake and the floating "+N" ignored the
  setting; the shake is now a red flash of the field's border and the "+N" fades in
  place. The Shuffle deal and Reel art kept no transition at all under it; they now
  cross-fade.

- **Sequel matching on Turkish-locale devices.** Answers were case-folded in the
  device locale, which turns "III" into dotless "ııı" — no longer a Roman numeral — so
  "mission impossible 3" stopped matching. Folding is now locale-independent.
- **A stray celebration after a fast "Play again".** The new-best haptic waited out
  the screen push in a task nothing cancelled, so leaving within half a second still
  fired it on the next screen.

## [0.5.0] — 2026-10-22

The visual design overhaul. The placeholder NYT-Games look is replaced by a real
identity — **Cream Neobrutalist**: a cream canvas, white cards wrapped in a 2pt ink
border with a hard offset shadow, one coral call-to-action per screen, Fraunces for
display type and every number, and SF for body and labels. Alongside the look, the
game settled two definitions it had been fudging: what a *link* is, and what counts as
your *best*. Motion is next and lands as 0.5.x.

### Added

- **Cream Neobrutalist, the new visual identity.**
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
- **Fraunces is the serif.** It's bundled as four static cuts, about 320KB with the
  full character set, so accented and extended-Latin names render in the same face.
  Body text, buttons and labels stay in SF, the iOS-native counterpart to the spec's
  Inter. The license credit is in Settings.
- **The remaining spec details.** Secondary text uses the spec's solid muted grey
  instead of iOS's translucent one, and errors use its red. The coral button darkens
  while held. Pressing anything moves it 1pt with the shadow collapsed. Every border
  is 2pt. The timer is the spec's thin 6pt progress bar. Screens use the 24pt gutter.
  Labels come in the spec's two sizes, and headings pair a roman phrase with an
  italic word ("Your *regulars*"). The Reel and Settings sheets get a cream bar with
  an ink rule, and Settings uses a bordered segmented control.
- **A leaner Reel.** It used to state the actor and movie counts three times: in two
  big count cards, in the filter tabs, and again in a header above the grid. Now the
  total sits at the top and the per-kind counts live only in the tabs. "Your
  *regulars*" lost its "most logged" caption, which said the same thing, and its two
  cards now always match in height.
- **A balanced home screen with a coral start button.** The start button was ink on
  an ink shadow, so the shadow merged into the card and it read as shifted. The
  screen also had no coral, though coral marks the main action everywhere else. It's
  coral now, like "Play again". The controls form one group, with the search link
  tucked under Shuffle instead of floating at the bottom. The title sits a little
  lower, so the whole composition centers on the screen with the start button just
  below the middle, where the thumb rests.
- **One summary card on game over, and one vocabulary.** The "Time's up" / "Chain
  ended" label is gone, since the screen itself says the run is over. A single card
  leads with this run: the link count as the hero, with "links · 179 pts" under it.
  Below a rule sit the personal best and the Reel in small, quiet type; the best is
  hidden on a new best, where it would only repeat the run. The words are fixed
  app-wide: a *chain* is a whole run, a *link* is one correct answer, and the score
  counts links. The dealt start isn't a link, so the recap marks it with a flag and
  numbers the links from 1, matching the score instead of running one past it. The
  play screen's newest card reads "Link 4" (or "Start") on the same rule.
- **"4 links" reads as one figure.** The unit used to sit on its own line between the
  number and the points, so "links" read like a separate stat. It now sits on the
  numeral's baseline, with the points on their own line beneath, on both the play
  and game-over screens.
- **You find out the moment you pass your best, not just at the end.** On the answer
  that takes a run one link past the record, the score swells, dips and settles, the
  phone gives the celebration haptic, and a brighter two-note chime replaces the usual
  one. For the rest of the run the score stays green and the points line reads "96 pts
  · *new best*", with no new shapes on a screen short of room. It fires once per run,
  never on a first game, and VoiceOver announces it. Reduce Motion keeps the colour
  and drops the bounce. Previously the only signal came on the game-over screen.
- **One record, defined.** The best run is the one with the most links, and points
  only break a tie. Before, the best link count and the best points total were kept
  separately, so "18 links · 848 pts" could pair two different games. Now both are
  written together and always describe one run. A run with fewer links but more
  points than ever is no longer a record of any kind. Existing saves keep their
  numbers until the next record overwrites both.

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

