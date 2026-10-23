---
id: photos
label: Photo record
span: Jul 11 · Jul 13 · Aug 29
versions: pre-0.4.0 / 0.4.0
accent: yellow
order: 1.5
sessions: 
start: 2026-07-11
end: 2026-08-29
band: no
---

## Photo record: past builds (July & August 2026)

The filenames carry the capture date and time (local Barcelona time, UTC+2 in summer). WhatsApp stripped EXIF, so there is no device model. All of these are **real-device captures**: iOS status bars, real keyboards, and screen-recording indicators. None come from the simulator. Pixel sizes: the July photos are 946×2048 (WhatsApp-recompressed screenshots), the Aug 29 photos are 471×1024 (re-forwarded, smaller), and the videos are 576×1248.

**Versioning note:** versioning started at **0.4.0 on 2026-07-25** (`94153f8`). The CHANGELOG folds everything before that ("19 commits, 2026-07-09 → 2026-07-25") into the 0.4.0 entry; it does not split it into 0.1 to 0.3. So the July batches are labelled **pre-0.4.0** (that work is recorded under 0.4.0).

**Main finding:** **three of the four batches show uncommitted work-in-progress, hours or days before the commit that landed it.** Abraham was sharing builds from his phone ahead of committing. The screen text proves this: strings and layouts that only exist in a *later* commit.

### Mapping table

| File(s) | Captured (local) | Commit SHA | Version | Confidence + evidence |
|---|---|---|---|---|
| `PHOTO-2026-07-11-01-47-41/42/42-2` | 07-11 01:45–01:47 (status bar 1:45/1:46) | **WIP between `c057968` (00:57) and `dabe62e` (13:12)** | pre-0.4.0 | High. At `c057968` the home is `"MOVIE CHAIN"` in **heavy rounded** type, a 🔗 glyph lockup, an orange trophy "Best chain N" badge, and a radial-heat background. The photo instead has a **serif** "Movie Chain", blue/purple squares, and a "Your best · 13 links" pill, all of which belong to the NYT reskin. But its tagline ("Link actors and movies. How long can your chain run?"), its pill-style Actors/Movies toggle and its "2 links · 108 pts" header row are in **neither** commit. This is an early iteration of the NYT redesign. Game-over strings ("TIME'S UP", "You were one away", BEST CHAIN / BEST PTS) do exist at `c057968`. |
| `PHOTO-2026-07-11-15-29-30`, `-30-2`, `-30-4` | sent 07-11 15:29, but status bar reads **1:45/1:46** | same as above (re-sent 01:47 screenshots) | pre-0.4.0 | High. Visually the same as the 01:47 batch (not byte-identical, because WhatsApp re-encoded them). Treat as duplicates. |
| `PHOTO-2026-07-11-15-29-30-3`, `-31`, `-31-2…-31-7` | 07-11 15:27–15:28 (status bar 3:27/3:28) | **`dabe62e` (13:12) + uncommitted Reel WIP**, committed later as `a99333e` (16:13) | pre-0.4.0 | High. The home copy "Actor → movie → actor. How long can you keep the chain alive?", "Your best · N links", the big Actor/Movie tiles ("start with a name / title") and the centred serif score hero all match `dabe62e` `SeedView`/`GameView`. A **"Your Reel · 11" pill and a whole Reel sheet are on screen ~45 min before `a99333e` was committed**. The Reel differs from what was committed: the hero reads "LOOK HOW MANY YOU KNOW / 13 logged" (committed: "You have logged"), there's a stats strip "4 CHAINS · 36 LONGEST · +13 THIS WEEK", and the filter has **All / Actors / Movies** (committed: Actors/Movies; no "LONGEST"/"THIS WEEK" strings exist in any committed `CollectionView`). |
| `VIDEO-2026-07-13-16-29-22.mp4`, `VIDEO-2026-07-13-16-30-03.mp4`, `PHOTO-2026-07-13-16-30-03` | 07-13 16:27–16:30 (status bar 4:27/4:28) | **WIP of `439c2e3` ("deal a start", committed 07-16 16:54)**, on top of `af4ca14`/`0a74c5e` | pre-0.4.0 | High. The home shows a "START WITH ⟨name⟩" card, "Shuffle", and "or search for your own start". `git grep` finds none of these strings at `af4ca14`; they first appear in `439c2e3`, **three days later**. The committed `af4ca14` home is a hero + live-search with a "Your best" pill, which isn't on screen. The Reel ("You have logged 27", Actors/Movies tabs, "🏆 Best chain · 5 links") matches committed `CollectionView`. |
| `PHOTO-2026-08-29-10-47-34` ×6, `VIDEO-2026-08-29-10-50-04.mp4` | 08-29 10:45–10:50 | **`6ce9429`** (0.4.0 tag `94153f8` + iOS 18 target; later commits to 08-08 are docs/skills only) | **0.4.0** | High. The committed build, not a design exploration. Gear button top-left (Settings, from `3af5d28`/kept in `94153f8`), "START WITH" card, Shuffle, "or search for your own start", "‹ Deal a start" search view, "CHAIN ENDED" / "PERSONAL BEST" game-over, and the Reel. All of these strings are in `94153f8`. It is in **light mode** (warm paper + ink), the light variant of the NYT palette. Neither Cream Neobrutalist (10-21) nor any `DESIGN-BRIEF.md` work (first committed 10-21 in `f812f1b`) is visible. |

---

### Batch 1: 2026-07-11, 01:45–01:47: NYT reskin, first iteration (pre-0.4.0)

This is the night of the gamification commit (`c057968`, 00:57). The phone is already running a **dark-mode, serif, blue/purple** build that isn't committed yet. Mid-reskin (inferred): the 13:12 `dabe62e` commit message describes the finished version of this look ("paper-warm neutrals, near-black ink, blue = actor, purple = movie, a serif wordmark + system sans, no flame/confetti/radial-heat").

![Home, 01:45. Dark canvas, serif "Movie Chain" wordmark over a two-square blue→purple lockup, tagline "Link actors and movies. How long can your chain run?", a "Your best · 13 links" pill, a pill-shaped Actors/Movies toggle (Actors lit periwinkle) and a "Search actors" field with "Pick your start" empty state. This intermediate copy and toggle never shipped in a commit; at c057968 the title was still "MOVIE CHAIN" in heavy rounded type with an orange trophy badge.](media/past-builds/PHOTO-2026-07-11-01-47-41.jpg)

![Play screen, 01:46. A speaker icon and Quit, a slim white linear timer bar (the TimerBar that replaced the ring), "2 links · 108 pts" left and "0:15" right. The chain is drawn as full-width flat category tiles (ACTOR Tom Cruise / MOVIE Magnolia (1999) / ACTOR Philip Seymour Hoffman), periwinkle for actors and orchid for movies, the "Connections" look. Prompt "Name a movie Philip Seymour Hoffman was in", input docked above the always-up dark keyboard, grey "Go". There's no centred score hero yet; dabe62e added it.](media/past-builds/PHOTO-2026-07-11-01-47-42.jpg)

![Game over, 01:46. "TIME'S UP", huge serif "2", "links · 108 pts", BEST CHAIN 13 / BEST PTS 564, a "You were one away: The Big Lebowski (1998) was in the filmography" near-miss card (the missedAnswer feature from c057968), a numbered "YOUR CHAIN" recap in the same tiles, a cream "Play again" and an outlined "Share". Tom Cruise → Magnolia → PSH timed out; the near-miss was a PSH film.](media/past-builds/PHOTO-2026-07-11-01-47-42-2.jpg)

### Batch 2: 2026-07-11, 15:27–15:28: `dabe62e` look + Your Reel before it was committed (pre-0.4.0)

Captured on the same phone (now on 5G) about two hours after the NYT redesign commit and about 45 minutes **before** "Add Your Reel collection" (`a99333e`, 16:13). Three files in this batch (`-30`, `-30-2`, `-30-4`) are re-sends of the 01:45 screenshots and are not new captures.

![Home, 15:27. dabe62e layout: a mini-chain lockup of four tiles plus a dashed "?" slot, serif wordmark, "Actor → movie → actor. How long can you keep the chain alive?", and two pills, "Your best · 36 links" and a NEW "🎞 Your Reel · 11". Two big category tiles (Actor "start with a name", Movie "start with a title"); the selected one gets a white outline. Best jumped from 13 to 36 links since 01:45.](media/past-builds/PHOTO-2026-07-11-15-29-31-7.jpg)

![Same home with Movie selected, 15:21. Shows a copy bug: "Search an movie to begin your chain." The article was hard-coded ("Search an \(kind)"); the string is identical in dabe62e and a99333e SeedView.swift.](media/past-builds/PHOTO-2026-07-11-15-29-30-3.jpg)

![Play, turn 0, 15:27. dabe62e GameView: time "0:29" centred between speaker and Quit, full white timer bar, a big serif "0" score hero over "0 pts", and the seed tile (ACTOR Tom Cruise) sitting just above the docked input.](media/past-builds/PHOTO-2026-07-11-15-29-31-6.jpg)

![Play, 3 links, 15:28. Serif "3", "161 pts". The ChainStack rises from the input: Tom Cruise → Mission: Impossible III (2006) → Philip Seymour Hoffman → Happiness (1998), prompt "Name an actor from Happiness". The MI:III link shows the Roman-numeral sequel matching working.](media/past-builds/PHOTO-2026-07-11-15-29-31.jpg)

![Game over, 15:28. "CHAIN ENDED" (not time's up), serif "3", "161 pts", a hairline-fenced "★ PERSONAL BEST 36 links · 1,688 pts" row and a green "🎞 2 new to your Reel · 13 total ›" link: the Reel hooking into game-over before it was committed. The numbered recap follows.](media/past-builds/PHOTO-2026-07-11-15-29-31-2.jpg)

![Your Reel sheet (top), 15:28. "LOOK HOW MANY YOU KNOW", serif "13 logged", 6 ACTORS (blue serif) / 7 MOVIES (purple serif) cards with coloured underlines, a stats strip "4 CHAINS · 36 LONGEST · +13 THIS WEEK" (green), "Your regulars: most logged" (PSH in 2 chains, MI:III), an All/Actors/Movies segmented filter and a headshot grid with ×N badges. The hero copy, stats strip and "All" tab were cut before a99333e (committed hero: "You have logged").](media/past-builds/PHOTO-2026-07-11-15-29-31-5.jpg)

![Reel, Actors tab, 15:28. The headshot grid: Philip Seymour Hoffman ×2, Tom Cruise ×2, Amitabh Bachchan, Mohanlal, Robert De Niro and Ben Stiller. Abraham's chains already mixed Hollywood and Indian cinema.](media/past-builds/PHOTO-2026-07-11-15-29-31-4.jpg)

![Reel, Movies tab, 15:28. Poster grid with green "NEW" badges on this run's adds (MI:III, Happiness) and ×1 counts: Ram Gopal Varma Ki Aag (2007), Meet the Fockers, Along Came Polly, Magnolia and Tropic Thunder. The art is streamed TMDB posters (AsyncImage at the time).](media/past-builds/PHOTO-2026-07-11-15-29-31-3.jpg)

### Batch 3: 2026-07-13, 16:27–16:30: the "deal a start" home three days early (pre-0.4.0)

This was captured after `af4ca14` (11:50, "hero+live-search home") and `0a74c5e` (12:00 docs). The home on screen is **not** `af4ca14`'s; it is the play-first **dealt start** that was only committed on **07-16** as `439c2e3`. Both videos are on-device screen recordings (red record pill, then 4:27). The Reel shows 27 logged and "Best chain · 5 links", much lower than the 36-link best two days earlier. That suggests a reinstall or wiped data, or possibly another phone (inferred). The battery is at 12–13%.

[▶ VIDEO-2026-07-13-16-29-22.mp4](media/past-builds/VIDEO-2026-07-13-16-29-22.mp4) (9.4 s): tapping **Shuffle** repeatedly deals The Hunger Games → The Dark Knight → Gary Sinise → Brett Cullen → Jessica Chastain → Inception.

![Frame ~0 s: the WIP dealt-start home in dark mode. Mini-chain lockup, serif wordmark, shorter tagline "How long can you keep the chain alive?", a Reel corner pill "🎞 27" top-right (the "Your best" pill is gone, moved into the Reel per 439c2e3), a large light "START WITH • The Hunger Games" card (the ink button inverted for dark mode), "→ Name an actor in it", an outlined "Shuffle", and the underlined link "or search for your own start" at the bottom.](media/past-builds/frames/v0713a-01.jpg)

![Frame ~3 s: after a Shuffle the deal flips to an actor, "START WITH • Gary Sinise" with a blue dot, and the hint changes to "→ Name a movie they were in". Brett Cullen comes up next, which shows the deal pool still surfacing less-famous names before the vote_count tuning that 439c2e3's message describes (inferred).](media/past-builds/frames/v0713a-03.jpg)

[▶ VIDEO-2026-07-13-16-30-03.mp4](media/past-builds/VIDEO-2026-07-13-16-30-03.mp4) (7.4 s): scrolling the Reel sheet and switching Actors/Movies.

![Frame ~0 s: Reel top, "You have logged 27", 13 ACTORS / 14 MOVIES, "🏆 Best chain · 5 links", regulars Tom Hanks (4 chains) and Saving Private Ryan, an Actors/Movies filter with no "All". This matches committed CollectionView at af4ca14.](media/past-builds/frames/v0713b-01.jpg)

![Frame ~3 s: scrolled actor grid: Russell Crowe, Ryan Gosling, Emma Stone, Al Pacino, Robert De Niro, Robin Williams, Vin Diesel, Tom Cruise and Ben Stiller, each with ×N badges.](media/past-builds/frames/v0713b-03.jpg)

![Photo 16:30 (status bar 4:28): Reel, Movies tab. "You have logged 27", Saving Private Ryan ×2, Iron Man (2008), The Circle (2017), Toy Story 5… Wi-Fi, 12% battery.](media/past-builds/PHOTO-2026-07-13-16-30-03.jpg)

### Batch 4: 2026-08-29, 10:45–10:50: the 0.4.0 build in light mode

There are no commits that day. The last code commit was `6ce9429` (07-25, iOS 18 target) and the last commit overall `c2a2d90` (08-08, skills). What's on screen is the **committed 0.4.0 build**, not a design exploration: every string is in `94153f8`, and nothing of Cream Neobrutalist or the 10-21 `DESIGN-BRIEF.md` appears. This is a month-long pause between 0.4.0 and the 0.5.0 overhaul, and the app was being played (Reel at 70 → 78 logged).

Possibly someone else's phone (inferred). The keyboard is **Italian + English** ("IT EN"), the phone has a Dynamic Island, and it runs in **light mode**, whereas the July phone showed "EN" only and dark mode. The Reel stats (Tom Hanks / Brad Pitt regulars, best 11 links) also differ from Abraham's July numbers. On the other hand, a light-mode switch plus an added keyboard on the same phone would also explain it. The app-switcher label reads "movie-quiz", so it's a dev install, not TestFlight under a product name (inferred).

![Home, 10:45. Light-mode 0.4.0: gear (Settings) top-left, Reel pill "🎞 70" top-right, mini-chain lockup, serif "Movie Chain", "How long can you keep the chain alive?", a big ink "START WITH • Bob Gunton" card, "→ Name a movie they were in", an outlined Shuffle and "or search for your own start". The palette is pale periwinkle/orchid on white paper.](media/past-builds/PHOTO-2026-08-29-10-47-34.jpg)

![Home with a movie dealt: "START WITH • The Dark Knight Rises", "→ Name an actor in it".](media/past-builds/PHOTO-2026-08-29-10-47-34-5.jpg)

![Play, 10:46. A black linear timer bar at 0:28, serif "1", "55 pts", tiles MOVIE The Dark Knight Rises (2012) → ACTOR Christian Bale, prompt "Name a movie Christian Bale was in", a warm-grey input pill and a grey "Go" over the light keyboard (IT EN).](media/past-builds/PHOTO-2026-08-29-10-47-34-3.jpg)

![Game over, 10:46. "CHAIN ENDED", serif "1", "55 pts", "★ PERSONAL BEST 11 links · 531 pts", "🎞 1 new to your Reel · 71 total ›", a 2-item recap, a black "Play again" and an outlined Share.](media/past-builds/PHOTO-2026-08-29-10-47-34-4.jpg)

![Your Reel, 10:45. "You have logged 70", 33 ACTORS / 37 MOVIES on warm-grey cards, "🏆 Best chain · 11 links", regulars Tom Hanks (4 chains) and Saving Private Ryan (2), and a headshot grid (Tom Hanks ×4, Brad Pitt ×3, Robert Downey Jr. ×3).](media/past-builds/PHOTO-2026-08-29-10-47-34-2.jpg)

![Search ("‹ Deal a start"), 10:46: serif wordmark, Actor/Movie segmented toggle with Actor in pale blue, "Search actors" field, "Pick your start / Search an actor to begin your chain." Fixed copy since July: "an actor" now reads correctly.](media/past-builds/PHOTO-2026-08-29-10-47-34-6.jpg)

[▶ VIDEO-2026-08-29-10-50-04.mp4](media/past-builds/VIDEO-2026-08-29-10-50-04.mp4) (78 s): an on-device screen recording (red dot in the Dynamic Island), roughly 10:48–10:49 on the clock. It starts in the iOS app switcher on the "movie-quiz" card, plays two runs, opens search and the Reel, and ends in Control Center to stop the recording.

![~0 s: the iOS app switcher with the movie-quiz card (its game-over screen still showing) next to HBO Max, Ridemovi and YouTube. The app-switcher label is the project name, "movie-quiz".](media/past-builds/frames/v0829-01.jpg)

![~5 s: fresh deal on resume: "START WITH • Gina Carano"; Reel pill 71. The dealFreshOnResume behaviour is working.](media/past-builds/frames/v0829-02.jpg)

![~20 s: mid-run, score "2" with a green "+56" FloatingGain popping beside it; the chain tiles Brad Pitt → Ocean's Eleven (2001) → George Clooney are caught overlapping mid-drop (the ChainStack "drop" spring).](media/past-builds/frames/v0829-05.jpg)

![~25 s: score 3, "150 pts": Brad Pitt → Ocean's Eleven → George Clooney → Up in the Air (2009); typing "Anna kendr…" for "Name an actor from Up in the Air".](media/past-builds/frames/v0829-06.jpg)

![~35 s: the "‹ Deal a start" search with "M" typed shows "No matches / Try a different spelling." A one-letter query reads as a failed search rather than "keep typing". Probably the debounce had not fired yet or one-letter queries returned nothing (inferred).](media/past-builds/frames/v0829-08.jpg)

![~45 s: second run, Mohanlal → Thudakkam (2026), typing "Vismaya" (Vismaya Mohanlal) with the Italian keyboard suggesting "Vidimata / Vistata". A Malayalam film from 2026 resolves, so the TMDB data is live and current.](media/past-builds/frames/v0829-10.jpg)

![~50 s: game over: "CHAIN ENDED 2", "125 pts", personal best 11 links · 531 pts, "3 new to your Reel · 78 total", recap Mohanlal / Thudakkam (2026) / Vismaya Mohanlal.](media/past-builds/frames/v0829-11.jpg)

![~55 s: Your Reel at 78 (37 actors / 41 movies), regulars Brad Pitt (4 chains) and Saving Private Ryan; the Movies grid has NEW badges on Thudakkam and Ocean's Eleven.](media/past-builds/frames/v0829-12.jpg)

![~60 s: scrolled actor grid while the sheet is mid-drag. Two tiles (Isa Frias and one other) show the **typographic/silhouette placeholder** because TMDB had no headshot. That's the "no path falls back to a placeholder" path from a99333e, visible in the wild. Also on screen: Heath Ledger, Chris Evans, Christopher Plummer, Christoph Waltz, Cate Blanchett.](media/past-builds/frames/v0829-13.jpg)

---

### Visual evolution notes (for a "how it looked then vs now" post)

- **Wordmark:** at `c057968` (07-11 00:57) it was "MOVIE CHAIN" in heavy rounded caps with a 🔗 glyph lockup. By 01:45 the phone showed a serif "Movie Chain" with a blue→purple two-square lockup. In dabe62e the lockup grew into a 4-tile mini-chain plus a dashed "?" slot. On 10-22 it became the "unspool" wordmark with blue/yellow circles (Claude Design export, below).
- **Palette:** pre-NYT used system colours with an orange trophy and a radial-heat background. From 07-11 it was the NYT/Connections palette: periwinkle = actor, orchid/purple = movie, near-black canvas in dark mode, paper white in light mode (Aug 29). From 0.5.0 (10-22) it is Cream Neobrutalist: cream canvas, ink borders, hard shadows, coral primary, and **movie yellow replaced purple**.
- **Home concept:** five homes in about three and a half months.
  1. Search-first with a pill toggle (07-11 01:45).
  2. Big Actor/Movie category tiles plus search (`dabe62e`, 07-11).
  3. A hero plus live search with a compact toggle (`af4ca14`, 07-13 commit; not photographed).
  4. A dealt "START WITH ⟨name⟩" card with Shuffle and search demoted to a link (WIP on 07-13, committed 07-16, shipped as 0.4.0).
  5. "The sentence": "⟨name⟩ *was in* / a movie…", where the blank itself is the start button (10-22 Claude Design export → `ca813f6`).
- **"Your best":** a pill on the home in July. It moved into the Reel ("Best chain · N links") with the deal-a-start home, and came back as a "BEST RUN 13 links" footer line in the sentence design.
- **Chain rendering:** flat full-width category tiles ("ACTOR Tom Cruise") stacked upward from the docked input (ChainStack, July–0.4.0; the overlap is visible mid-drop in the Aug video). Game over used the same tiles, numbered. In 0.5.x it became the physical **Deck** (cards with art, a pile peeking above) and compact cards in the recap.
- **Score:** "2 links · 108 pts" in a header row (01:45 WIP), then a big centred serif number hero (dabe62e onward). The serif numeral survived into the Cream Neobrutalist type system.
- **Timer:** a circular ring (`TimerRing`, until c057968), replaced by a slim linear bar (white in dark mode, black in light mode). The bar persists today (`TimerBar.swift`).
- **Reel:** first seen 45 min before its commit, with a richer stats strip (chains / longest / this week) and an All tab that were cut before commit. It stayed a stats + regulars + poster/headshot grid (×N badges, NEW badges) through 0.4.0. In 0.5.2 it became playing cards (actors) and framed posters (movies) with paper/inked/holo tiers, no numbers on the fronts.
- **Settings:** no gear in July. A gear top-left appears with the (later removed) Assisted mode work and stays in 0.4.0 (Aug 29). Now a gear pill sits beside the Reel pill, top-right.
- **Devices:** July captures are from Abraham's phone (EN keyboard, dark mode, home indicator). Aug 29 is a Dynamic Island phone in light mode with an IT/EN keyboard, possibly a tester's (inferred).

### Evening of 2026-10-22: external items

![The sentence · home: a Claude Design export (saved 22:36) titled "The sentence · home (try it: tap the blank, type, press Go)". Cream canvas, "unspool" lowercase serif wordmark with a blue+yellow double-o, a Reel pill "62" and a round gear button with ink borders. An actor avatar in an ink ring plus a blue "ACTOR" chip, the huge serif "Chris Hemsworth", italic grey "was in", a blank "a movie…" on an ink underline with a coral square → button, "⤨ Someone else" and "🔍 Pick your own" beneath, and a footer "BEST RUN 13 *links* · tap the blank to start". This is the design that `ca813f6` (23:00, "Make the home the first turn: a sentence that hands off into play") built 24 minutes later. In the build the shuffle/search labels became "Deal again" / "Pick your own" per CLAUDE.md.](media/external/The-sentence-home@2x.png)

*(Three other files dropped in at the same time — IMG_1926, IMG_1927, 347.jpg — were unrelated personal screenshots and have been removed from the diary.)*

### Media index

- `media/past-builds/PHOTO-2026-07-11-01-47-41.jpg`: 07-11 01:45, home, NYT reskin first iteration (WIP before dabe62e), dark.
- `media/past-builds/PHOTO-2026-07-11-01-47-42.jpg`: 07-11 01:46, play screen, 2 links / 108 pts, Tom Cruise → Magnolia → PSH.
- `media/past-builds/PHOTO-2026-07-11-01-47-42-2.jpg`: 07-11 01:46, game over "TIME'S UP 2", near-miss The Big Lebowski.
- `media/past-builds/PHOTO-2026-07-11-15-29-30.jpg`: duplicate (re-send) of the 01:45 home.
- `media/past-builds/PHOTO-2026-07-11-15-29-30-2.jpg`: duplicate (re-send) of the 01:46 game over.
- `media/past-builds/PHOTO-2026-07-11-15-29-30-4.jpg`: duplicate (re-send) of the 01:46 play screen.
- `media/past-builds/PHOTO-2026-07-11-15-29-30-3.jpg`: 07-11 15:21, dabe62e home, Movie tile selected, "Search an movie" copy bug, Reel pill (WIP).
- `media/past-builds/PHOTO-2026-07-11-15-29-31-7.jpg`: 07-11 15:27, dabe62e home, Actor tile selected, best 36, Reel · 11.
- `media/past-builds/PHOTO-2026-07-11-15-29-31-6.jpg`: 07-11 15:27, play turn 0, serif score hero, Tom Cruise seed.
- `media/past-builds/PHOTO-2026-07-11-15-29-31.jpg`: 07-11 15:28, play at 3 links (MI:III, PSH, Happiness).
- `media/past-builds/PHOTO-2026-07-11-15-29-31-2.jpg`: 07-11 15:28, game over "CHAIN ENDED 3", "2 new to your Reel".
- `media/past-builds/PHOTO-2026-07-11-15-29-31-5.jpg`: 07-11 15:28, Reel WIP top: "13 logged", stats strip, All tab.
- `media/past-builds/PHOTO-2026-07-11-15-29-31-4.jpg`: 07-11 15:28, Reel WIP, Actors grid.
- `media/past-builds/PHOTO-2026-07-11-15-29-31-3.jpg`: 07-11 15:28, Reel WIP, Movies poster grid with NEW badges.
- `media/past-builds/VIDEO-2026-07-13-16-29-22.mp4`: 07-13 16:27, 9.4 s, Shuffle cycling dealt starts (439c2e3 WIP).
- `media/past-builds/VIDEO-2026-07-13-16-30-03.mp4`: 07-13 16:28, 7.4 s, scrolling the Reel (27 logged).
- `media/past-builds/PHOTO-2026-07-13-16-30-03.jpg`: 07-13 16:28, Reel Movies tab, 27 logged, best chain 5.
- `media/past-builds/PHOTO-2026-08-29-10-47-34.jpg`: 08-29 10:45, 0.4.0 light home, START WITH Bob Gunton.
- `media/past-builds/PHOTO-2026-08-29-10-47-34-5.jpg`: 08-29 10:45, home, START WITH The Dark Knight Rises.
- `media/past-builds/PHOTO-2026-08-29-10-47-34-2.jpg`: 08-29 10:45, Reel, 70 logged, best 11 links.
- `media/past-builds/PHOTO-2026-08-29-10-47-34-3.jpg`: 08-29 10:46, play, TDKR → Christian Bale, IT EN keyboard.
- `media/past-builds/PHOTO-2026-08-29-10-47-34-4.jpg`: 08-29 10:46, game over "CHAIN ENDED 1", 71 total.
- `media/past-builds/PHOTO-2026-08-29-10-47-34-6.jpg`: 08-29 10:46, "Deal a start" search view.
- `media/past-builds/VIDEO-2026-08-29-10-50-04.mp4`: 08-29 ~10:48–10:49, 78 s screen recording of 0.4.0: two runs, search, Reel.
- `media/past-builds/frames/v0713a-01.jpg`: frame ~0 s of the 07-13 deal video, START WITH The Hunger Games.
- `media/past-builds/frames/v0713a-03.jpg`: frame ~3 s, START WITH Gary Sinise.
- `media/past-builds/frames/v0713b-01.jpg`: frame ~0 s of the 07-13 Reel video, Reel top (27 logged).
- `media/past-builds/frames/v0713b-03.jpg`: frame ~3 s, scrolled actor grid.
- `media/past-builds/frames/v0829-01.jpg`: ~0 s, app switcher with the "movie-quiz" card.
- `media/past-builds/frames/v0829-02.jpg`: ~5 s, fresh deal on resume (Gina Carano).
- `media/past-builds/frames/v0829-05.jpg`: ~20 s, "+56" floating gain, tiles mid-drop.
- `media/past-builds/frames/v0829-06.jpg`: ~25 s, 3 links, Up in the Air.
- `media/past-builds/frames/v0829-08.jpg`: ~35 s, search "M" → "No matches".
- `media/past-builds/frames/v0829-10.jpg`: ~45 s, Mohanlal → Thudakkam (2026), typing Vismaya.
- `media/past-builds/frames/v0829-11.jpg`: ~50 s, game over 2 links, 78 total.
- `media/past-builds/frames/v0829-12.jpg`: ~55 s, Reel 78 logged, Movies tab.
- `media/past-builds/frames/v0829-13.jpg`: ~60 s, actor grid with silhouette placeholders.
- `media/external/The-sentence-home@2x.png`: 10-22 22:36, Claude Design export "The sentence · home", the model for ca813f6.
