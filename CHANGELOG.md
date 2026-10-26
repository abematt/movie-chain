# Changelog

All notable changes to **Unspool** (called Movie Chain until 0.6.0) are recorded here.

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
| **0.5.0** | [**Design overhaul**](docs/ROADMAP.md#050--design-overhaul) — the real visual identity: Cream Neobrutalist, Fraunces, the chain as cards (motion re-tuned in 0.5.1) |
| **0.6.0** | [**Unspool**](docs/ROADMAP.md#060--unspool) — the rebrand: name, two-circle icon, wordmark, the home as the first turn |
| **0.7.0** | [**Ground & Object**](docs/ROADMAP.md#ground--object--the-10-look) and the first [**foundations**](docs/ROADMAP.md#070--foundations--safety-net) — the 1.0 look; analytics, device id, deal-pool disk cache, the chain link format (logging, crash reporting and the build pipeline follow) |
| 0.8.0 | [**The service — TMDB proxy first**](docs/ROADMAP.md#080--the-service) — takes the shared key out of the app and caches it |
| 0.9.0 | [**Accounts**](docs/ROADMAP.md#090--accounts) — Apple, Google or email one-time code (Supabase) over the device id, with a merge that doesn't clobber |
| 0.10.0 | [**The Daily Chain**](docs/ROADMAP.md#0100--the-daily-chain) — one puzzle a day: longest route from A to B ([spec](docs/DAILY-CHAIN.md)) |
| 0.11.0 | [**Friend groups**](docs/ROADMAP.md#0110--friend-groups) — invite-code groups, no global ranking |
| 1.0.0 | [**Launch**](docs/ROADMAP.md#100--launch) — share images + links, onboarding demo, store listing |

Until 1.0, breaking internal changes land in minor bumps. The order above is a plan,
not a contract — if milestones land out of order, the version follows the work. (It
already has: the design overhaul landed before Foundations and took 0.5.0, and the
Unspool rebrand was inserted as 0.6.0, and Ground & Object shipped in 0.7.0 alongside the first foundations.)

## [Unreleased]

### Added
- **A daily start for everyone.** Each local day has one start, the same on every phone,
  drawn from a fixed hand-picked list (`DailyStart`), and the home leads with it
  ("Daily #12") until it's played; "Deal again" still deals randomly, and a Today pill
  goes back. One attempt: it's used up when the run starts, so quitting doesn't buy a
  retry. The share card and image say "Unspool #12". Until now no two players ever
  played the same start, so the share card had nothing to compare. The list is still a
  placeholder.
- **Settings links to the website**: the privacy policy (playunspool.com/privacy), a
  "Suggest a feature" row that opens the feature board, and a Contact row that writes to
  hello@playunspool.com. The App Store needs the privacy policy reachable from the app,
  and players were never told where to send ideas.

### Changed
- **TMDB requests go through Unspool's own service** (Supabase), not straight to TMDB.
  A proxy function holds the TMDB token and caches responses, so one fetch of the deal
  pool, a cast or a filmography serves every player. Every phone used to make its own
  requests against one shared key, which capped how many people could start at once;
  and the token no longer has to ship inside the app.
- **TMDB attribution uses the terms' exact wording, and Settings → About shows it too.**
  The app carried the FAQ's shorter line; the API terms (§3) require "uses TMDB and the
  TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB", shown
  prominently. It matters before App Review, where TMDB apps get asked about their rights.

## [0.7.0] — 2026-10-26

Unspool gets its 1.0 look, **Ground & Object**: a paper ground, objects with an ink edge
and a hard side, the colour moved into the answer dock, game over on Night with the run
as a coin stack you can open with a finger, and a share card. Underneath, the first of
the foundations: product analytics, a device id, a home screen that can't hang on
"Dealing…", a deal pool saved between launches, and the link format chains will be
shared in. Logging, crash reporting and the build pipeline follow.

### Added
- **Product analytics (PostHog).** Until now there was no way to know where runs end,
  how long turns take, what people try, or whether anyone comes back. The app sends
  a few events with rich properties, about 47 a session, so the 1M-event free tier
  holds roughly 700 daily players:
  - `run_started`: the seed (TMDB id), dealt or picked, deals before starting, and
    time on the home and previous game-over screens.
  - `link_landed`: what was shown, what was typed, the misses before it, think time
    and how long the turn's answers took to load.
  - `run_ended`: the outcome, run and play time, average and slowest answer, wrong
    guesses, retries, the turn it ended on and the near-miss.
  - `card_viewed` (one per Reel card looked at: which, how long, flipped, dragged)
    and `reel_closed` (the visit: time, cards, flips, filters).
  - `turn_load_failed`, `share_tapped`, and PostHog's app opened/installed/updated.

  Screen times ride on the event that ends the screen, so there are no screen
  events. Typed text is cut to 60 characters. Nothing else is captured: no
  autocapture, screen views, replay, surveys or flags. Views call one `Telemetry`
  object and the engine only records plain facts about each turn, so `GameEngine`
  stays pure and tests send nothing. Development builds carry `debug_build`.
- **A stable device id**, made on first launch and used as PostHog's anonymous id, so
  the events and a future account (0.9.0) agree on who the player was.
- **"Share usage data" in Settings**, on by default, which stops all sending when off.
- **`deal_failed` analytics**, so a home screen that couldn't deal shows up in PostHog
  instead of as a player who silently left.
- **Game over's coin stack opens under a finger.** Drag up and down the stack: the coins
  above the one you're on lift away, so its face shows, and a film's label gains its
  year, which brings back the one thing the old per-link list showed. A tick marks each
  new coin, and letting go settles the stack. Coins can never pass through each other
  and only the top and chosen coins show a face, so a half-lifted coin doesn't read as
  two discs. Modelled on the stack figure in lucasmarkes/hairline.

### Changed
- **Ground & Object begins: new type and colour foundations.** Cream Neobrutalist read
  as generic and sat too close to Claude's own ivory, serif and clay. The app is now set
  in Archivo (names and sentences, with condensed black for numbers and actions) and
  JetBrains Mono caps for chips, with no serif and no italics; the cream ground becomes
  paper, coral is gone (the call to action is an ink slab), and dark mode is a dim room
  rather than a black one, so edges and sides keep their weight. Objects get a hard ink
  side straight below them, never a blur, and a press sinks them onto it.
- **Home and Play put the colour in the dock.** The ground stays paper; the panel you
  act in is filled with the kind you name next, yellow for a movie and blue for an
  actor, so the turn's colour is always where your thumb is. On Play the dock carries
  the prompt, and a miss takes its line instead of adding a row. The wordmark is
  redrawn in Archivo.
- **Game over is on Night, with the chain as a coin stack.** The run reads as one
  number and one object: every link a coin, actors labelled left and movies right, a
  film spool on top when the run ended on a movie. A new best is the same screen on
  the holo sky rather than a sticker. The answer you were one away from is a scroll
  away; the list of every link is gone, since the stack already names them in order.
- **Share sends a picture.** The text now travels with a 9:16 card: the count, the
  stack with no names on it, and the start to beat it from, so the dare is the image.
- **A new icon in the new colours**, the mark on paper (night in dark mode), and the
  Reel's cards stay paper in dark mode: they're printed things, the lit objects on a
  dim ground.
- **Out of film reads like the home it replaces**, with an empty spool and Reconnect
  in a night dock that says the Reel and best run are safe.
- **The deal pool is saved between launches.** Every cold launch used to fire about 24
  TMDB requests to rebuild the same most-watched pool. Now a copy less than a week old
  is dealt from with no requests at all, which spares most launches and keeps a burst
  of new players further from TMDB's rate limit.
- **A correct answer is quicker and calmer.** Each link fired five motions at once. The
  dock's colour now swaps instantly (blue to yellow tweened through a flat grey on every
  answer), the "+N" drifts off in a third of the time, the prompt cross-fades instead
  of bouncing, and colour changes ease rather than spring. The default animation is
  0.25s instead of half a second, and a lifted Reel card goes home faster than it came
  out.
- **The play screen lets the phone rest.** The START sticker's foil now holds still: it
  kept the gyro and a 120Hz frame loop running on the main thread for the whole run,
  while you typed. The timer bar slides rather than being redrawn every frame, and the
  share card is drawn once game over has settled instead of on top of the new-best
  bounce.
- **The play header leads with the clock.** The time is in ink and Quit is quiet, and
  sound and Quit have full-size touch targets.
- **The prompt points at the card instead of repeating it** ("Name an actor in it"): a
  long title used to be cut off mid-word. The home's blank and the dock's field now say
  the same thing ("a movie…"), so nothing changes as one flies into the other.
- **Game over shows there's more below.** The top of the recap (the answer you were one
  away from) peeks above Play again; before, nothing said the screen scrolled.
- **The deck's front card stands on a lighter side.** It stood on a 10pt ink slab, the
  deepest in the app, which read as a heavy black bar across the bottom of the play
  screen. It now uses the buttons' 6pt side and sinks to the small one as it goes back
  into the pile. A uniform 4pt side was tried and lost the pile's depth: the front
  card's bottom read as a doubled outline, as if it were cut off.
- **The deck's cards keep their size at small text sizes.** Their height scaled with
  the text both ways, so below the default size the card shrank while the art didn't,
  and the art ran through the card's bottom edge. They now grow with large text but
  never shrink below their default.
- **The Reel's caption reads like the home's best run**: "LOGGED ACROSS / 36 CHAINS /
  BEST RUN 13 LINKS" in condensed caps with the figures in ink, instead of the app's
  only lowercase sentence broken over three lines.
- **The dock is a square band.** Its rounded top corners were the one soft curve in a
  design of hard-edged objects; the dock is ground, so it now runs edge to edge under a
  straight ink rule, on the home, the play screen and the offline notice alike.
- **Touch and polish:** 44pt targets on the home's links, the search's back link and
  its clear button; bold icons beside the heavy caps; the search's empty state on the
  same leading edge as the rest; the Reel's dim now covers its header too, so Done
  isn't lit while a card is out; one press scale everywhere.

### Fixed
- **Large text sizes no longer break the game.** At the biggest accessibility sizes the
  deck clipped the name you were naming from, the prompt cut it off, the home's links
  broke mid-word ("DEA L…") and the coin stack read "Le…". Home, play and game over now
  follow the text size up to XXXL (the Reel and Settings still go all the way), the
  deck's cards and peeks grow with their text, Deal again and Pick your own stack when
  they don't fit side by side, and the coin stack's labels keep one size.
- **The Reel no longer says "best 1 links"**, and game over's points carry a thousands
  separator, as play's already did.
- **The home screen no longer hangs on "Dealing…".** When the pool couldn't load (offline,
  or rate-limited on a cold launch), the first screen a new player saw stayed on
  "Dealing…" with no way forward. It now deals from the last saved pool if there is one,
  and otherwise shows a no-connection screen in the app's own voice ("Out of film.")
  with one Reconnect button that stays on that screen while it retries.

## [0.6.0] — 2026-10-23

Movie Chain becomes **Unspool**: a new name, a two-circle icon and wordmark, and a home
screen that is the first turn of the game rather than a menu in front of it. The Reel's
cards became things to pick up — a lifted card tilts with the phone — and actor cards
got proper collectible fronts.

### Added

- **Actor cards look like collectible cards.** Each photo is printed in two inks, a
  deep shade and a pastel from the holo foil, and every actor keeps their own pair. A
  card's face goes from paper to that pastel (at 5 films linked) to holo foil (at 11),
  so the colour of the card is the reward. The top carries a collector number, the
  order you first linked them in, and the name sits on a plate with five dots that are
  only all full at holo. There are still no counts on the front.

- **A lifted Reel card is a card in your hand.** Pick up an actor or a film and it tips
  with the phone: the photo or poster shifts behind the face, light slides across the
  card's laminate or the frame's glass, and a holo card's foil shimmers. It comes out bigger than before, and without a hard shadow —
  under a card tipping in 3D, one never looked attached. No gyro, or holding still? Drag it with a finger, and it swings
  back level carrying the flick. It flies out and home flat, so it still lands exactly
  on its slot, and Reduce Motion keeps it still with a quiet sheen.

### Changed

- **The home screen stopped explaining itself.** "Tap the blank to start" is gone: the
  sentence already reads as the rule, and the blank nudges once for a new player. The
  best run now sits alone, centred at the bottom.

- **The holo foil is smoother and cheaper.** Stickers and holo cards used to redraw
  their foil gradients on every tilt sample; now the gradients are drawn once and slid,
  and the tilt is smoothed per display frame rather than per sensor reading, so it no
  longer steps on a fast screen. A sticker covered by the Reel sheet also stops
  running the gyro.

- **The game is called Unspool now.** "Movie Chain" described the mechanic and nothing
  else; Unspool is film coming off a reel and a chain playing out, and it's a name the
  game can own. The home-screen name, Settings, and both share texts say Unspool.
- **A new icon and wordmark.** Two overlapping circles, blue for actors and yellow for
  movies, and the ink where they overlap is the link between them: the game's one rule
  as a mark. It stands in for the "oo" in the wordmark, and the icon is the mark on a
  cream tile (with dark and tinted versions for iOS 18's home-screen styles).
- **The home screen is the first turn.** It used to be a name on a coral "Start with"
  button; now it's a sentence with a blank, "Chris Hemsworth *was in* a movie…" (or
  "Inception *starred* an actor…"), so a new player reads the rule instead of being
  told it. Tap the blank and the home turns into the play screen in place: the name,
  its chip and its photo fly down into the start card, the card assembles around them,
  and the blank settles into the answer box as the keyboard comes up. It takes about
  half a second, since you see it every run, and a soft tap on landing marks the
  moment the clock starts. The first time you open the game, the blank's arrow nudges
  once to show you where to tap. **Deal again** flicks the start away and deals a fresh one; **Pick
  your own** opens the search as before. Your best run sits in a quiet line at the
  bottom.
- **The first turn is ready when you get there.** The dealt start's films (or cast)
  are fetched while you're still looking at it, so the first answer you type is checked
  at once rather than after a load.
- **Share squares use yellow for movies.** The spoiler-free share card still drew
  movies as 🟪, a leftover from the purple of the old palette; they're 🟨 now, to match
  the game.

## [0.5.3] — 2026-10-22

Fixes from playing 0.5.2 on a real phone: sounds that went missing, a Reel that
stuttered open, the keyboard and the last run's points lingering into the next
screen, and lifting a card in and out of the Reel made clean. Two settings that had
served their purpose — Chain style and Reel cards — are gone.

### Fixed

- **Sounds stop going missing.** iOS stops the audio engine on its own — a call,
  Siri, AirPods connecting or disconnecting, sometimes a trip to the background — and
  the game only ever checked a flag it set at launch, so after the first interruption
  every chime played into a stopped engine until the app was relaunched. It now
  checks the engine itself before each sound and restarts it when needed, and warms
  it again on returning to the app so the next chime isn't late. (Silent mode still
  mutes the game, as it should.)
- **Your Reel opens smoothly.** Cards used to arrive in a cascade while each photo
  loaded separately, showing initials first and swapping to the photo whenever it
  landed — every time the Reel opened, because the image loader kept nothing in
  memory. Art now goes through a real cache (memory and disk), so a reopened Reel
  draws at once, its first screen is fetched at launch, and a card loading for the
  first time goes straight from colour to photo in one fade. The cascade is gone.

- **The keyboard is gone before game over.** It used to close only once the play
  screen was pushed away, sliding down over the game-over screen and making it jump
  as it re-laid itself out. Now it goes as the run ends — during the time's-up beat,
  or straight away on Quit, with the run ending once it's down — and the game-over
  screen no longer reacts to a keyboard at all.

- **Play again leaves the last run alone.** The game-over screen read the score,
  points and chain live from the game, and Play again resets them as that screen
  starts sliding away — so the points cross-faded to zero and lingered while it
  left. The finished run is now frozen into its game-over summary.
- **Lifting and putting back a Reel card is clean.** The card used to be handed
  between two copies of itself: on the way back it faded out in place while the
  grid's copy faded in underneath, its buttons hung on mid-screen, the colour behind
  the photo could flash through, and the returning card slid *under* the cards next
  to it. Now one card makes the whole trip, drawn above everything: it grows out of
  its slot, and on close shrinks back onto it — turning to its front on the way if
  it was flipped — while the buttons go at once and the dim clears.

### Changed

- **Smaller cards, three across.** The Reel fits half as many again on a screen.
  Cards and frames are drawn once at that size and scaled, so lifting one is a pure
  zoom — the same card brought closer — and the lifted card swaps in a sharper photo.

### Removed

- **The Chain style and Reel cards settings.** The Deck is the chain, and an actor
  card is inked at 5 films linked and holo at 11, for everyone. The Cards and Tiles
  chain styles and the Share and Plain card rules are gone, along with the
  well-known-films count that only Share used.

## [0.5.2] — 2026-10-22

Your Reel becomes a collection. Actors are playing cards earned through the films you
linked through them, movies are framed posters, and either lifts out of the grid and
turns over to show the other side of its links. Decade and genre filters narrow it
down. Not a roadmap milestone, so a patch: the minors stay reserved for them.

### Changed

- **Your Reel is now a collection.** Actors are playing cards earned through the
  films you've linked *through them*, and movies are posters hung in picture frames.
  The old "×N chains" figure only said how often someone came up; a card now says
  how well you know their work. Tap either to lift it out and turn it over: an
  actor's back lists the films you linked through them, a movie's the actors. The
  fronts carry no numbers — a card earns an inked frame and then holographic foil
  instead. How it earns them is a setting for now (Settings → Reel cards: Rank,
  Share or Plain) so the three can be compared in real play before one is kept.
  Films are never listed as missing — the Reel isn't a study sheet for the next run.

### Added

- **Decade and genre filters in Your Reel.** They narrow the movies directly, and
  the actors to those you linked through a matching film. The menus only offer
  decades and genres your Reel actually has.
- Links and genres are recorded from now on: cards already in your Reel start with
  no links, and films logged before this have no genre until they come up again.
  Existing Reels load unchanged, and none of this costs an extra TMDB request — the
  number Share needs comes from the filmography each turn already loads, and genres
  arrive on the same responses.

## [0.5.1] — 2026-10-22

The motion re-tune that 0.5.0 left open. The chain becomes a physical **Deck** by
default (Cards and Tiles stay as a setting), the start and a new best get holographic
stickers, and the play loop's feedback — the timer, a miss, running out of time, game
over — was re-timed so each moment reads as one clear beat.

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

