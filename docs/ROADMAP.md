# Roadmap to 1.0 (launch)

> **1.0.0 means launch.** The solo game loop is complete and tested at
> [`0.4.0`](../CHANGELOG.md); five milestones stand between here and a public
> release. Each is allocated a minor version so the version number signals real
> progress — see the table in [`CHANGELOG.md`](../CHANGELOG.md).
>
> This doc is the *planning* layer: scope, rationale, what each milestone touches,
> and the decisions/traps to settle before writing code. Deep technical designs live
> in [`ARCHITECTURE.md`](ARCHITECTURE.md) and are linked rather than duplicated.
> The order is a plan, not a contract — if milestones land out of order, the version
> follows the work.

| Version | Milestone | Depends on |
|---|---|---|
| 0.5.0 | [Design overhaul](#050--design-overhaul) | — |
| 0.6.0 | [Login / session retention](#060--login--session-retention) | — |
| 0.7.0 | [Social — Pass & Play](#070--social--pass--play) | 0.6.0 (attribution) |
| 0.8.0 | [Leaderboards](#080--leaderboards) | 0.6.0 + backend |
| 0.9.0 | [Share images + TMDB proxy](#090--share-image-renderers--tmdb-proxy) | — |
| 1.0.0 | [Launch](#100--launch) | all of the above |

**One principle spans all of them** (carried over from the sociality design in
`ARCHITECTURE.md`): the game must stay **fully playable and fun solo and offline**.
Every social or account layer is additive on top of the login-free core, never a gate
in front of it.

---

## 0.5.0 — Design overhaul

**The current look is placeholder.** It's a competent NYT-Games/Connections pastiche,
but it isn't an identity of its own — and that includes the chain rendering, the
app's most visible element.

**What must survive:** the *structure*, not the styling. The design-system layer
exists precisely so a re-skin is a change to `Theme.swift` + `Components.swift`
rather than a rewrite of every screen:

- `Theme` — color / spacing / radius / motion tokens. Views reference tokens, never
  literals, so retuning is central.
- `Components.swift` — owned primitives (`NodeTile`, `NodeDot`, button styles, juice
  pieces). Screens compose these.
- **Per-node category identity** — the actor/movie distinction (currently blue/purple)
  is a real information channel, not decoration. Whatever replaces it must still
  encode "which kind is this" at a glance.

**In scope:** palette, typography, the `ChainStack` signature visual, tile treatment,
and a motion re-tune to match.

**Decide before starting:**

- **Still open — leading candidate: a stacked list of cards.** ⚠️ **Not decided.** The
  current tile-stack is the thing most likely to go (it reads as Tetris rather than
  *chain*), and a card stack is the direction being explored as of 2026-07-25 — but a
  filmstrip, a literal linked thread, and a constellation are all still live, and the
  card idea itself is still being played with. Everything below is exploration notes,
  not a spec. This remains the highest-leverage decision in the overhaul.

  **The card reference shape** (what was being looked at): cards stacked vertically with a strong overlap, each a
  distinct saturated colour block with a bold uppercase title; the **rearward cards are
  collapsed to just their title bar** while the **front (active) card is expanded** and
  carries the real content — illustration/art plus small pill-shaped metadata chips and
  a corner action button.

  **If cards win, the existing `ChainStack` structure already maps onto them.** It stacks,
  collapses older entries ("+N earlier"), and emphasises the newest — the same
  information architecture. So this is a **tile → card upgrade**, not a structural
  rethink: richer per-card content, art, and a real collapsed/expanded distinction,
  rather than a new layout model. That materially lowers the risk of the overhaul.

  **Why cards fit this app specifically:** it already fetches poster and headshot art
  for every node (`imagePath` → `Config.imageURL`), and a card is the natural container
  for art where a coloured bar is not. Today that art only surfaces in the Reel — cards
  put the *film itself* on screen during play, which is far more on-genre. It also
  composes much better with the 0.9.0 share-image milestone: a shareable "hand of
  cards" is a stronger artefact than a column of bars.

  **The hard constraint to solve first:** cards need far more vertical room per node
  than a 44pt bar, and the play screen's band is squeezed between the score hero and
  the **docked keyboard** (portrait-only, see below). Decide early how many rearward
  cards stay visible, how tightly they overlap, and whether the front card's expanded
  content is viable at all in the play window or only in the game-over recap. The
  reference's front card is tall — that's the part that has to give.

  **What the metadata chips become:** the reference uses them for attributes
  (`< 20 seats`, `< 5 workers`). Here the natural equivalents are year, the actor/movie
  kind, and possibly the points that link earned — but **nothing that leaks a future
  answer**, and the kind must stay glanceable (see the category-identity note above).

  **Naming note, so this doesn't become a false blocker:** "chain" is the *domain*
  vocabulary (`ChainNode`, `chain`, `bestChain`) and it stays accurate regardless — the
  data genuinely is an ordered sequence where each link is validated against the
  previous one. Presentation is independent: cards can render a chain. Only
  `ChainStack.swift` is presentation-named and would be renamed. The app *name* ("Movie
  Chain") is a separate, larger question — worth deciding deliberately rather than
  drifting into.

- Does the app keep the "puzzle page" register, or move toward something cinematic?
  The former is calmer and differentiated; the latter is more on-genre — and pairs
  naturally with a card/poster direction.

**Traps (all previously paid for — don't rediscover):**
- Every color needs **light + dark** variants in `Assets.xcassets`. `OnAccent` exists
  because text on the pastel tiles must stay legible in *both* themes.
- **Reduce Motion** is honored throughout today (screen pushes degrade to cross-fades,
  staggers and drops become instant). Keep that property.
- The **app icon** is derived from the chain mark — it changes with the redesign, and
  the render must be **opaque, no alpha channel** (iOS rejects icons with alpha).
- iPhone is **portrait-only** because the play screen docks the keyboard. A redesign
  that wants landscape has to solve the keyboard-docking layout first.

---

## 0.6.0 — Login / session retention

**Why:** durable identity, so scores attach to a *person* rather than a device — the
prerequisite for both leaderboards (0.8.0) and correct social attribution (0.7.0).

**Where the app is today:** entirely local and login-free — records in
`UserDefaults` (`bestChain`/`bestPoints`), the collection as JSON in Application
Support. Nothing knows who the player is.

**Recommended shape — anonymous first, upgradeable:**
1. A **stable per-device player id**, generated locally. Pass & Play needs one anyway
   (see `ARCHITECTURE.md` → Pass & Play: attribution must key on a stable id, *not* a
   name or roster index, so the same person coming back around a round-robin isn't
   duplicated).
2. **Sign in with Apple** as the upgrade path when the player wants their scores to
   follow them. Lowest friction on iOS, no password infrastructure, privacy-preserving.

This keeps the login-free character intact: you can play forever without an account,
and signing in is a migration rather than a gate.

**Decide before starting:**
- Is sign-in ever *required* (e.g. to appear on a global board), or always optional?
- What happens on sign-out / a second device — merge or replace?

**Traps:**
- **Migration must merge, not clobber.** A player with a local best and a full Reel
  who signs in must keep both. Write the merge rule before the auth code.
- Sign in with Apple gives a **stable but app-specific** user id, and the email may be
  a private relay — don't use email as the identity key.
- Account deletion is an App Store requirement once you offer accounts.

---

## 0.7.0 — Social — Pass & Play

**The mode:** you finish a run and hand the chain to a friend, who continues it and
passes it on — one shared chain shuttling between any number of players
indefinitely.

**This is already designed in detail** — see
[`ARCHITECTURE.md` → "Direction: Pass & Play"](ARCHITECTURE.md#direction-pass--play--a-chain-you-shuttle-between-friends)
for the full shape: a `moviechain://` deep link as the transport (no backend), a
versioned pure `Codable` payload + URL codec in the `FuzzyMatch`/`SeedDeal` family,
pass-on-run-end (no separate mode to pick), and a new engine entry point that rebuilds
`chain` + `usedIds` so the no-repeat rule and bounded-set validation automatically
span the whole shared history.

**Highlights worth restating here:**
- **No trust problem** — the receiver re-validates every link locally, so a lie in the
  link just fails validation on arrival.
- **Two integrity rules, already decided:** a shared chain **never** writes the solo
  best, and the Reel logs **only the links you personally added** (filter by owner
  before recording). Both follow the precedent set by the removed Assisted mode's
  split records.
- **Ownership lives on the payload/engine, not on `ChainNode`** — that stays a pure
  domain link.
- **Custom scheme first, Universal Links eventually.** A custom scheme is cheap but
  shows a system "open in app?" prompt, has no rich preview, and is dead for anyone
  without the app. Since the codec already speaks URLs, only the transport changes.
  Registering a scheme needs a real `Info.plist` **outside** the synchronized
  `movie-quiz/` group — see the gotcha note in `ARCHITECTURE.md`.

---

## 0.8.0 — Leaderboards

**Why now:** this is the point a **backend** genuinely becomes worth it — authoritative
scores, cross-device identity, and anti-cheat.

**Anti-cheat is already designed for.** Every entity resolves to a stable TMDB id and
validation is pure bounded-set membership, so a submitted chain can be **re-validated
server-side with the same logic the client uses**. Keeping the engine/provider split
clean is what preserves this property — don't break it.

**Tiering matters more than a global board** (from the sociality analysis in
`ARCHITECTURE.md`): a global all-time list is motivating for the top few only. A
**local / affinity tier** (city, campus, a film-club group code) is small enough that
a good run can actually top the board — that's where the motivation lives. Plan for
the tier structure up front even if global ships first.

**Decide before starting:**
- **What is ranked** — chain length (the headline metric) or points (the richer one)?
  Ranking both means two boards; ranking points makes speed/obscurity strategy matter.
- **Daily vs all-time.** A shared daily seed makes the 🟦🟪 share card *comparable*
  (Wordle's whole trick) and is probably the strongest single social feature here.
- Does the removed Assisted mode's precedent apply to any future assist? Yes — modes
  that change the difficulty of recall must never share a board (see
  [`ASSISTED-MODE.md`](ASSISTED-MODE.md)).

---

## 0.9.0 — Share-image renderers + TMDB proxy

Two unrelated pieces of release prep; together they make this the true release
candidate.

### Share images

**Nothing is built yet — there is no image renderer in the app today.** Sharing is
text only: `GameEngine.shareSummary` builds the 🟦🟪 card and hands it to `ShareLink`,
which works fine. This milestone *adds* rendered **images** for a finished run and for
the Reel. The notes below are traps to design around before writing that code, not
descriptions of existing bugs.

**The tool is SwiftUI `ImageRenderer`** — build the share card as a normal SwiftUI view
(reusing the node components) and rasterize it. Keep the text card too; it's a good
fallback and pastes nicely.

**The trap to plan for:** `ImageRenderer` renders **synchronously**, so any
`AsyncImage` in the rendered view will still be in its placeholder state — poster and
headshot tiles come out **empty**. Art has to be fetched into memory *first* and handed
to the view as a concrete `Image`. This matters most for a Reel share card, where the
grid of posters is the entire appeal. Also: `ImageRenderer` is `@MainActor`, and set
`scale` to the display scale or the output looks soft.

**Decide:** does the image stay **spoiler-free** like the text card (squares only), or
is showing the actual chain the point? The Reel card and the score card probably answer
this differently.

### TMDB proxy (the one infrastructural blocker)

From the `TODO(scale/security)` on `Config.makeProvider`: the TMDB token is bundled in
the app, so it ships inside the `.ipa` and can be extracted, and **every install shares
one key** — TMDB's per-key rate limit (~50 req/s) becomes a global ceiling across all
players, throttling the per-turn cast/filmography fetches at scale. A leaked key can
also get the account banned.

**The fix:** a thin server-side proxy holding the key and **caching the near-static
cast/filmography responses**, with the app pointing at the proxy. The
`MovieDataProvider` protocol means this is a *new provider implementation*, not an
engine change. If 0.8.0 already brought a backend, this rides on it.

---

## 1.0.0 — Launch

Not a feature milestone — the shipping checklist.

- ~~**Lower the deployment target.**~~ ✅ **Done (2026-07-25) — now iOS 18.0.** It had
  been **26.2**, which was never a requirement: just Xcode's default (the current SDK)
  at project creation. Verified by running the full suite on an **18.0** simulator as
  well as 26.x — green on both. macOS/visionOS minimums were left at 26.2 (secondary
  platforms; visionOS isn't installed locally so it couldn't be verified).
  **The audit, kept for the reasoning:**

  | Target | Result |
  |---|---|
  | 18.0 | ✅ builds clean, zero availability errors |
  | 17.0 | ✅ builds clean, zero availability errors |
  | 16.0 | ❌ `'Observable()' is only available in iOS 17.0 or newer` — `GameEngine.swift`, `Collection.swift` |

  So **iOS 17.0 is the true floor**, and the only thing holding it there is
  `@Observable` (the Observation framework) — which is load-bearing and not worth
  giving up. Note `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is a *compiler* setting,
  not an OS requirement, so it doesn't constrain this.

  **Why 18.0 and not 17.0:** going to 17.0 buys almost no extra *devices* (17 and 18
  support the same hardware), only users who declined two updates — while 18.0 keeps
  iOS 18 APIs available. Since Apple's numbering jumped 18 → 26, targeting 18.0 is
  "current major plus one back", the conventional support window.

  **Still to confirm at launch:** Apple's then-current adoption and device-support
  lists (don't trust a 2026-07 estimate) — iOS 26 dropped some devices that 18 still
  supports, so this may have recovered real hardware, not just un-updated users.

  **Ongoing cost now that it's lowered:** APIs newer than 18.0 need `if #available`
  guards, and version-sensitive changes should be tested on an 18.x simulator, not just
  the newest — 18.0 is the floor the shipped build must honour.
- **Real device testing.** Everything so far is simulator-verified. Haptics, audio
  session behaviour under the silent switch, and thermals/network on cellular need
  real hardware.
- **TestFlight** round with players who aren't you — the Assisted-mode postmortem is
  the argument for this: a mode survived four commits of refinement and died in one
  playtest.
- **App Store requirements:** privacy manifest / nutrition label (the app makes network
  requests to TMDB and stores data only locally; no tracking), account deletion if
  0.6.0 shipped accounts, and the **TMDB attribution** already rendered in the Reel
  sheet (their API terms require it — keep it reachable).
- **Changelog + tag** per the process in `CLAUDE.md`.

---

*Keep this current: when a milestone lands, move its entry into the changelog as a
released version and delete or rewrite its section here. When a plan changes, change
it here rather than letting the changelog table drift.*
