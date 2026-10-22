# Growth plays → what we build

> **What this is.** An external research dossier on [@maubaron](https://x.com/maubaron)'s
> app-growth playbook (*Prayer Lock*, $0 → ~$60K/mo, solo, TikTok-only) reconfigured for
> this app — as an **engineering backlog**. Each of his plays needs a mechanic in the
> product to work at all; this doc is what those mechanics are here, what they'd cost,
> where they plug into the existing code, and which ones only make sense together.
>
> **Status: partly superseded (2026-08-08).** The direction has since been decided —
> see [`ROADMAP.md`](ROADMAP.md) for the plan of record. In short: **Bet A (the daily)
> was taken and enlarged** into the [Daily Chain](DAILY-CHAIN.md), friend groups replaced
> global leaderboards, and login moved *into* the launch scope rather than after it,
> because mastering the full publish→backend→auth→social loop is the actual goal here.
>
> **What's still live in this doc:** the build catalog in §4 (sizes and code anchors all
> still hold), the TMDB rate-limit derivation in §8, the licensing analysis, and §6 on
> why the onboarding lever doesn't transfer. **What's dead:** the §5 "smaller 1.0"
> recommendation and the §7 bet framing.
>
> **Companions:** [`ROADMAP.md`](ROADMAP.md) (the path to 1.0 — several items here are
> roadmap milestones seen from a different angle), [`ASSISTED-MODE.md`](ASSISTED-MODE.md)
> (rules out one whole class of these features — read before building **D6**, **D7**, or
> anything that picks a link), [`ARCHITECTURE.md`](ARCHITECTURE.md) (the engine/provider
> split every one of these hangs off).

---

## 1. The playbook's plays, and what each one needs from the product

His plays, and the product surface each one requires. The right-hand column is the
actual subject of this doc.

| His play | Why it worked | What the product has to provide |
|---|---|---|
| Distribution over features, early | Nothing to lose | A reason for the app to leave the phone it's on |
| One format, huge volume | Algorithmic surface area | Cheap, repeatable content — ideally generated, not authored |
| The hook is *discovered* (~40 posts) | Iteration beats design | Many distinct clippable moments to test |
| Judge on installs, not views | Kills pretty dead-ends | Attribution, and an activation event |
| Longer onboarding → 3× conversion | Trial funnel | *Not transferable — see §6* |
| Creator fleet by cold DM | Others make your content | Something a creator can pose to their audience |
| Spark Ads on organic winners | Amplify what worked | Nothing app-side — it's a creative buy |
| Shareable result as acquisition | Users become the channel | A share artifact **with a way back in** |

Two of those are pure marketing ops and aren't discussed further (Spark Ads, posting
volume). The rest all cash out as things we build.

---

## 2. Where the app stands relative to them

The honest read of the code, because it sets what's cheap and what isn't:

- **Every share is a dead end.** `GameEngine.shareSummary` and
  `CollectionStore.shareText` produce nice artifacts with **no URL in them**. The
  Wordle-grid mechanic is half-built: the spoiler-free 🟦🟪 card exists and tells nobody
  where to get the app.
- **The grid isn't comparable.** Wordle's trick isn't the emoji — it's that everyone
  played *the same puzzle*. Every run here starts from a different dealt seed, so
  `🟦🟪🟦🟪` communicates a length and nothing else.
- **`startGame(with seed: ChainNode)` is a single, clean entry point** — a daily chain, a
  challenge link, a rematch, and a received Pass & Play chain are all *the same call with
  a different seed*. That's the reason most of §4 is cheap.
- **There is no wire format.** `Person`/`Movie`/`ChainNode` are `Identifiable`/`Hashable`/
  `Sendable` but **not `Codable`** (only `NodeKind` is; `CollectedEntity` is the one
  Codable value, in `Collection.swift`). Anything that travels — link, daily, replay —
  needs the codec in **D1** first.
- **The engine can already be driven into an arbitrary chain state.**
  `loadDemoChain()`/`loadDemoGameOver()` (DEBUG-only) build a chain, set score/points,
  and jump the phase. That's the germ of rendering a run you didn't play — the basis
  of **D9**.
- **Nothing is measurable.** No analytics, no attribution, no crash reporting. All state
  is local (`UserDefaults` + a JSON file).
- **The app isn't shipped** — v0.4.0 when this was written (0.5.0 now), no App Store
  listing, no TestFlight. The repo is on GitHub, but nothing is distributed.

---

## 3. The one build that unlocks four plays

**D1 — the chain wire format + URL codec.** Everything that leaves the device needs it,
and it doesn't exist.

A versioned, pure `Codable` payload — the ordered chain with each link's id, kind, and
display name (self-contained, so no by-id fetch is needed; the provider protocol has
none today) — plus a `URL ⇄ payload` transform, in the same family as `FuzzyMatch` /
`SeedDeal` / `Scoring`: no UIKit, no network, unit-tested for round-trip,
malformed → nil, newer-version → rejected.

[`ARCHITECTURE.md`](ARCHITECTURE.md#direction-pass--play--a-chain-you-shuttle-between-friends)
already specs this **as part of Pass & Play**. The reframe: it isn't a Pass & Play
component, it's shared infrastructure. It's the prerequisite for **D4** (challenge
links), **D8** (Pass & Play), **D9** (video from any chain), and the payload half of
**D5** (daily result sharing).

Build it once, generalized, ahead of whichever play goes first. **Size: S–M.** Pure
value type + codec + tests, no I/O.

---

## 4. The build catalog

Sizes are relative: **XS** = an afternoon, **S** = a day or two, **M** = a week-ish,
**L** = a real project. Every item names where it plugs in.

### Share loop

**D2 — Put a URL in both share strings.** `shareSummary` and `shareText` gain the App
Store link. Blocked only on a listing existing. **XS.** Highest
distribution-value-per-line in the repo — right now the app's best organic artifact
converts at exactly zero.

**D3 — Rendered share image (score card).** Part of the 1.0.0 launch milestone. SwiftUI `ImageRenderer`
over the existing node components. **M** — the trap is documented: `ImageRenderer` is
synchronous, so any `AsyncImage` renders as its placeholder and poster art comes out
empty; art must be fetched into memory and handed in as a concrete `Image`. Keep the
text card as the fallback. Decide per-artifact whether it stays spoiler-free (the grid)
or reveals the chain (the flex).

**D3b — Reel poster wall.** The Reel rendered as a grid of posters and headshots —
"look how many you know" as a single image. **M–L**, and it's the worst case of the
`AsyncImage` trap (the whole appeal *is* the art, so every tile must be pre-fetched).
Probably the most postable artifact the app is capable of producing, and it pairs with
**D7** milestones as the trigger to post it.

**D4 — Challenge links ("beat my start").** A link that drops the recipient into
`startGame(with:)` on **the same seed** you just played, with your score to beat.
**S once D1 exists.** This is the comment-bait mechanic FilmTok already runs on, it
gives a share a *reason* beyond the number, and it's the cheapest true acquisition loop
in the catalog — but see **D10**: without a web fallback the link is dead for anyone who
doesn't already have the app.

### Comparability

**D5 — Daily chain.** A date-derived seed, so everyone plays the same start.
No backend, no accounts — deterministic from the date. **M.**

This is what makes the existing 🟦🟪 card mean something, and the roadmap already
identified it (inside the old leaderboards milestone, now dropped) as *"probably the strongest single social feature here."*
It never needed the rest of leaderboards.

⚠️ **It inherits the drift obligation.** [`ASSISTED-MODE.md`](ASSISTED-MODE.md#the-trap-worth-remembering-drift)
names a daily seeded chain explicitly: the moment the *game* chooses the seed, the game
owns where the player ends up. A daily must pass at least the familiarity standard the
deal pool already applies — and a bad day is now a public failure that everyone hits at
once, not a private one.

**D6 — Streaks.** Consecutive days played. **S** on top of D5. The return reason the app
currently lacks — nothing in it gives a reason to open tomorrow.

**D7 — Milestones.** "100 actors logged", "first 10-link chain". **S–M.** The
`CollectionStore` already counts everything needed (`chainsLogged`, per-entity
`timesLogged`). Value is as a *share trigger* — a moment the app can legitimately ask
you to post, which is when **D3b** fires.

### Friend-to-friend

**D8 — Pass & Play.** Fully designed already; **L**. The reframe worth making before
building it: **as specced it can't acquire anyone.** A custom `moviechain://` scheme is
dead for anyone without the app, which makes it a *retention* feature. With **D10** it
becomes an acquisition loop — every handoff is an ad delivered by a friend, with
context, to someone who doesn't have the app.

**D9 — Chain → vertical video.** The content factory, and the most interesting item
here. The dossier's automated-content play (§5 of the source: scrape a creator's videos,
staple your CTA on) is a copyright and ToS exposure. **We don't need it** — the app can
generate original content from its own data.

A chain is just data. `loadDemoChain()` already proves the engine can be driven into any
chain state; a renderer walks a chain, animates it through the real components, and
writes 9:16 frames out with `AVAssetWriter`. That's "700 posts in ten minutes" done
legitimately, with our own art and our own UI.

Three shapes, in ascending cost:
- **ReplayKit capture** in a debug build — record real runs by playing them. **S**, but
  it's manual labor per video, which is exactly what the volume prescription can't
  afford.
- **A macOS companion target** that imports a chain (via **D1**) and renders it
  offscreen. The project already builds for macOS and the views are shared. **L**, and
  it's dev tooling — no App Store surface, no iOS app bloat, no review risk.
- **In-app "save a replay"** as a player feature. **L** and the least urgent — it puts
  the burden back on the player.

Recommendation if this bet is taken: the Mac tool. It's the only version that makes the
marginal cost of a video approach zero, which is the entire premise of the volume play.

**D10 — Universal Links + a web fallback page.** A domain, an `apple-app-site-association`
file, and a page that renders the shared chain and offers the App Store. **M + a domain.**

This is the multiplier on **D2**, **D4**, and **D8** — it's the difference between a
share that only works between people who both already have the app, and a share that
installs the app. The same domain is where the TMDB proxy (§8) would live, so one
decision serves both.

### Activation

**D11 — Curated first seed.** Hand-pick the first-run seed from universally-known names
instead of dealing it. **S**, and it stays on the right side of the drift line: the game
chooses a *seed*, never a *link* — which the app already does every launch.

**D12 — Hint ladder.** Count → first initial → letter blanks, all from
`candidates` minus `usedIds`, so **zero extra network**. **M**, and it's already designed
in [`ASSISTED-MODE.md`](ASSISTED-MODE.md#if-assistance-returns-preserve-the-recall-act)
down to the type sketch. It's the real answer to "the newcomer got stuck", and it's the
only surface in the game with a natural shape for a price (a consumable, or the one ad
format that wouldn't wreck a timed recall game: rewarded video → one hint).

⚠️ The open question from that doc still stands and should be tested with two people
before any code: **does a stuck enthusiast want a hint, or do they want the run to end so
they can start a fresh one?** That document exists because a mode was built before that
question was asked.

**D13 — Near-miss as a shareable artifact.** "You were one away" is already computed and
already the most dramatic beat in the game — and it currently dies on the game-over
screen. Make it a share (and a video-clip ending in **D9**). **XS–S.**

### Measurement

**D14 — Attribution + activation event.** App Store Connect **campaign links** (the `ct=`
parameter) give per-campaign install counts with no SDK and no privacy-label change.
Pair with an activation definition — proposed: **first run reaching a chain of ≥ 3**
(the engine already treats ≥ 2 as "a real combination landed", the Reel-logging
condition in `endGame()`). **S.** Without this, "judge on installs, not views" — the
most useful discipline in the dossier — is unrunnable, and every format test is a guess.

**D15 — Crash reporting.** **XS.** Not growth, but acquiring into an uninstrumented app
means a crash loop is invisible.

---

## 5. Two plays that need no build

**The app already is the content.** His hook was a person reacting on camera because a
prayer-lock screen has nothing to show. Here a screen recording of a real run is already
a complete video: timer pressure, a rising chain, the shake on reject, the score pop,
the near-miss. Camera-shyness is a non-issue, and going faceless isn't a deviation from
the playbook — it's the correct application of it to a different product.

**Which made 0.5.0 (the design overhaul) a distribution deliverable.** If the screen is the creative, the
screen's quality is the creative's quality — and it's also the App Store screenshots and
the preview video. The design overhaul is the one "feature" on the roadmap that is
straightforwardly acquisition work.

---

## 6. One play that doesn't transfer, and one that's forbidden

**Longer onboarding → 3×** is a *subscription-trial* lever: more installs start a paid
trial. There's no trial, no price, and no monetization anywhere in the app or the
roadmap, so the mechanism it exploits doesn't exist. There is no 3× onboarding lever
available here; claiming one would import a number from a funnel we don't have. The
equivalent-sized lever for a free game is D1 return — that's **D5**/**D6**.

**The dossier's adaptation of it — "make the first session a guided playable chain" — is
ruled out by this repo's own postmortem.** [`ASSISTED-MODE.md`](ASSISTED-MODE.md) names a
tutorial as one of the features that inherits the drift trap, and the finding applies
directly: a guided first chain either picks links for the player, or it doesn't guide. A
multiple-choice difficulty was built, unit-tested, refined over four commits, and killed
by a single playtest for exactly this reason. **D11** and **D12** are the versions that
survive that lesson.

---

## 7. Three directional bets

These aren't exclusive, but they order the catalog differently and the first one you pick
determines what's cheap next.

### Bet A — The daily (Wordle path)
**D5 + D6 + D2 + D3**, then **D7**.
No backend, no domain, no accounts. Makes the share card the app *already builds* mean
something, and gives the app a reason to be opened tomorrow. Cheapest complete loop, and
the mechanic is proven to the point of cliché.
**Cost:** M overall. **Risk:** the drift obligation on the daily seed; a bad day is
public.

### Bet B — The challenge loop
**D1 → D4 + D10**, then **D8**.
Friend-to-friend, compounding, no content labor. Every share is an install path instead
of a dead end. This is the highest-ceiling organic channel the app can have, and D10 is
what converts three existing/planned features from retention into acquisition.
**Cost:** M–L plus a domain. **Risk:** needs real friends-with-the-app density before it
compounds; the web fallback is the hedge against that.

### Bet C — The content factory
**D9** (Mac tool) **+ D4** for the poseable format, on top of **D1**.
Treats the app as a video generator and feeds the volume play directly — the one thing
the dossier says actually matters. Dev tooling rather than player features, so it adds no
App Store surface and no review risk.
**Cost:** L. **Risk:** it's a bet on the *content* channel working, and it produces
nothing for existing players.

**If forced to sequence:** **D2** and **D14** regardless (XS/S, and everything else is
unmeasurable without them), then **D1** because three of the interesting builds sit on
it, then pick a bet.

---

## 8. Two hard gates on any of it

**TMDB request rate — the constraint that scales with success.** A cold launch fires
**24 concurrent requests** (5 `discover` pages for the movie pool; 1 page + credits for
`seedActorSourceMovies = 18` films for the derived actor pool), and the pools are
in-memory only, so it repeats every launch. Against the ~50 req/s key ceiling the
roadmap cites, that's roughly **2 cold launches per second** before saturation — before
any gameplay traffic. Averaged over a day that's tens of thousands of players, so
steady-state DAU isn't the binding constraint; **launch concurrency is, and a breakout
video is precisely a launch-concurrency spike.** A video driving 10K installs in an hour
is ~2.8 launches/s — over the line.

Two amplifiers: `prepareSeeds()` retries the pool load up to 3× and
`Config.candidateLoadAttempts = 3` retries each turn fetch, so failures multiply load;
and the failure surface is the home hero stuck on **"Dealing…"**, which is the first
screen the cohort you just earned would see.

- **Cheap mitigation: persist the deal pool to disk with a TTL.** It's a fixed
  `vote_count.desc` query, near-static, and *identical for every player*, yet it's
  refetched from scratch on every cold launch. **S**, and it removes most of the burst
  with no server.
- **Real fix: the 0.7.0 proxy with caching**, which also takes the extractable key out of
  the `.ipa`. Because the pool is identical for everyone, one cached upstream response
  serves the whole player base.

Neither is needed for the first few thousand installs. Both should be live before any
deliberate push for a breakout — otherwise the best possible outcome breaks the app for
everyone at once.

**Content licensing.** TMDB's attribution requirement is already met in the Reel sheet,
but TMDB doesn't own the posters and stills it serves — studios do, and it can't license
them to us for marketing. The dossier's suggested formats ("name the film from one
frame") are built on exactly that material; FilmTok runs on de-facto tolerance, and an
app CTA attached to it is commercial use. **This resolves in our favour and points the
same way as §5:** make the app's own screen the creative. Where a poster appears it
appears as in-app UI with attribution present — a far more defensible position than a
bare frame with a CTA stapled on. Separately: **if a price is ever attached, re-read
TMDB's terms** — the free tier's commercial-use position is the thing to check first.

---

## 9. Still open

1. **Which bet** (§7) — or explicitly none yet.
2. **Free forever, or is there a price?** Decides whether **D12** is an activation
   feature or a monetization surface, and whether the dossier's entire paid-acquisition
   half is void (it is, today: no StoreKit, no IAP, no ads, nothing planned).
3. **A domain**, if Bet B — it's also where the proxy lives.
4. **The app name** — the roadmap already has it open as a design question; it's an ASO
   decision too, and "movie trivia" is real search demand his app never had.
5. **Realistic hours/week for content**, if Bet C — the factory only pays off if
   something posts what it makes.

---

*Source: research dossier on @maubaron's playbook, compiled 2026-08-01 — one operator,
one product, largely self-reported in promotional contexts; treat its numbers as
order-of-magnitude anchors. Everything in §2–§9 is derived against this codebase at
`0.4.0`. Keep current: if a bet is taken, fold its builds into
[`ROADMAP.md`](ROADMAP.md) and leave this doc as the rationale.*
