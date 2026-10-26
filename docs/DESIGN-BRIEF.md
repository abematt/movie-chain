# Movie Chain — design brief (for Figma / a fresh redesign)

> Purpose: give a designer or design tool enough to recreate a skeleton of the
> app from scratch, **without** inheriting the current look. Everything below is
> product, rules, content and constraints. It deliberately says nothing about
> palette, type, shape language, the chain treatment, or motion — those are the
> open questions the redesign is meant to answer.

## What it is

A recall game about movies. You build a chain that alternates
**actor → movie → actor → movie …**. Each new link has to be real: the actor
appeared in that movie. You type answers from memory into a text field. Nothing
is suggested to you — there is no autocomplete, no multiple choice, no hints
during play. Misspellings are forgiven ("John Malkovic" counts).

The pleasure is "I know this" plus the pressure of a clock. Every turn is timed.
When the timer runs out, or you can't think of anything, the run ends.

**Score** is chain length (how many links). A secondary **points** total rewards
speed and obscure picks. Personal bests persist locally. No account is needed
for anything in the core loop, ever.

Platforms: iPhone first (portrait only), iPad, later Mac/visionOS. iOS 18+.
Light and dark mode both required.

## Rules (the game engine already enforces these)

- Alternate strictly: actor, movie, actor, movie.
- Each link must be valid: the actor is in that movie's cast.
- No repeats within a run — an actor or movie can only appear once.
- One free-text answer per turn, with a per-turn countdown (currently ~30 s).
- The typed text is matched against the small set of valid answers with
  spelling tolerance. A near miss (you were close, or the answer you probably
  meant) can be shown at the end of the run.
- The run ends on timeout or on a wrong/unrecognised answer.

## The two kinds of thing

Every node in the chain is either an **actor** or a **movie**. This distinction
is real information, not decoration: the player must be able to tell at a
glance which kind each node is, and which kind they are being asked for next.
The redesign is free to encode it however it likes (colour, shape, art
treatment, layout, iconography) as long as it is legible in light and dark.

Data available for every node: display name/title, a stable id, and usually an
image (headshot for actors, poster for movies). Movies also have a release year.
Images can be absent — every design that shows art needs a no-image fallback.

## Screens and states

The app is a one-way loop: **Home → Play → Game Over → Home**. There is no
back navigation between these; each replaces the last. Two sheets can open on
top of Home and Game Over: **Your Reel** and **Settings**.

### 1. Home (before a run)

Play-first. The app deals the player a suggested starting point (an actor or a
movie) drawn from very well-known films and their top-billed casts. The player
can accept it, reshuffle for a different one, or opt in to search for their own
start. Content on this screen:

- The app name / mark.
- A dealt starting node (name, kind, optional art) with a way to **start with
  it** and a way to **shuffle** for another.
- An opt-in, de-emphasised **search for your own start** path (text search of
  actors or movies, results list, pick one).
- Entry to **Your Reel** (shows a count of things collected once non-empty).
- Entry to **Settings**.
- States: normal; *dealing* (data loading); *deal failed / offline* (needs a
  retry affordance — today this state is a known weak spot).
- First launch only: a short intro moment that explains the alternating chain in
  one beat before the controls appear. Optional to redesign, but the "how do I
  play" job has to be done somewhere.

### 2. Play (during a run)

This is the signature screen and the hardest layout problem. The **keyboard is
always up** — the text field is the primary control, docked above the keyboard
for the whole run. Everything else fits in the space that remains above it, in
portrait. Content:

- The **chain so far**, newest link most prominent. Runs can get long (10–20+
  links), so older links need to compress or collapse somehow ("+N earlier").
- A clear prompt for what's wanted next: "name a movie with ⟨actor⟩" or "name an
  actor in ⟨movie⟩".
- The **per-turn countdown**, readable at a glance without dominating.
- Current score (chain length) and, secondarily, points.
- The text input + submit.
- Feedback moments: a correct link landing (and any speed/obscurity bonus), a
  wrong or unrecognised answer, the timer getting low.
- Error state: a data load failed and the turn can't start — show a **Retry**
  instead of the input.

### 3. Game Over

- The final score, and whether it is a **new personal best**.
- Points total and how it broke down (base / speed / obscurity) is available if
  wanted.
- The full chain as a numbered recap, start to finish.
- The near miss, if there was one ("you were probably thinking of …").
- **Share** (a spoiler-free text card exists today; a rich share image is
  planned).
- **Play again** (returns to Home with a fresh deal).
- Entry to Your Reel.

### 4. Your Reel (sheet)

A local collection of every actor and movie the player has ever successfully
chained — a "look how many you know" record. Content: a grid/list of collected
nodes with art, counts (actors / movies / chains logged), personal best score,
and a filter or toggle between actors and movies. Pure counts, no rarity tiers.

This sheet also carries the **required TMDB attribution** ("This application uses
TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB", plus their logo; Settings → About carries it too), so it
must always be reachable even when empty.

### 5. Settings (sheet)

Small: sound on/off, app version. Will grow (account, notifications for the
daily puzzle).

## Planned features — leave room, don't design them yet

These are on the roadmap before launch. The skeleton should not paint itself
into a corner on any of them, but they don't need screens now.

- **The Daily Chain**: one shared puzzle per day, "get from A to B in the most
  links you can", one attempt, a shareable result card, and a streak. This will
  become the headline mode and likely gets a prominent slot on Home alongside
  the endless game.
- **Accounts** (optional sign-in so progress syncs; the game stays fully
  playable without one).
- **Friend groups**: compare daily results with friends by invite link. There
  will never be a global leaderboard.
- **Pass & Play**: hand the phone over and alternate turns on one chain.
- **Share images**: an image card for a completed run or daily result.

## Hard constraints

- **Portrait only on iPhone**, because the Play screen docks the keyboard. Any
  Play layout must be checked with a keyboard occupying the bottom ~40% of the
  screen.
- Actor vs movie must be distinguishable at a glance.
- Light and dark mode, both first-class.
- Respect Reduce Motion (anything animated needs a still or cross-fade
  equivalent).
- Text answers only during play; no autocomplete, no suggested answers.
- App icon must work as an opaque square (no transparency).
- TMDB attribution must live somewhere always reachable.
- Runs can be long; the chain display must handle 20+ nodes gracefully.

## Explicitly *not* decided (design these freshly)

- Palette, typography, shape language, imagery style.
- How the chain is drawn (stack, filmstrip, thread, constellation, cards, …).
- Whether the register is "calm puzzle page" or "cinematic".
- Motion language and feedback for correct / wrong / timeout.
- The app name and mark (a separate decision; "chain" is only domain vocabulary).
