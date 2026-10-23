---
id: design-resync
label: Re-sync & analytics
span: Oct 23 10:35 – 14:12
versions: 0.7.0
accent: yellow
order: 6
sessions: bb139731 8aa6b002 4227355d c300b3a3 02d88d55
start: 2026-10-23
end: 2026-10-23T14:12
---

## Era: After the cut — housekeeping, then analytics and a launch plan (2026-10-23)

**Arc.** 0.6.0 had been cut and tagged at 10:32, and the diary had just written itself up for the first time. The morning's last half hour was housekeeping that turned out to matter. First, a check on whether the diary's `SessionEnd` hook really fires when a VS Code tab is closed: it does. Then Abraham went back to the session that had built the **Design System artifact** the evening before. That system still described the app as it was at 0.5.3: "Movie Chain", a mini-chain lockup, the coral "Start with" card, and pastel-bar app icon. Everything it was built to help design had since shipped. "I think this needs to be updated because we reworked the home screen and logo etc". Over about fifteen minutes the system was re-synced to 0.6.0 Unspool:
- the real mark, wordmark, icons and film strip;
- the home as the first turn;
- the Reel cards, which hadn't been drawn at all the first time.

Two snags came up on the way. The Claude account had flipped back to work, so the artifact wasn't reachable. And the new logos rendered as broken images in the previews. No app code changed in this chapter.

### 2026-10-23 ~10:35 — "What constitutes a session end?" (session bb139731)

**Ask (verbatim):** "What constitutes a session end? and should i run a diary command now?"

- Claude's answer:
  - The hook fires on a clean end: `/exit`, Ctrl+D, Ctrl+C twice, or `/clear`, which starts a new session id.
  - `/compact` and resuming are not ends.
  - A killed session (crash, force-closed terminal, Mac shutdown) misses the hook. `/diary` begins with a backfill for exactly that reason.
  - The only real gap is a killed session left for more than 30 days, because Claude Code deletes old transcripts after that.
  - Sessions opened before the hook existed may not run it, because hooks load at session start. The backfill covers those too.
- Claude also wasn't sure whether closing a VS Code tab counts: "I haven't checked that this fires the hook in VS Code".
- **Abraham tested it:** "i'll open a chat tab and close it and can you check if the hook fires?" Claude noted the baseline: 10 sessions, index last written 10:29. It warned that a tab closed with **no prompts** would be skipped by the capture and look like a failure.
- Abraham's test was more useful than the empty tab he'd planned: "i just ran a diary on a tab that i had to update, can yo usee if the hook ran after i closed that tab". That tab was session `8aa6b002`, the planning chat. In it, `/diary` had expanded chapter 05's planning entry and merged it as PR #12 (`7193b94`, merge `700851b`).
- **The evidence** in `diary/raw/`:

  | What | When | Effect |
  |---|---|---|
  | `/diary`'s backfill in that tab | 10:39 | every session rewritten at once |
  | The tab's last message | 10:41 | — |
  | Tab closed | ~10:42 | only `8aa6b002` rewritten, now ending 10:41 with 11 prompts |

  A single session rewritten a minute after its last message can only be the hook.
- **Settled:** closing a tab in VS Code counts as a session end.
- **Should he run `/diary`?** "No": the first run had just brought chapter 05 up to the morning. The advice was to run it at the end of the next working day and before tagging 0.7.0.

### 2026-10-23 ~10:43 — "this needs to be updated because we reworked the home screen and logo" (session 4227355d)

**Ask (verbatim):** "I think this needs to be updated because we reworked the home screen and logo etc"

This was the same session that had built the design system at 18:21 the evening before (see chapter 05). It was resumed, so it still had the full build in context.

- **Account snag, again.** Claude Code was signed in as the work account. The design system lives on Abraham's personal account, and from work it's a 404. The read came back as "artifact not found — it may have been deleted, or it has not been shared with you". Rather than stall, Claude prepared the whole update locally and asked him to `/login` before publishing.
- **What had changed since the snapshot** (`4d296ee` → `700851b`, 204 files):
  - **Colours:** none. The asset catalog's colours were untouched.
  - **Brand art:** new `LogoMark`, `Wordmark` and `FilmStrip` image sets, each an SVG with an on-dark variant, and three app icons (cream, dark, tinted).
  - **Type:** `Theme` gained `cardStamp` (SF heavy, 7pt) and nine motion values: `handoffSpring` and `handoffDuration`, `tiltIn`, `tiltOut`, `tiltRelease`, `layoutOut` and `layoutIn`, `swapSettle`, `dealOut`.
  - **The home was rewritten:** `SeedView` (643 lines changed) plus the new `Handoff.swift`.
- Claude rendered the wordmark with `qlmanage` to check it, since the SVG is outlined paths. It's "unspool" in Fraunces Display Bold, with the blue and yellow circles as the "oo".

  ![The shipped wordmark rendered from wordmark.svg: lowercase "unspool" in heavy serif, with the "oo" replaced by an overlapping blue circle and yellow circle, ink outlines, and a black lens where they overlap. Rendered to see what the outlined SVG actually draws.](media/4227355d/render_wordmark.svg.png)

- **Read from the code, not the changelog:**
  - **The sentence:** `SentenceType` fixes the name at 44pt and the verb and blank at 34pt.
  - **The avatar** is 40×40 with radius 20.
  - **The blank's arrow** is a 48×48 coral key with a 3pt ink rule under the row.
  - **The pills** are 40pt tall.
  - **Two presses:**
    - The home's text links and pills use `PressScaleStyle` (97% scale, dim).
    - The blank's arrow keeps the neobrutalist shift-and-collapse.
  - **The handoff** is the exception to the forward screen push.
- **A contrast catch:** the blank's arrow is `ink` on `coral`. That's 5.0:1 in light, but in dark `ink` is cream, and cream on coral is **2.5:1**, under the 3:1 floor for icons. It was recorded on the token and in the component's notes, not fixed. The system keeps the source's values exact and flags misses.
- **Also caught:** the old cover's tagline, "How long can you keep the chain alive?", no longer appears anywhere in the app. The cover now uses the home sentence instead.

### 2026-10-23 ~10:47 — "must also be in the diary for these or just run the simulator"

**Ask (verbatim, sent mid-turn; it doesn't appear in the raw capture):** "I also think this needs to the capture the reel cards we set up the latest ones , must also be in the diary for these or just run the simulator"

- The first build of the design system had left the Reel cards out ("Not drawn: the Reel cards…"). Since then they had become collectible cards (chapter 05, ~00:14).
- **Diary or simulator?** Both were checked. The diary's best shots of the fronts (`628e4dd2/fronts2.png`, `lift2.png`, ~00:21) **predate** `aa78047`, "Drop the HOLO label from holo cards". They show "NO. 001 · HOLO", while the shipped card says only "No. 001". So the simulator was the honest source.
- **Simulator gotcha (twice in one morning):**
  - `-destination 'platform=iOS Simulator,name=iPhone 16'` matches no device here, though an "iPhone 16" exists. The likely cause is the simulator list holding duplicate device names across runtimes (inferred). xcodebuild prints the device list and the visionOS "not installed" note, and the pipeline still exits 0.
  - The first "build" therefore produced no app, and `simctl install` crashed on a missing path.
  - Building by device id (`id=CB60E1E7-…`) worked. The release session had hit the same thing at 10:28.
- Launched with the DEBUG flags already in the code: `-uiDemoReel -uiOpenReel`, then `-uiLiftFirst`.

  ![Simulator, iPhone 16, the shipped Reel: "You have logged 42", BEST CHAIN 13 links, the Your regulars cards (Keanu Reeves, The Matrix), ACTORS 13 / MOVIES 29, and the grid: No. 001 Keanu Reeves on a rainbow holo face with an amber duotone photo and five full dots, No. 002 Tom Hanks on a lilac pastel face in purple duotone, No. 004 Margot Robbie on paper in cyan duotone, all with green NEW badges. Taken as the reference for the ReelActorCard component.](media/4227355d/shots_reel-grid-sm.png)

  ![Simulator: Keanu's card lifted out of the dimmed grid via -uiLiftFirst. "NO. 001" top left and the two-circle mark top right on the holo foil face, amber duotone photo, white name plate "Keanu Reeves" with five filled dots, FLIP and CLOSE buttons beneath. No hard shadow under the lifted card. Shows what the static preview can only describe.](media/4227355d/shots_reel-lifted-sm.png)

  ![Simulator: the shipped home. "unspool" wordmark top left, the Reel pill (film stack, 42) and gear top right; a round Morgan Freeman avatar and blue ACTOR chip; "Morgan Freeman" in big serif; "was in" in muted italic; "a movie…" over an ink rule with a coral arrow key; "Deal again" and "Pick your own"; BEST RUN 13 links centred at the foot. Taken to check the redrawn HomeScreen preview against.](media/4227355d/shots_home-sm.png)

- The rest of the card spec came from `ReelCards.swift` and `Duotone.swift`. Cards are drawn at a 110pt design width, 5:7, and scaled as one picture:
  - Paper → pastel at 5 films → holo at 11, with five progress dots.
  - The "No. 027" collector number in `cardStamp`, tracked 0.9.
  - The `LogoMark` 8pt tall in the corner.
  - A green NEW capsule tilted 8°.
  - Posters sit in a 4pt ink moulding with a 7pt mat.
- The five duotone pairs went into the tokens, from `Duotone.palette`:
  - pink `#802966` / `#ffc2eb`
  - lilac `#4c389e` / `#d6c7ff`
  - cyan `#0d5478` / `#b8edff`
  - mint `#126145` / `#c2f7d9`
  - lemon `#8c540f` / `#fff2b2`

### 2026-10-23 ~10:54 — "what are we signed in as now", then the publish

- Abraham re-logged in, then asked: "what are we signed in as now". The answer, his personal account, came from reading the artifact's index. That proved access and was the required pre-publish read in one call. The index showed it still titled "Movie Chain", untouched.
- "yeah" → Claude read every file it would replace and compared each with its own last publish: all 14 were identical.
- **Uploaded** the 11 brand files and screenshots: mark ×2, wordmark ×2, film strip, three icons, and three simulator shots.
- **Published version 5.** The system is renamed **Unspool**.
  - **New components:** `LogoMark`, `SentenceStart`, `Blank`, `DealLinks`, `ReelActorCard`, `ReelFrame`.
  - **Redrawn:** `Wordmark`, `HomeScreen`, `CornerPill`, the cover.
  - **The old `StartButton`** was moved to `archived/`, not deleted.
- **A warning, explained:** the publish reported that the version it replaced "was saved from the artifact's page". That was the page's own save in between, inferred to be its generated token stylesheet. Since every replaced file had just been read from that exact version, nothing was lost.

### 2026-10-23 ~10:57 — "logos seem broken"

**Ask (verbatim):** "logos seem broken", with a screenshot:

![Abraham's screenshot of the published LogoMark row: two broken-image icons with alt text "Unspool" and three empty ink-bordered rounded squares with alt text "App icon", "App icon, dark", "App icon, tinted"; under them, the page's caption "Static preview — see the note above." The bug report.](media/4227355d/pasted-1.png)

- **Cause:** the previews referenced the uploads as `/_blob/<id>`. The Design System page renders previews in a static frame that can't reach the upload store. The type's docs list `/_blob/<id>` as a valid preview source, so the failure only showed live.
- **Fix:** every `/_blob/` reference in the previews was replaced with a `data:` URI of the same file. The mark and wordmark SVGs were embedded as shipped, and the icons were downscaled to 256px to keep previews small (LogoMark preview: 60KB, under the 256KB cap). Four previews were republished as version 7: LogoMark, Wordmark, HomeScreen and ReelActorCard.
- The uploads stay: the Assets tiles render them fine.
- Abraham: "perfect thanks".
- Claude saved a memory: the system's link, that it lives on the personal account, and "previews need data: URIs".

### Where things stand (2026-10-23 ~10:58)

- **0.6.0 is out** (`3ffaf90`, tagged `v0.6.0`). `main` is `700851b`, with the diary's planning write-up merged as PR #12.
- **The Unspool design system** (https://claude.ai/artifact/Ba9rkPwbqAvpgQe9HUtZnz, personal account) matches 0.6.0:
  - 27 components, including the Reel cards;
  - the shipped brand art;
  - three simulator screenshots as reference.
- **Still not drawn:** the back of a Reel card, game over, search results and Settings.
- **The first, empty "Movie Chain Design System" artifact** is still on the work account (https://claude.ai/artifact/QtUBJFdqC8sNWHqYsSna6Y). The offer to delete it got no answer.
- **The hook is proven** for tab close in VS Code.
- **Next on the roadmap:** 0.7.0 Foundations (see chapter 05's plan).

## Era: Foundations begin — PostHog, a real phone, and a launch plan (2026-10-23 midday)

**Arc.** "Alright visually we're all there." The look was done; what was left was the work that makes an app something other people can use. In under two hours the first 0.7.0 piece went from a question ("can posthog handle both crash reports and user interaction tracking?") to two merged PRs. PostHog went in with ~10 events. Then the app went onto Abraham's actual iPhone for the first time in this stretch, after a fight with library Wi-Fi. Then the event set was redesigned three times in twenty minutes, each time around what he wanted to *know*: how long runs take, what people type, which Reel cards they pick up. A volume budget (1M free events a month) shaped the final version. A `/swift-review` found one real bug. The analytics became a documented, enforced system so "whatever model or engineer is working here" plugs into it. Meanwhile, in a second tab, Abraham turned two Chris Raroque videos into a launch track for the roadmap, picked Supabase, and asked for Apple, Google and email sign-in. Both landed on `main` at 13:45.

### 2026-10-23 ~12:11 — "Now its a bunch of technical work to get this prod and people ready right?" (session c300b3a3)

**Ask (verbatim):** "Alright visually we're all there. Now its a bunch of technical work to get this prod and people ready right?"

- Claude read the roadmap rather than answering from memory. Mostly yes, with one exception: the **Daily Chain** is specced but has never been played, and the roadmap itself says to playtest it on index cards before building. That's the biggest risk to launch, and it isn't technical.
- What 0.7.0 actually needs: logging (the app had **zero** log statements and 18 places that catch an error and discard it), crash reports, analytics, automated builds to TestFlight, a device id, and a disk cache of the deal pool.
- One roadmap line was already stale: "back the code up, there's no remote". There was one, `abematt/movie-chain` on GitHub.

### ~12:16–12:20 — PostHog for crashes? Sentry instead

- "can posthog handle both crash reports and user interaction tracking?" Claude searched instead of guessing: PostHog has iOS error tracking, but it's **experimental** (an Experimental SPI import, no visionOS autocapture, crashes reported on next launch).
- "Whats the then established posthog equivalent free enough to start easy for a solo app builder/founder…" → **Sentry** (mature Swift SDK, a free tier for one developer, and it covers the 0.8.0 server too). **Firebase Crashlytics** was the alternative: free with no cap, but it brings in Firebase and covers the app only.
- **Decision:** PostHog for what players do, Sentry for what breaks, Xcode Organizer as the free backup.

### ~12:20 — "okay i've set up posthog" → the first build (`afb7eaa`, 12:28)

Abraham pasted PostHog's iOS setup snippet, project token included.
- **The token went into the gitignored secrets plist, not source.** A `phc_` token is meant to ship in apps, but the repo is public, and a token in it would let anyone's build report into the project. A fresh clone with no token sends nothing.
- The Swift package was added by editing `project.pbxproj` directly (no Xcode UI in the loop). It resolved to posthog-ios 3.92.3.
- **Built to the roadmap's rules:** a small closed event set fired from the views, never `GameEngine` (the same split as haptics and sound); an injected `Analytics` with a no-op default so tests and previews never send; autocapture, screen views, replay, surveys and feature flags off; a "Share usage data" toggle in Settings.
- **A stable device id** (`DeviceID`), made on first launch, became PostHog's anonymous id through the SDK's `getAnonymousId` hook. That's also a 0.7.0 item, and it means the 0.9.0 account can claim the events made before sign-in.
- **Gotcha avoided:** the hook closure is called by the SDK from any thread. Under main-actor-by-default, a plain closure would be inferred main-actor and could trip a runtime isolation check, so it's written `{ @Sendable _ in deviceID }`.
- **Debug builds tag every event `debug_build: true`**, so Abraham's own play can be filtered out.
- In the simulator: PostHog's anonymous id on disk was exactly the device id. 82 tests green.

### ~12:29–12:36 — "is the app on my mobile?" — the library network

- It wasn't. The iPhone 16 Pro showed as paired but "unavailable".
- "it is on the same network now" — still unavailable. A browse for the phone on the local network found nothing.
- "yeah im on a library network". Library Wi-Fi blocks devices from seeing each other, so nothing on the Mac side could fix it.
- "hot pot jined" … "sorry hotspot means no internet". Still unavailable on the hotspot: the phone had never been set up for wireless builds, which needs one cable connection first.
- "cable connected" → wired, connected, built, installed and launched in about three minutes. Signing worked with the existing development profile.

### ~12:39 — the first events, and "no don't push"

- Abraham pasted the first PostHog activity. A whole run arrived in order on the phone: `deal_again` → `run_started` → four `link_landed` → `run_ended` → `play_again` → `reel_opened` → `pick_your_own_opened` → backgrounded.
- Claude read two things off it: PostHog counts the first launch with its SDK as "Application Installed", and the simulator showed a duplicate "Application Opened" (it disappeared in a later export, so it was a display glitch).
- Claude started to push and open the PR. Abraham stopped it: **"no don't push i need to talk through it, from this is it clear how long a game session was, how long they stayed on certain screens etc ?"**

### ~12:40–12:51 — what do you actually want to know?

**Ask (verbatim):** "Also i'd like a little more granular detail on their game play for example, how long their game session is, how long they take in between turns etc … do they open the cards, which cards, anmd how long they check there, do they flip etc,"

- **The honest answer:** run length could only be worked out roughly from timestamps. Time between turns was misleading, because the gap between two `link_landed` events includes waiting for the next turn's answers to load (the clock pauses then). Time on screens wasn't possible: the app is one SwiftUI root, so PostHog's automatic screen views can't see the changes.
- "yeah tmdb id is good"
- **"Why is raw typed text not sendable? is that some privacy concern there ? i'd like to know what people type for their prompts in the turns"** → It's free text, so a player could type anything (a name, a number), and it changes the privacy label. But it's the most useful data a recall game has: common wrong answers, and whether the spelling tolerance is too strict. **Decision:** send it, clipped to 60 characters, with the TMDB id of what was being shown, and say so in Settings.
- **"but aren't we going to put all the details like which movies and actors they've guessed into a db once we add login ?"** → Partly. The account database will hold what the player *owns* (the Reel, records, daily results), and only for players who sign in. Misses, typing and timings aren't the player's data to restore. The rule: **the database is for the player, PostHog is for you.**
- **"assume that after launch i have about 100 active players, with the granularity im looking for , how fast am i hitting the limit"** → about 100 events per session, so ~300k a month at 100 daily players. The 1M free tier would be reached at ~330 daily players.
- **"what can we scale down while still maintaing usability"** → fold events into properties: no screen events (a screen's time rides on the event that ends it), misses as a list on their turn, one `card_viewed` per Reel card. About 47 events a session, so **~700 daily players** on the free tier.
- "yes lets do it"

### ~12:51–12:57 — the lean event set (`4564787`)

- **The engine records, never sends.** `GameEngine.Turn` captures each answered turn: what was shown, what was typed, the misses, think time (only while the clock runs) and load wait. The summary gained the final turn's misses, play time and retries. A new `Telemetry` object is the one thing the views call.
- Events: `run_started` (seed, dealt or picked, deals before starting, time on home and on the previous game over), `link_landed`, `run_ended`, `card_viewed`, `reel_closed`, `turn_load_failed`, `share_tapped`.
- **Settings line rewritten**, because the first build promised "never names or answers": now "How you play — your turns, what you type, what you look at in your Reel…".
- The phone got the new build over the cable.

### ~13:01 — "i swiped up and closed the app and it didn't show up as an event there"

- iOS kills a swiped-away app with no warning, so there can never be a "closed" event. **Application Backgrounded** is the last word, and if the kill lands mid-send it goes out on the next launch with its original timestamp.
- Proven a few minutes later: the Backgrounded event from 12:58:32 arrived after the relaunch.
- **A duplicate `reel_closed`** showed up 0.36s apart. Abraham's CSV export settled it: **same event uuid**, identical properties, different `$sent_at`. The batch was sent just before the kill and sent again on relaunch. PostHog adjusted each copy's timestamp by its send time, so they may not merge. Not an app bug; documented as "count distinct uuid".
- The CSV also confirmed the detail end to end, e.g. a run that died on *Spotlight* after "What" and "Batman", with play time 32.8s = 2.8s answering + the 30s final turn, and the near-miss recorded.

### ~13:05 — "i want whatever model or engineer is working hree to know to plug into the posthog system"

**Ask (verbatim):** "I guess my question is as the app grows with more modes and events and settings and login and stuff , i want whatever model or engineer is working hree to know to plug into the posthog system and that the system be flexible and modular enough to work within that"

- What existed only explained the code to someone already reading it. Nothing pointed a newcomer at it, CLAUDE.md didn't mention analytics, and nothing stopped a direct `PostHogSDK.shared.capture` from anywhere.
- Then: **"Yeah i think before we add that we should do a swift review to make sure things are being done in the correct way"**.

### ~13:06 — `/swift-review` finds one real bug (`5e280d9`, 13:09)

- Mid-review Abraham asked "is this equivalent to but if not do a /swift-review" — it was the command itself, already running.
- **The bug:** in `startGame`'s prefetch path, the load wait was added to the run's record *after* an `await`, without checking the run was still current. A reset during that wait left the abandoned game's wait on the next run's first turn. The other load path already guarded this with the `generation` token.
- **Fixed and proven:** a test using the existing `RaceProvider` pattern, plus an injected clock for the engine. Removing the guard makes the test fail; restoring it passes.
- Also fixed: the Reel sheet now records its own visit; PostHog starts from a `static let` rather than inside a SwiftUI `@State` initial value; one constant for the opt-out key; a tuple became a struct.

### ~13:09–13:13 — analytics as a system (`c32e5d7`)

- **`docs/ANALYTICS.md`**, the tracking plan: every event and property, eight rules ("a property before an event"), and a checklist for adding analytics to a feature. A test reads the doc and fails if its event list and `EventName` disagree; Claude checked it catches a missing heading.
- **`Telemetry` split** into a core plus `Telemetry+Runs.swift` and `Telemetry+Reel.swift`; a new mode adds its own file.
- **Shared context on every event:** `mode`, `signed_in`, `sound_on`, `schema`. Settings are properties, never events.
- **Identity hooks for 0.9.0:** `signedIn(accountID:)` / `signedOut()`.
- **Two new `swift-check` rules:** PostHog only in `Analytics.swift`; no telemetry in `GameEngine`. Both fired on deliberate test files.
- CLAUDE.md got an Analytics section; `/swift-review` checks analytics on user-facing changes. 93 tests green.

### 2026-10-23 ~13:10 — Chris Raroque's playbook, in another tab (session 02d88d55)

Abraham pasted the transcript of Chris Raroque's "how to start an app" video and asked how Unspool compares.
- **On building, Unspool already follows him:** a better workflow on an existing genre, small first, analytics before the first user, revert after failed attempts (Assisted mode), building in public (this diary).
- **On distribution it was far behind:** the plan put the first real user at 1.0, 6–9 months away.
- **"Lets diivde this into different buckets"** — building tools and services, and marketing. Abraham remembered a landing-page tool; it wasn't in that video.
- A second paste (the launch video plus a sponsored video about the no-code builder *Anything*) answered it: **Framer** for the waitlist and landing pages, **FormSpark** for forms, **UserJot** or Canny for a feedback board, **Loops** for email, 3–4 days on store screenshots because Apple's new-app boost lasts about two weeks, and launch only when beta players keep coming back. One line from the Anything video confirmed the TMDB proxy plan: keep API keys on a backend, never in the app.

**Abraham (verbatim):** "these are all good lets roll it into our plan, I think eventually the email stuff is good too because i do feel like it'd be good to build a community around the app, but anyway, this tells me in my mind that we should have google,apple and normal email logins

and yes supabase but i'm a little concerned about safety there and then i want to do notifications also probably with firebase ?"

- **Sign-in:** Apple, Google, and email with a **one-time code**, so no passwords are ever stored. Offering Google makes Sign in with Apple mandatory anyway. Marketing email is a separate opt-in.
- **Supabase, with the worry taken seriously:** the key the app ships is public by design, so row-level security is the only lock on each table. Rules: RLS on every table, deny by default; the `service_role` key never in the app; important writes through Edge Functions; the security advisor before every schema change.
- **Firebase for notifications: no.** On iOS its messaging only relays to Apple's push service, which an Edge Function can call directly. Revisit only for Android.
- **The TestFlight question, closed:** still nothing on the App Store before 1.0, but a TestFlight beta drawn from the waitlist, and launch decided on its week-1 retention.
- Written into ROADMAP.md as a "launch track" alongside the milestones. Nothing was committed in that tab.

### ~13:23–13:45 — splitting the work, and both PRs merged

- "alright i did some roadmap work also in another tab". That tab had edited the same checkout, so its changes sat uncommitted on the analytics branch.
- **A surprise, and Claude's mistake:** `origin/feature_posthog-analytics` already existed on GitHub at the first commit. Claude said it hadn't pushed and that it "must have been you or the other tab". It was Claude's own 12:39 command (inferred): one command that pushed and then opened the PR. Abraham's stop landed after the second-long push had finished but before the PR step, and the transcript logs the whole command as "rejected". GitHub held exactly the 12:39 commit and no PR, which fits. No harm done; the branch waited there until the PRs were approved.
- "its done there so yeah do your split thing" → stashed, branched `feature_roadmap-launch-track` from `main`, applied cleanly, and fixed two stale "Sign in with Apple only" lines (`f568ce4`). On the analytics branch, ANALYTICS.md gained "the account id is the Supabase user id — never an email" and how beta players separate from launch players (`$is_testflight` plus `debug_build`) (`5882b30`).
- "go ahead" → PRs **#14** (analytics) and **#15** (roadmap), opened at ~13:42.
- "merge in both, and then yeah i'll work on the sentry stuff soon" → merged at 13:45 (`2271bc6`, `d1dd1a4`). `main` builds and passes all 93 tests.

### ~13:49–14:12 — the diary write-up, and a correction it forced

- `/diary` extended this chapter (`e1d1296`). Writing it up meant re-reading the 12:39 stop in the raw capture, and that showed the "mystery" branch was Claude's own push.
- Claude's first note to Abraham called it an open question ("if you remember doing it, I'll correct that line"). **Abraham (verbatim):** "don't understand". The plain version: one command pushed and then opened the PR; the stop landed between the two; the log calls the whole thing "rejected".
- The chapter was corrected (`db8e43f`). Claude saved a memory: after a stopped command, check the real state before saying what ran, and don't chain a push with other steps.
- "go ahead" → pushed, PR #16 opened and merged, each step checked separately this time (`c20124f`, 14:10).

### Where things stand (2026-10-23 ~14:12)

- **On `main`:** PostHog analytics (7 events, shared context, a tracking plan, enforced boundaries) and the device id — two of the 0.7.0 items. The roadmap has a launch track, Supabase, three sign-in options and a TestFlight beta.
- **Still open for 0.7.0:** OSLog logging, Sentry crash reports (Abraham's next), automated TestFlight builds, the deal-pool disk cache.
- **Unconfirmed:** `share_tapped` on a real device (a `simultaneousGesture` on a `ShareLink` may not fire).
- **Not decided:** discarding IP addresses in PostHog's project settings.

### Decision log

| Time (local) | Decision | Rationale | Source |
|---|---|---|---|
| 10:36 | Don't run `/diary` again yet | Its first run had just brought chapter 05 up to the morning; run it end of day and before tagging 0.7.0 | bb139731 |
| 10:37 | Test the hook with a tab that has at least one prompt | The capture skips prompt-less sessions, so an empty tab would look like a failure | bb139731 |
| 10:42 | Closing a VS Code tab counts as a session end | Only `8aa6b002` was rewritten, a minute after its last message; a backfill rewrites everything at once | bb139731 |
| 10:44 | Prepare the re-sync locally, publish after `/login` | The design system is on the personal account; the work account gets a 404 | 4227355d |
| 10:45 | Use the shipped SVG/PNG brand art, never redraw the mark | The mark and wordmark are finished assets; a redraw would drift | 4227355d |
| 10:46 | Flag cream-on-coral (2.5:1, dark) rather than fix it | The design system mirrors the source exactly and records misses on the token | 4227355d |
| 10:47 | Capture the Reel cards from the simulator, not the diary | The diary's card shots predate `aa78047` (HOLO label dropped) | 4227355d |
| 10:48 | Duotone pairs become colour tokens | They're the cards' printed inks, fixed per actor by TMDB id | 4227355d |
| 10:52 | Archive `StartButton`, don't delete it | It no longer exists in code, but the move keeps the old design's record | 4227355d |
| 10:53 | Cover tagline = the home sentence | "How long can you keep the chain alive?" no longer appears in the app | 4227355d |
| 10:57 | Embed preview images as `data:` URIs | The static preview frame can't load `/_blob/` uploads | 4227355d |
| 12:12 | Start 0.7.0, and playtest the Daily Chain on paper alongside it | Foundations needs no design calls; the Daily Chain is the one untested design risk | c300b3a3 |
| 12:18 | PostHog for behaviour, Sentry for crashes, Xcode Organizer as backup | PostHog's iOS error tracking is experimental; Sentry is mature and covers the server too | c300b3a3 |
| 12:22 | PostHog token in the gitignored secrets plist, not source | The repo is public; a fresh clone sends nothing | c300b3a3 |
| 12:24 | The device id is PostHog's anonymous id | A future account can claim pre-sign-in events | c300b3a3 |
| 12:24 | Events fire from views; the engine never sends | Same split as haptics and sound; keeps the engine pure and testable | c300b3a3 |
| 12:39 | Don't push yet | "i need to talk through it" | c300b3a3 |
| 12:44 | Send typed text, clipped to 60 characters | What people try is the game's most useful data; the opt-out and privacy label cover it | c300b3a3 |
| 12:45 | The account database is for the player, PostHog is for the developer | Behaviour isn't the player's data to restore; signed-out players are only in PostHog | c300b3a3 |
| 12:48 | Few events, rich properties (~47 a session) | 1M free events a month holds ~700 daily players instead of ~330 | c300b3a3 |
| 12:49 | No screen events; a screen's time rides on the event that ends it | Screen events were the biggest share of volume | c300b3a3 |
| 12:52 | Record `dragged`, not `tilted`, on Reel cards | The gyro tilts every lifted card, so tilted would always be true | c300b3a3 |
| 13:03 | Duplicate on kill-and-relaunch is not an app bug | Same uuid, different `$sent_at`: the SDK re-sent the batch | c300b3a3 |
| 13:05 | Review before building the framework | "make sure things are being done in the correct way" | c300b3a3 |
| 13:08 | Inject the engine's clock | Makes think time and the race fix testable | c300b3a3 |
| 13:11 | A tracking plan the tests check, and `swift-check` boundaries | So the next model or engineer plugs in instead of going around | c300b3a3 |
| 13:11 | Settings and mode are shared context on every event | A new mode reuses the run events; no extra volume | c300b3a3 |
| 13:22 | Sign in with Apple, Google, or email one-time code | No passwords stored; Apple is required once Google is offered | 02d88d55 |
| 13:22 | Supabase for the service, RLS on every table | The shipped key is public, so table rules are the only lock | 02d88d55 |
| 13:22 | No Firebase; push from an Edge Function to APNs | On iOS, Firebase messaging only relays to APNs | 02d88d55 |
| 13:22 | TestFlight beta from the waitlist; launch on week-1 retention | Don't spend the App Store's two-week boost without knowing the app holds anyone | 02d88d55 |
| 13:40 | Roadmap on its own branch and PR | It has nothing to do with the analytics change | c300b3a3 |
| 13:40 | The account id is the Supabase user id, never an email | Apple emails may be relays; one person can sign in several ways | c300b3a3 |
| 14:08 | Correct the diary: the first push was Claude's | The raw capture shows the stop landed after the push and before the PR | c300b3a3 |
| 14:09 | Push, open the PR and merge as separate, checked steps | A stopped multi-step command can leave its first step done | c300b3a3 |

### Story material

- **A design system out of date by morning.** Built at 18:34 to help design a new home and logo, it described an app that no longer existed by 10:32 the next day. Both of the things it was made for had been designed, built and shipped overnight, partly from mocks made with it. The re-sync was the system catching up with its own output.
- **The account ping-pong.** The system lives on the personal account. Claude Code was on work at 18:21, personal by 18:34, work again by 10:43, and personal at 10:54. Each switch is a `/login`. Each time, the tool's answer from the wrong account is a plain "not found", which reads like deletion. It's in memory now, plus a standing rule to check the account before publishing.
- **The diary versus the truth.** The diary's own screenshots were three commits stale. "NO. 001 · HOLO" became just "No. 001", because "a holo card shows it's holo, never says so". The simulator, launched with flags the code already had for screenshots, was the faster honest source.
- **Docs said it works.** `/_blob/<id>` is listed as a valid preview image source, but the live page's static frame couldn't load it. The fix was the boring one: inline the bytes.
- **The hook test that ran itself.** Abraham meant to open an empty tab to test the hook. Instead he closed a tab where `/diary` had just done real work, and that was a better test.
- **The library Wi-Fi.** Five messages to get the app onto a phone on the desk: "try now", "it is on the same network now", "yeah im on a library network", "hot pot jined", "sorry hotspot means no internet". A cable did it in three minutes.
- **"no don't push i need to talk through it."** The first build was done and verified on a real phone. Stopping it led to the version that answers his actual questions: how long people think, what they type, which cards they pick up.
- **Three event designs in twenty minutes**, each shaped by a number: ~10 events (first build), ~100 a session (everything he wanted), ~47 a session (folded into properties, ~700 daily players free).
- **A real run, read back from a spreadsheet.** Mark Ruffalo → "Spotlight" in 2.8 seconds, then 30 seconds of "What" and "Batman" before time ran out, with the answer he missed recorded. The analytics work in one row.
- **The swipe-up kill that sent one event twice.** Same uuid, a different send time. What looked like a bug was the SDK delivering an event it wasn't sure had arrived.
- **A YouTube video became a roadmap section.** Two Chris Raroque transcripts pasted into a second tab turned into the launch track: Framer, Loops, UserJot, a TestFlight beta, and "launch when they come back after a week".
- **"Rejected" doesn't mean "didn't run".** Abraham stopped a push-then-open-PR command; the push had already gone through. Claude believed the log, called the branch a mystery and suggested Abraham had pushed it, until the diary write-up made it look again.
- **Two tabs, one checkout.** The roadmap tab wrote into the same working folder the analytics work was on. It was untangled with a stash and a branch from `main`, and the two PRs merged cleanly within minutes.

### Media index

- `media/4227355d/pasted-1.png`: Abraham's "logos seem broken" screenshot of the LogoMark row (broken images, empty icon tiles). 10:57.
- `media/4227355d/render_wordmark.svg.png`: `wordmark.svg` rendered with qlmanage to see the outlined wordmark. 10:45.
- `media/4227355d/render_film-strip.svg.png`: `film-strip.svg` rendered the same way: a cream strip with ink sprocket holes. 10:45.
- `media/4227355d/shots_home.png`, `shots_home-sm.png`: simulator, the shipped 0.6.0 home (Morgan Freeman was in a movie…). ~10:51.
- `media/4227355d/shots_reel-grid.png`, `shots_reel-grid-sm.png`: simulator, the demo Reel grid with holo, pastel and paper cards. ~10:50.
- `media/4227355d/shots_reel-lifted.png`, `shots_reel-lifted-sm.png`: simulator, Keanu's holo card lifted (`-uiLiftFirst`). ~10:51.
- `media/4227355d/ds_upload2_home.png`, `ds_upload2_reel-grid.png`, `ds_upload2_reel-lifted.png`: the same three screenshots as uploaded to the design system.
- `media/4227355d/ds_upload2_AppIcon-1024.png`, `ds_upload2_AppIcon-1024-dark.png`, `ds_upload2_AppIcon-1024-tinted.png`: the shipped 0.6.0 app icons (cream, ink and tinted tiles) as uploaded.
- `media/4227355d/ds_icons256_AppIcon-1024*.png` (×3): the icons downscaled to 256px for embedding in the LogoMark preview. 10:57.
- Sessions `c300b3a3` and `02d88d55` captured no screenshots or images; the PostHog exports quoted above were pasted as text.
- `media/4227355d/ds_upload_app-icon-1024.png`: the pre-0.5.0 icon (pastel blue and purple bars on near-black) uploaded to the first build of the system on Oct 22 ~18:33. It belongs to chapter 05's 18:21 entry and is indexed here because that chapter didn't list this folder.
