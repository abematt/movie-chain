# Assisted mode — built, playtested, removed

> **Status: removed (playtested, rejected).** A multiple-choice "Assisted"
> difficulty was fully built, unit-tested, and refined over four commits, then
> removed after playtesting because it **served neither audience**. This document
> is the postmortem *and* the implementation guide: why it failed, exactly how to
> get the code back, and what to build instead if assistance returns.

## What was built

A session-level difficulty picked on the home screen: **Hardcore** (the shipped
recall game — type the answer, fuzzy-matched) or **Assisted** (each turn presents
3 options, 1 correct, and you tap). Supporting pieces:

- `Choices.swift` — a pure option-building policy (1 correct from the bounded
  candidate set + recognizable distractors from the cached deal pool, **zero extra
  network**), with a `FamiliarityGate` that constrained which node the chain could
  step to.
- Engine: `Difficulty`, `currentOptions`, `select(_:)`, a shared `accept(_:)`, a
  wrong-tap time penalty, and **split record tracks** so an assisted run never
  wrote the Hardcore best.
- UI: a `DifficultyToggle` on the home screen, a `SettingsView` sheet, a
  keyboard-free panel of tappable option tiles with `NodeThumbnail` art.

It worked. The problem was never that it was broken.

## Why it was removed

**It served neither audience.** This is a design conclusion, not a tuning miss —
which is the important part, because every individual problem *was* fixable and
fixing them did not help.

1. **For the newcomer it was built for, it still confounded them.** Playtested
   with someone not into movies. Restricting the options to globally-famous names
   doesn't address the actual difficulty: the hard part isn't *recognizing a name*,
   it's knowing **who was in what**. A turn asking "which of these three films was
   this actor in?" is uncharted territory for someone without cast knowledge no
   matter how famous the three films are. Recognition doesn't rescue a player who
   lacks the underlying association — it just changes the shape of the guess.
2. **For the enthusiast the app is actually for, it removed the point.** The
   accomplishment *is* the act of recall — dredging up "who else was in that?"
   unaided. Tapping from a list deletes that, so there's no reason to play it.

A middle mode that dilutes the core loop without solving the newcomer's real
problem has no audience. That's the whole finding.

### The trap worth remembering: drift

The most interesting failure — and the one that took two attempts to diagnose —
is worth keeping even though the mode is gone, because **it applies to any feature
that picks chain links on the player's behalf** (a daily seeded chain, a tutorial,
an AI opponent, Pass & Play validation).

The chain is a walk on the TMDB co-appearance graph, and nodes have wildly
different "familiarity neighborhoods." A globally-famous actor whose filmography
is almost entirely regional cinema (the reported case: a Bollywood star with one
Hollywood credit) legitimately enters the recognizable actor pool — but stepping
onto her strands the chain, because her *candidate set* is genuinely
non-mainstream, its cast are non-mainstream, and there is no way back (the
no-repeat rule forbids retreating).

The first fix attempt — sorting that node's own candidates by popularity and
picking from the top — **cannot work, and understanding why matters**: ordering a
set that is 95% unfamiliar still yields something unfamiliar. Local ordering
cannot escape a globally bad neighborhood.

The real diagnosis: **the game curated recognizability for the seed (step 0) and
then abandoned it for every step after.** That inconsistency was the bug. The fix
was to apply the same standard at every step, which is self-reinforcing — widely
seen films have widely known leads and vice versa, so a walk that never leaves the
mainstream component of the graph stays inside it.

The other principle worth keeping: **an asymmetry of responsibility.** In Hardcore
the player chose to type that name, so they knowingly entered that neighborhood. The
moment the game *offers* the node, the game owns where the player ends up. Any
future feature that picks links inherits that obligation.

## Getting the code back

It's all in git — nothing needs to be rewritten from this document.

| Commit | Contents |
|---|---|
| `ef2603b` | Engine (`Difficulty`, `select`/`accept`, split records) + `Choices.swift` + tests |
| `3af5d28` | UI: home `DifficultyToggle`, `SettingsView`, `GameView` option panel |
| `98c0a7d` | Stuck-turn fix, recognizability ordering, `NodeThumbnail` option art |
| `190b962` | `FamiliarityGate` (the drift fix) + Reel logging made Hardcore-only |

```bash
# Read the whole feature as it stood at its most refined
git show 190b962

# Restore individual files
git checkout 190b962 -- movie-quiz/Choices.swift movie-quizTests/ChoicesTests.swift

# See everything the removal took out
git log --oneline --all -- movie-quiz/Choices.swift
```

### What was deliberately kept (do not "restore" these — they're already in)

Four things from this work were **not** assisted-specific and remain on `main`:

- **Candidate-load retry + `Config.requestTimeout` + `retryTurn`/`awaitingRetry`.**
  This fixed a genuine freeze that affects **Hardcore too**: the clock is paused
  across a candidate fetch, so a stalled request (URLSession's ~60s default, no
  timeout set) hung the turn. Now transient failures retry silently and an
  exhausted load surfaces a manual **Retry**.
- **`filmography(of:)` sorted most-popular first** — makes the "you were one away"
  near-miss surface a film the player would actually know.
- **`Config.seedMoviePoolPages = 5`** (~100 titles) — seed shuffles stopped
  recycling the same ~40 films.
- **`SettingsView` + the home gear pill** — a settings surface was wanted
  independently; it now holds the sound toggle.

### Orphaned persisted keys

Assisted runs wrote `bestChainAssisted` / `bestPointsAssisted` and the home stored
`difficulty` in `@AppStorage`. Nothing reads them now. They're harmless (a few
integers in `UserDefaults` on devices that ran a test build) and are deliberately
**not** deleted, so a revival would find its old records intact.

## If assistance returns: preserve the recall act

The lesson is not "assistance is bad" — it's that **assistance must narrow the
answer space while the player still produces the answer.** Replacing production
with selection is what killed it. So don't rebuild multiple choice; build a hint.

**Design sketch.** Keep the Hardcore loop *exactly* as-is — typing, fuzzy match,
the docked keyboard. Add an optional per-turn hint that escalates, drawn entirely
from state the engine already owns (`candidates` minus `usedIds`), so it needs
**zero extra network**:

| Tap | Hint | Cost |
|---|---|---|
| 1 | "12 valid answers left" | free (or a small time cost) |
| 2 | First initial: "J—" | a few seconds |
| 3 | Letter blanks: "J _ _ _   M _ _ _ _ _ _ _ _" | more |

The player still has to *produce* "John Malkovich" — the accomplishment survives,
and a stuck enthusiast gets unstuck instead of quitting. This also sidesteps drift
entirely: hints never choose the next node, so the chain stays player-driven and
the responsibility asymmetry above never arises.

A sketch of the pure type, in the family of `FuzzyMatch`/`SeedDeal`/`Scoring` (so
it's unit-testable with no network and no engine):

```swift
/// Progressive hints about one valid answer. Pure — the caller supplies the
/// bounded candidate set the engine already holds.
enum Hint {
    case count(Int)              // "12 valid answers left"
    case initial(Character)      // "J—"
    case blanks(String)          // "J _ _ _   M _ _ _ _ _ _ _ _"

    /// `level` 1…3. `target` is any unused candidate (pick the most recognizable —
    /// cast is billing-ordered, filmography is popularity-sorted).
    static func reveal(level: Int, target: ChainNode, remaining: Int) -> Hint {
        switch level {
        case 1:  return .count(remaining)
        case 2:  return .initial(Character(target.matchText.prefix(1)))
        default: return .blanks(masked(target.matchText))
        }
    }

    private static func masked(_ name: String) -> String {
        name.enumerated()
            .map { i, c in c == " " ? "  " : (i == 0 ? String(c) : "_") }
            .joined(separator: " ")
    }
}
```

Engine additions would be small: `hintLevel` (per turn, reset on `accept`),
`currentHint`, and a `revealHint()` that docks time. **Scoring is where the
integrity rule goes** — and the precedent already exists in this codebase (the
split record tracks, and the Pass & Play rule that a shared chain never writes the
solo best): either dock points per hint on a single leaderboard, or track
hint-assisted runs separately. Prefer docking points here, since the run is still
genuinely recall.

**Open question worth settling before building it:** does an enthusiast who is
stuck actually want a hint, or do they want the run to end so they can start a
fresh one? Test that with two people before writing code — this whole document
exists because a mode was built before that question was asked.

---

*Cross-references: [`ARCHITECTURE.md`](ARCHITECTURE.md) for the engine/provider
split this would plug into, and its "Extending it" section for the other planned
directions (Pass & Play, sociality, leaderboards).*
