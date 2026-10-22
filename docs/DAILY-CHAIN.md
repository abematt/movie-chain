# The Daily Chain — A→B, longest route home

> **Status: specced, not playtested, not built.** The mechanic below came out of a
> design conversation on 2026-08-08 and is the planned headline mode for
> [1.0](ROADMAP.md). **Two open risks (§8) should be answered on paper with two people
> before any code is written** — this repo's most expensive lesson
> ([`ASSISTED-MODE.md`](ASSISTED-MODE.md)) is that a mode survived four commits of
> refinement and died in one playtest.

---

## 1. Why the game needs this

The endless game has no win condition. Every run ends in failure — you type until you
can't. That's tolerable in an arcade loop, but it costs us three things:

- **Nothing to compare.** Every run starts from a different dealt seed, so a score of 7
  is 7 against nobody.
- **Nothing to post.** People share wins. Our best possible outcome is "I lasted a
  while."
- **No reason to come back tomorrow.** Nothing in the app is different on Tuesday.

The daily chain adds a win condition, a shared puzzle, and a result worth sending to a
friend, without touching the endless mode — which stays exactly as it is, as free play.

## 2. The mechanic

**You get two names and a par score.** Both are actors. Everyone gets the same pair on
the same day.

> **Start: Tom Hanks · Target: Scarlett Johansson · Par 4**

You build a chain from the start, exactly as the endless game works today — alternating
actor → movie → actor, typed free-text, fuzzy-matched, validated against real credits,
no repeats. The only new thing is that you're building *toward* something.

The short route home is four links:

> Tom Hanks → *Saving Private Ryan* → Matt Damon → *We Bought a Zoo* → **Scarlett Johansson**

But you don't have to take it. You could go the long way:

> Tom Hanks → *Catch Me If You Can* → Leonardo DiCaprio → *The Departed* → Matt Damon → *We Bought a Zoo* → **Scarlett Johansson**

Six links. Same endpoints, more film knowledge shown, better score.

**The game is not racing to the target. It's seeing how far out of your way you can go
and still get home before the clock stops.**

### The decision

Every turn asks the same question: *do I know a route home from here, and is it worth
one more detour to find out?*

Three things give that question teeth:

1. **One clock for the whole round**, not per turn. Every detour spends time you may need
   to close the path. (The endless game's per-turn clock does the opposite — it has no
   round-level cost at all.)
2. **You can't back up.** The no-repeat rule already forbids reusing anyone, so a bad
   detour is permanent.
3. **Not connecting means no score.** This has to be true or the decision is fake — if a
   failed run still scored, the optimal play would be to extend forever.

### An important honesty note about the floor

"Bank whenever you want" is **not** a safety valve here. Closing out isn't a button —
it's the move of playing the target, and you can only play it when you *know* a link
from where you're standing to the target. A player who can't find a route has no way to
bank.

That means **the interesting decision only exists for a player who can already see a
route home.** For everyone else it's just a hard puzzle. Whether that population is
large enough is the single most important thing the playtest has to answer (§8).

## 3. Outcomes

Two results, both legitimate, both shareable:

| Outcome | Result |
|---|---|
| Reached the target | **Connected in N** — N is the score |
| Clock expired first | **Didn't connect — built N** |

Not connecting is modelled on Wordle's `X/6`: a normal thing that happens, posted
without embarrassment, still a result. **Designing the failure out of the game is the
wrong goal; making it unremarkable is the right one.**

Difficulty is not managed by softening this outcome — it's managed at generation (§5).

## 4. Scoring

- **Headline number: links in the chain**, on a connect. Directly comparable to par and
  to other players.
- **Points** (the existing base + speed + obscurity math in `Scoring.swift`) stay as the
  secondary number.
- **The obscurity weight is the anti-padding lever.** See §8.
- **The daily never writes the solo endless best.** Precedent already set twice in this
  codebase: the removed Assisted mode kept split records, and the Pass & Play design
  states a shared chain never writes the solo best. Different mode, different record.

## 5. Generating a solvable puzzle

**The hard part of this whole mode.** Two random famous names may have no route between
them, and shipping an impossible puzzle fails publicly for everyone at once.

**Build the puzzle backwards: don't pick two names, walk a path.**

1. Pick a start actor `A` from the recognizable pool (same standard the deal already
   applies).
2. Walk `par` real links through actual credits — cast, filmography, cast, filmography.
3. Whatever you land on is the target `B`.

A route is guaranteed because we just walked one, and its length is the par score for
free.

**Apply the familiarity standard at every step of the walk.** This is the direct lesson
from [`ASSISTED-MODE.md`](ASSISTED-MODE.md#the-trap-worth-remembering-drift): the removed
mode failed because the game curated recognizability for the seed and abandoned it for
every step after, stranding players in obscure neighborhoods. A generated walk owns the
whole path, so it inherits that obligation completely — the walk must never leave the
mainstream region of the graph.

**Then check the target is *dense*.** A target reachable by exactly one route is a
needle in a haystack. Prefer a `B` with a large, popular filmography so many routes
exist. This is what makes a puzzle findable rather than lucky.

### Difficulty dials

All at generation, none in the mechanic:

| Dial | Effect |
|---|---|
| `par` length | Longer par = harder |
| Fame floor for the endpoints | Lower = harder |
| Target density | Fewer routes = harder |
| Round clock | Shorter = harder |

### Why this can't run on the phone

- **Devices would diverge.** A date-seeded start actor is deterministic and fine, but
  finding a *reachable* target means walking live data — and the walk depends on current
  credits and result ordering, so two phones can land on different targets. The moment
  that happens the puzzle isn't shared, and the whole mode is pointless. **This is the
  fatal one.**
- It costs a lot of API calls per device per day — the walk plus the density check, far
  more than a play session.
- A client-generated puzzle is a client-chosen puzzle.

### But it doesn't need a *live* backend job

Generation has to happen **once, somewhere** — it does not have to happen on a running
server. The pipeline is **generate offline → review → publish**:

1. A script on your Mac walks the paths (through the proxy, so its cache serves the
   generator too) and **queues** candidate puzzles.
2. **You approve them.** A human in the loop is deliberate, not a placeholder — see the
   drift note below.
3. Approved puzzles publish as `{date, A, B, par}` and the app fetches a week at a time,
   cached on device so an outage degrades instead of breaking.

**Why a human approves.** The generator chose every node on the path, so it owns where
the player ends up. A walk that wanders somewhere obscure strands *everyone* at once,
publicly — the drift trap with an audience. Five seconds glancing at tomorrow's pair is
very cheap insurance, and it's what lets you hand-author a puzzle for launch day or a
themed week.

**Three delivery options, in ascending capability:**

| Option | Trade |
|---|---|
| Ship a pack in the app bundle | Zero infrastructure, works offline. Frozen at ship time — a bad puzzle needs an App Store update, and it runs out. |
| Publish to a static file (GitHub Pages, S3) | Nothing *running*, so nothing to deploy or monitor. Fixable any day, never runs out. |
| Publish through the service | Everything above, plus themed packs, community puzzles, remote tuning, and a message channel. See [`ROADMAP.md`](ROADMAP.md#080--the-service). |

**Decided: the service** — the point is owning a publishable surface, not just the daily.
But note the consequence for sequencing: **the daily is not hard-blocked on a backend.**
If the service slips, a bundled pack ships the mode.

### When the day turns over

**Decided 2026-10-23: the player's local midnight**, the Wordle / Duolingo model. One
global rollover would change the puzzle mid-evening for half the world, which reads as
broken in a daily game.

- **Each puzzle is keyed by its calendar date and carries a number** (#1 is launch day).
  Everyone plays the same puzzle on the same local date; Sydney simply gets it hours
  before New York. Accepted, as Wordle does — earlier time zones can spoil it, and nobody
  can do anything about that without a global rollover.
- **Results are stored by puzzle number, never by timestamp.** "One attempt per day" is
  really "one result per puzzle", which is also what the two-devices merge rule ("highest
  wins") keys on.
- **Today is decided by the phone's current time zone**, read when the app opens.
  Travelling west gives a longer day, east a shorter one; that's accepted rather than
  engineered around.
- **Streaks count consecutive local dates with a result**, stored as the set of completed
  dates (`ROADMAP.md` 0.7.0).
- **Moving the phone's clock forward shows tomorrow's puzzle early.** Accepted, for the
  same reason as below — there's nothing to win.

### One attempt, without a server

Device-local enforcement only, until accounts exist. Reinstalling or changing the phone's
clock defeats it. Acceptable at friend scale with no prizes — and given an AI can produce
a valid chain on request, the integrity story was never airtight anyway (see
[`ROADMAP.md`](ROADMAP.md#the-decisions-this-plan-rests-on)). It tightens automatically at
0.9.0, when the "already played today" check moves server-side.

## 6. What the app needs

Modest — the engine's existing structure does most of the work.

- **A target on the round.** `startGame(with:)` gains a target node; `accept()` checks
  whether the accepted node's id matches it and ends the round as a connect. Validation,
  fuzzy matching, and the no-repeat rule are **completely unchanged** — the bounded
  candidate set works identically.
- **A round clock.** New; the existing per-turn countdown is the wrong shape for this
  mode. Both modes' clocks should share the pause-across-fetch behaviour that fixed the
  stuck-turn bug.
- **A daily provider call** to fetch today's puzzle, and a local cache so the round
  survives losing signal mid-play.
- **One attempt per day, enforced.** Device-local until accounts exist; server-side
  after. Note the loophole to close: **quitting mid-round must consume the attempt**, or
  force-quitting the app is a free retry.
- **Separate records** from the endless best (§4).

## 7. The share card

Spoiler-free, comparable, and it names the puzzle so a friend knows you played the same
one:

```
Movie Chain · Aug 8
Tom Hanks → Scarlett Johansson
Par 4 · connected in 9
🟦🟪🟦🟪🟦🟪🟦🟪🟦
```

The squares reveal only the shape, never the names — same property as the existing
`shareSummary`. **And unlike today's card, this one carries a link.**

## 8. Open questions — answer these on paper first

**1. Padding.** The optimal strategy might be boring: bounce between five mega-famous
actors who've all worked together, then close. If the highest score comes from the least
interesting play, the mechanic is broken. The likely fix already exists — the obscurity
bonus makes famous filler score poorly — but that's a hypothesis, not a result. *Watch
for: does the best score come from the most impressive play, or the safest one?*

**2. Stranding.** A player who wanders into a corner and loses everything may feel
cheated rather than beaten. Par is proof a route exists, but proof isn't consolation.
*Watch for: when someone fails, do they say "I blew it" or "that was unfair"?*

**3. Does the decision exist at all?** Per §2 — extend-or-bank is only a decision for
someone who can already see a route home. *Watch for: how often does a player knowingly
choose to extend, versus just moving because they must?*

**4. Round clock length.** Start at three minutes and tune. Long enough to consider a
detour, short enough that leaving the app to look something up costs the round.

**5. Is par shown up front, or only at the end?** Up front sets expectations and proves
solvability. Held back preserves the surprise and stops par from anchoring people to the
short route.

**6. Does the daily log to the Reel?** It's genuine recall, so probably yes — but the
Reel's rule today is deliberately narrow ("successful combinations only"), and this mode
has a different shape.

**7. One attempt — how strictly?** See §6. Worth deciding whether a mid-round crash
should cost the day.

---

## 9. What this mode is *not*

- **Not shortest-path.** Six Degrees of Kevin Bacon is lookupable, solved, and gives
  everyone with knowledge the identical score — no spread, nothing to compare. Longest
  produces a distribution, which is the whole point.
- **Not replayable.** One attempt. Retries don't weaken the score, they delete the
  mechanic: if failure is free, the answer is always "extend," every time. Replayability
  lives in the endless mode, and later in an unranked practice mode.
- **Not ranked globally.** See [`ROADMAP.md`](ROADMAP.md) — an AI can produce a valid
  long chain on request, so a number from a stranger is meaningless. Comparison is
  friend-scale only.

---

*Cross-references: [`ROADMAP.md`](ROADMAP.md) for where this sits in the plan,
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the engine this plugs into, and
[`ASSISTED-MODE.md`](ASSISTED-MODE.md) for the drift obligation the generator inherits.*
