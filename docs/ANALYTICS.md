# Analytics — the tracking plan

What the app measures, why, and how to add to it. **Every user-facing feature reports
through `Telemetry`; read this before building one, and update it in the same change.**
`AnalyticsTests` fails if the events below and `EventName` in the code disagree.

PostHog (product analytics) is the only destination. It answers *how people play*:
where runs end, how long turns take, what people try, how the Reel gets used, who comes
back. It is **not** the record of anything the player owns — scores, the Reel, streaks
and daily results live on the device and, from 0.9.0, in the account database. Don't
query the account database for analytics, and don't put behaviour in it.

## Where it lives

| File | Job |
|---|---|
| `Analytics.swift` | The sink: `EventName`, the `Analytics` protocol, `NoAnalytics`, `PostHogAnalytics`, `DeviceID`. **The only file that may import PostHog.** |
| `Telemetry.swift` | The core views call: sink, clock, shared context, screens (incl. `deal_failed`), identity, `send`. |
| `Telemetry+Runs.swift` | `run_started`, `link_landed`, `turn_load_failed`, `run_ended`. |
| `Telemetry+Reel.swift` | `card_viewed`, `reel_closed`. |
| `GameEngine.Turn`, `Summary` | Plain facts the engine records (think time, misses, load time). **The engine never calls `Telemetry`.** |

`swift-check` enforces both bold rules.

## The rules

1. **A property before an event.** The free tier is 1M events a month; the app spends
   about 47 a session, which holds ~700 daily players. A new event has to earn its
   place against that; most new facts belong on an event that already fires.
2. **A screen's time rides on the event that ends it.** There are no screen events.
   Home time is on `run_started`, play time on `run_ended`, game-over time on the next
   `run_started`, Reel time on `reel_closed`.
3. **Settings and setup are context, not events.** `Telemetry.Context` is added to every
   event (`mode`, `signed_in`, `sound_on`, `schema`). A new setting adds a field there.
4. **A new mode reuses the run events** and sets `context.mode`. Its own events, if it
   needs any, go in `Telemetry+<Mode>.swift` with its own state struct.
5. **Ids, not names.** Actors and movies are TMDB ids. Typed text is the one free text
   sent, clipped to 60 characters (`Telemetry.typedLimit`).
6. **Durations are measured in the app**, on an injected clock, and sent as properties:
   `_s` (seconds, one decimal) or `_ms` (integer).
7. **Names are snake_case**, events are `noun_verb` past tense (`run_started`), and a
   property means the same thing on every event it appears on.
8. **Bump `Telemetry.schema`** when an existing property changes meaning. Adding one
   doesn't need a bump.

## Adding analytics to a feature

- [ ] Which question will this answer? If none, don't send it.
- [ ] Can it be a property on an event that already fires? (Usually yes.)
- [ ] If it's a new event: add the `EventName` case, a section below, and check the
      volume estimate.
- [ ] Build it in the right `Telemetry+<Area>.swift`; views call it, the engine doesn't.
- [ ] Test it in `AnalyticsTests` with the recording sink and the fake clock.
- [ ] Privacy: new kind of data → update the privacy-label note in `ROADMAP.md` (1.0)
      and the app's section of https://playunspool.com/privacy (`privacy.html` in
      `unspool-site`), so the label and the page agree.
- [ ] Check it on a device: debug builds tag every event `debug_build: true`.

## Shared on every event

| Property | Meaning |
|---|---|
| `mode` | Which game: `endless` (the Daily Chain adds `daily`) |
| `signed_in` | Whether the player is signed in (always `false` before 0.9.0) |
| `sound_on` | The sound setting |
| `schema` | The tracking plan's version (`Telemetry.schema`) |
| `debug_build` | Present and `true` on development builds; filter it out of charts |

PostHog adds its own (`$app_version`, `$os_version`, `$session_id`, `$device_model`,
location from the IP, …). Its lifecycle events — **Application Installed / Updated /
Opened / Backgrounded** — are on, and carry PostHog's properties but not ours.

## Events

### `run_started`

A run began. Every event until `run_ended` carries the same `run_id`.

| Property | Meaning |
|---|---|
| `run_id` | New for each run |
| `seed_id`, `seed_kind` | The start (TMDB id, `actor` / `movie`) |
| `source` | `dealt` (the home deal) or `picked` (searched for) |
| `deals_before_start` | "Deal again" taps since the home screen appeared |
| `home_s` | Time on the home screen before starting (time in the background excluded) |
| `game_over_s` | Time on the previous game-over screen; absent on a session's first run |

### `link_landed`

A correct answer.

| Property | Meaning |
|---|---|
| `run_id`, `link` | The run, and the chain's new link count |
| `prompt_id`, `prompt_kind` | What the player was answering from |
| `answer_id` | What they named (TMDB id) |
| `typed` | What they typed for it (clipped) |
| `misses` | Rejected attempts this turn, in order: not on the list, or already in the chain |
| `answer_ms` | Think time: the clock running, start of turn to accepted |
| `load_ms` | Waiting for this turn's answers to load, before its clock started |
| `fast` | Beat the speed-bonus threshold |

### `turn_load_failed`

A turn's answers couldn't load and the Retry button replaced the answer field.
`run_id`, `links`.

### `deal_failed`

The home couldn't deal a start: the deal pools didn't load after every attempt and
no saved copy was on the device to fall back on, so the home showed its "Out of film."
no-connection screen.
Rare by design (the pools are cached on disk), so it costs almost nothing in volume,
and it's the one failure that strands a player before any run event fires.

| Property | Meaning |
|---|---|
| `retries` | "Reconnect" taps before this failure (0 on the first) |
| `home_s` | Time on the home screen so far |

### `run_ended`

A run is over, by timeout or Quit. Sent once, from the phase change.

| Property | Meaning |
|---|---|
| `run_id`, `reason` | `timeout` or `quit` |
| `links`, `points`, `new_best`, `reel_additions` | The outcome |
| `duration_s` | Wall time, `run_started` to game over |
| `play_s` | Time the clock ran (loading excluded; the last turn capped at its 30s) |
| `avg_answer_ms`, `slowest_answer_ms` | Over answered turns; absent with no links |
| `wrong_guesses` | All misses in the run, the last turn's included |
| `final_prompt_id`, `final_misses` | The turn the run ended on, and what was tried there |
| `near_miss_id` | The answer shown as "you were one away" (timeouts only) |
| `retries` | Manual retries after failed loads |

### `share_tapped`

The Share button was tapped (whether the share was sent isn't knowable). `from`:
`game_over` or `reel`.

### `card_viewed`

A Reel card or poster was lifted and put back (or still out when the sheet closed).

| Property | Meaning |
|---|---|
| `tmdb_id`, `kind` | Which card |
| `linked` | Links through it (an actor's films, a movie's actors) |
| `finish` | Actors only: `paper`, `pastel` or `holo` |
| `duration_s` | Time out of the grid |
| `flipped` | Turned over at least once |
| `dragged` | Tipped with a finger (the gyro tilts every card, so it isn't recorded) |

### `reel_closed`

A visit to the Reel ended.

| Property | Meaning |
|---|---|
| `from` | `home` or `game_over` |
| `duration_s` | Time on the sheet |
| `cards_viewed`, `flips` | Across the visit |
| `filters` | Tabs, decades and genres chosen, in order: `tab:movies`, `decade:1990`, `genre:18` |

## Identity

Before an account, the anonymous id is the **device id** (`DeviceID`, made on first
launch). From 0.9.0, `Telemetry.signedIn(accountID:)` ties events to the account (and
PostHog links the device's earlier events to it); `signedOut()` returns to the device
id. Person profiles are only created for identified players.

**The account id is the Supabase user id — never an email**, whichever way the player
signed in (Apple, Google or an email code). An Apple email may be a private relay, and
one person can sign in different ways on different devices; when Supabase links those
identities into one user, PostHog follows because the id is the same.

**Beta vs launch:** PostHog marks TestFlight installs itself (`$is_testflight`), and
development builds carry `debug_build`, so the beta's week-1 retention — the launch
decision — reads cleanly without a property of our own.

## Privacy

The Settings toggle "Share usage data" (`Telemetry.enabledKey`) stops everything,
lifecycle events included. Declared on the privacy label (1.0): Product Interaction,
Other User Content (typed answers), Device ID — not linked to identity, not used for
tracking, no ATT prompt. PostHog also records the IP and a city by default; turning on
"Discard client IP data" in the project settings drops the IP.

## Known quirks

- An event can arrive twice if the app is killed mid-send: the SDK sends the batch
  again on next launch. Both copies have the same `uuid`; count distinct `uuid` where
  exact counts matter.
- A swipe-up kill gives no "closed" event — **Application Backgrounded** is the last
  word, and it may arrive on the next launch.
