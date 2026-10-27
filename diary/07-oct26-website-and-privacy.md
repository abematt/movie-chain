---
id: website
label: Site, money & service
span: Oct 25 15:41 – Oct 27 08:41
versions: after 0.7.0 (unreleased)
accent: blue
order: 7
sessions: 4f948fc0 be4a0e49 716720e0 875718fd b738c613 e81853bc
start: 2026-10-25
end: 2026-10-27T08:41
---

## Era: 0.7.0 is tagged, and the website talks back (2026-10-26)

**Arc.** The overhaul was merged and written up, and nothing happened in this session overnight. The morning's first message was three words, "go ahead and finish up", and what finishing meant was cutting **0.7.0**: Ground & Object plus the first foundations, tagged on GitHub. Then the app repo met the website. Abraham pasted a handover document that the site's own repo had written for it, and the next half hour was working through what it asked: roadmap entries that were out of date, two Settings links, and a privacy page that needed an app section and a named person. The privacy question ended with a timing correction. The page doesn't need the app section when the app goes live; it needs it before the first TestFlight invite, because that's when someone else's play data starts reaching PostHog. Two other tabs asked one-line questions on the side, about the feature-request service and marketing notes. The site work itself happened in a different session in the site's own repo, which this diary doesn't capture (inferred: the site's commits and the handover weren't written in any session captured here).

### 2026-10-25 ~15:41 — "do you remember" (session be4a0e49)

**Ask (verbatim):** "in our youtuber research we found a service for users to suggest features, do you remember"

- A short tab. Claude searched the repo and its own project history instead of answering from memory, and found it: **UserJot**, with Canny named as the pricier alternative. It came from the two Chris Raroque transcripts pasted during the Oct 23 design resync, the same source as Framer, FormSpark, Loops and the TestFlight-beta plan.
- It sits in `docs/ROADMAP.md` under "Before the beta": a board linked from Settings where players post and upvote requests, so what they want is visible rather than guessed. The 1.0 "Send feedback" email stays, for bug reports.
- Nothing was changed. This is the board that the Settings link at 08:29 the next morning opens.

### 2026-10-26 ~08:02 — "go ahead and finish up" → 0.7.0 (session 4f948fc0)

**Ask (verbatim):** "go ahead and finish up"

- Read as: cut the version. The repo's rule is to write the diary chapter first, and chapter 06 already covered everything under `[Unreleased]`. Checked state first: `main`, in sync, clean.
- **What the cut changed:** `[Unreleased]` became `[0.7.0] — 2026-10-26` with a summary paragraph. `MARKETING_VERSION` went to 0.7.0 in all four build configurations. The roadmap table, CLAUDE.md's "Currently" line and its tagging example (now 0.7.0 → 0.8.0), and the diary README were updated to match.
- **Decision: Ground & Object ships *in* 0.7.0, alongside the first foundations.** The roadmap had 0.7.0 as foundations only, with Ground & Object "taking the next minor version when it is cut". Everything since 0.6.0 was one body of unreleased work, so it became one version, and the roadmap now says logging, crash reporting and the build pipeline are still to come under it.
- **Decision: leave `CURRENT_PROJECT_VERSION` at 1.** No build is being submitted anywhere; the CLAUDE.md rule is to bump it for a submitted build.
- All 113 tests passed on the iOS 18.0 simulator before the commit. PR #31 (`34a37a0`) was merged at 08:05 (`f2d6c4c`), and `v0.7.0` was tagged on the merge commit and pushed.
- **Bug:** the first attempt to commit, merge, tag and stop the preview server in one shell line was blocked by the safety hook as a force push. Nothing had run. The cause was `pkill -f` on the same line as `git push` (inferred: the hook saw a `-f`). Splitting the commands fixed it.

### ~08:06 — "here's the info about the landing page"

**Abraham (verbatim):** "here's the info about the landing page" (a pasted `handover-app.md`)

- The document was written in the site's repo, `unspool-site`, **for agents and people working in the app repo**. By then the site was on its own domain, **playunspool.com** (Cloudflare Registrar, about $11 a year, the only cost), hosted as a Cloudflare Worker that deploys on every push to `main`. The waitlist was a D1 database. There was a privacy page, a contact address on the domain, and the UserJot board at unspool.userjot.com.
- **What it asked of the app:** five things. Update roadmap entries that predated the site; add the app's section to the privacy page before the beta goes beyond Abraham; link the site from Settings (Privacy policy, Suggest a feature, Contact); keep the DEBUG flags the site's screenshots depend on stable; and keep the claims the landing page makes true.
- **Decision: apply the docs half at once, and take the code and the wording as separate steps.** The roadmap and CLAUDE.md changes went in as PR #32 (`0ea869b`, merged 08:07 as `9cf4575`).
- What PR #32 recorded: the waitlist is live on playunspool.com with no Framer, FormSpark or Loops, and the beta pool is a CSV export from D1. The 0.8.0 service goes on a subdomain (e.g. `api.`), never the bare domain or `www`. App Store Connect's support URL must be a web page, not a `mailto:`, so the site adds `/support` before launch. The analytics checklist gained a step: a new kind of data also updates the app's section of the privacy page, so the label and the page agree. CLAUDE.md gained a short "The website" section listing the flags, the promises, and the privacy status.
- **A fact worth keeping from the handover:** on football match days Spanish ISPs block Cloudflare's IP ranges under a court order, so the site, and any service behind Cloudflare's proxy, is unreachable from Movistar and Vodafone while a match is on. Abraham is in Spain, so this affects testing.
- Claude's closing question: should it start on the Settings links, and who is named on the privacy page as controller?

### ~08:26 — "name me, but yeah get started"

**Abraham (verbatim):** "name me, but yeah get started"

- **Decision: Abraham Mathew is named as the controller on the privacy page**, a person, not a company. Privacy law expects the person responsible to be named, and the handover had flagged that the page said only "an independent developer". Alternative not taken: a company name, since there isn't one.
- **Settings links** (PR #33, `abcd1b5`, merged 08:29 as `0f2347d`). A "Privacy policy" row under the usage-data switch; a new Feedback section with "Suggest a feature" (opens the UserJot board) and "Contact" (a mail to the site's address). The three URLs live in `Config`. Rows are 44pt, use the app's object style and press scale, and carry an accessibility hint that the link leaves the app.
- **Decision: the three links send no analytics.** The tracking plan's rule is a property before an event, and none of these answers a question about play: the board counts its own visits. Recorded in `docs/ANALYTICS.md`.
- Added `-uiOpenSettings` (DEBUG), which opens the Settings sheet on the home screen, so it could be screenshotted; documented with the other QA flags. Checked light and dark; 113 tests pass.

![Settings in light mode: the Share usage data switch with the new Privacy policy row under it, then a Feedback section with Suggest a feature and Contact, then About with version 0.7.0 (1). Taken to check the new rows. Share usage data reads off only because the screenshot launch passes the analytics-off flag.](media/4f948fc0/shots_s-settings.png)

![The same Settings sheet in dark mode: the new rows keep the same hard side, with the ground lifted.](media/4f948fc0/shots_s-settings-dark.png)

### ~08:30 — the privacy page's app section

- Claude read the current page, then the app's code for the facts, not the handover's summary: PostHog's host and configuration (lifecycle events on; screen views, replay, surveys, flags and swizzling off; opt-out honoured), the device ID made on first launch, the TMDB hosts the phone calls directly, and the list of events in the tracking plan.
- **What the app section says:**
  - *How you play:* a random ID not tied to a name, email or Apple ID; runs, with typed answers cut to 60 characters, timings, misses and how it ended; Reel views; app lifecycle; device, iOS and app version; rough location from the IP; sent to PostHog in the US; **Settings → Share usage data** stops it. The basis given is legitimate interest in improving the game.
  - *Films and actors:* TMDB sees the phone's IP.
  - *On the phone only:* chains, best run, the Reel, settings and the saved film lists.
  - *Sharing:* the picture and text go only where the player sends them.
  - *The beta and crash reports:* TestFlight shows testers' names and emails in App Store Connect; feedback and crash reports arrive with any screenshot or comment.
  - The services list gained PostHog, TMDB and Apple, and the rights section says play data can't be looked up by name.
- It was drafted as **PR #1 on the site repo** (`privacy-app-section`), with the site's docs updated to match. Merging deploys straight to playunspool.com, so it was left unmerged for Abraham.
- **Three things Claude flagged but didn't resolve**, because they're decisions: analytics is on by default with an opt-out, and EU rules on storing an identifier on a device may expect consent first; there is no stated retention period for play data; and a deletion request can't find play data, since it isn't linked to a person. Offered fixes: show the random ID in Settings, or add a "delete my play data" action.

### ~08:32 — "once the app goes live, right?"

**Abraham (verbatim):** "for the privacy page i thought we'd update that stuff once the app goes live right?"

- **Decision: the app section goes live just before the first TestFlight invite**, not now, and not at App Store launch. Claude agreed with the instinct and moved the date. The handover's own deadline was "before TestFlight goes beyond Abraham, or before the App Store submission at the latest". While he is the only person running the app there is nothing for the page to cover. The moment a tester runs it, their play data reaches PostHog from the first launch, so the page has to describe the app by the day the invites go out. Alternatives rejected: merge it now; wait for the App Store.
- Until then the new "Privacy policy" row opens a page that covers the website only, which is fine for a build only he runs.

### ~08:33 — "lets note this all down"

**Abraham (verbatim):** "lets note this all down"

- Written in three places, plus a note to self. All in the app repo, because merging anything in the site repo deploys it:
  - `docs/ROADMAP.md`, "Before the beta": the page covers the app before the first invite; the draft is waiting in the site PR; re-check it against the code, update what's changed, merge it; settle the three flagged points in the same pass. PR #34 (`ee3e710`, merged 08:34 as `86418b5`).
  - CLAUDE.md's website section: the draft is in the PR and merges before the first beta invite.
  - A comment on the site PR: hold until the first invite, with the same checklist.
  - Claude's own memory note about the site, with Abraham's decision and its date.
- The site repo's own docs were left alone.

### ~08:34 — "its time to close this tab?"

**Abraham (verbatim):** "alright so this is also in some roadmap stuff and so if i ask whats left its going to show up, so its time to close this tab?"

- Before closing, Claude checked both repos were clean, on `main` and level with GitHub. The site repo had been left on the privacy branch, so it was switched back to `main`.
- The open item surfaces three ways when he asks what's left: the roadmap's "Before the beta", the app's CLAUDE.md, and the site PR's comment.

### ~08:35 — `/diary`, and a tab that asked about marketing (sessions 4f948fc0, 716720e0)

- **Abraham (verbatim, other tab):** "did we do some exploration or documentation on basic marketing". That tab searched the repo's docs and read the roadmap's launch track and the site's roadmap, and what it found is in the next era (~08:37).
- **This `/diary`** was the second on Sonnet and the first to start a new chapter after a tag. Chapter 06 was tagged for 0.7.0 and 0.7.0 is now released, so the work after it opens chapter 07.
- Only a few hours of material was new, so it was written directly with no subagents.
- **The skill's model setting covers its own run only.** The session went back to Opus for "go ahead and finish up" at 08:02, and the commits that morning carry the Opus attribution; the model line switched to Sonnet again for this `/diary`.

## Era: what the game could sell, and what it owes TMDB (2026-10-26, afternoon and evening)

The rest of the day was business, not code. The marketing tab found nothing on promoting the waitlist, and Apple Developer enrollment went in. Then an evening session took up a question parked since GROWTH.md: can Unspool ever make money while every answer is checked against TMDB? It read TMDB's terms in full, found solo developers' forum threads with TMDB's real price, measured Wikidata as a way out, and ended with the money plumbing planned but switched off, the next three mechanics written down, and the attribution fixed. One app change shipped; the rest went into the roadmap.

### ~08:37 — "nothing about promoting a landing page?" (session 716720e0)

- **Abraham (verbatim):** "nothing about promoting a landing page?"
- The tab's answer: there's a plan for *building* the page (the site's Astro move and connection-post blog, Reddit and build-in-public in the roadmap), but nothing on sending people to it before launch. No post plan with the waitlist as the call to action, no link preview card for the landing page, no signup target before the November invites, no referral, no per-source (UTM) tracking. It offered a "promoting the waitlist" section for the site's roadmap; nothing was written that session.

### ~14:40 — Apple Developer enrollment (session 716720e0)

- **Abraham (verbatim):** "I've signed up for apple developer, says could take up to 48 hours"
- Recorded in memory as the gate for TestFlight and the app record.
- **The flag it raised:** the bundle ID is still `abe.movie-quiz`, and once the App Store Connect record exists it can never change. Change it now (e.g. `com.playunspool.app`) or live with it. Not decided.
- While waiting: the privacy page's three questions, a USPTO/EUIPO search for "Unspool", and a clean Release build with tests on iOS 18.0.

### 19:30 — "monetization on the api stuff" (session 875718fd)

- **Abraham (verbatim):** "i think we talked about reaching out to tmdb asking about possible monetization on the api stuff" and "i think my monetization will only revolve around game mechanics, so to keep their score going for hints or something like that?"
- The repo already had it parked: ROADMAP's "TMDB's terms on commercial use get settled (by email) before anything is charged for", GROWTH §9's open question 2, and the hint ladder in ASSISTED-MODE.md.
- **First answer:** selling gameplay instead of data doesn't get around the terms. A hint *is* TMDB data (the initials and letter blanks come from a TMDB cast list). And a paid hint and a paid continue are different products: a continue keeps a run alive with no recall, which is buying score.

### 19:31 — reading the terms (875718fd)

- **Abraham (verbatim):** "can we do a proper look see through their terms and conditions to see where that leaves us"
- Read the [API Terms of Use](https://www.themoviedb.org/api-terms-of-use) in full (last updated 2023-10-20; TMDB is operated by TiVo Platform Technologies LLC). The clause that decides it, §2.A: commercial use includes "deriving revenues from the use or provision of TMDB… for commercial or monetary gain, **directly or indirectly**", with "Charging users a fee for Your Application… that includes some form of integration" as the first example. Unlicensed commercial use is a "material breach" that "causes irreparable harm".
- **Checked against the code, three things owed even while free:**
  - the attribution used the FAQ's shorter line, not §3's wording;
  - §1.C forbids caching TMDB information for more than six months, and the Reel stores names, years and image paths indefinitely;
  - §1.C forbids "derivatives", and the duotone actor photos are arguably one.
- The FAQ's softer test ("primary purpose is to create revenue") isn't the contract.

### 19:33 — what solo developers found (875718fd)

- **Abraham (verbatim):** "can you see if any solo developers have publicly posted about this?"
- TMDB's forum has the number the terms leave out. TMDB staff in 2026: "If your app generates revenue, it is considered commercial… You would need to subscribe to our 'commercial' API key which costs $149/mo", and under $1M revenue that's the price, with a custom quote above. A 2024 promise of "a new offering designed for apps like yours" never arrived.
- The same thread has a developer whose emails to sales went unanswered for weeks. In October 2026 a hobby-site owner asking about ads got: "As soon as you decide to earn some revenue, you will need to upgrade to a commercial subscription."
- **Two by-products:**
  - The only rate limit is about 40 requests a second **per IP**, which matters for the 0.8.0 proxy: it puts every player behind one IP.
  - App Review has rejected TMDB apps under guidelines 4.1, 5.2.1 and 5.2.2, mostly over posters and celebrity photos in store screenshots.

### 19:36 — "I think we have to move away from TMDB no?" (875718fd)

- **Abraham (verbatim):** "I think we have to move away from TMDB no?"
- **Answer:** not yet. A free app is allowed, $149 a month is a capped cost, and leaving TMDB doesn't fix the image question, because TMDB doesn't own the posters either. The only free source for commercial use is Wikidata (CC0), so the question became how good its data is.

### 19:37 — the Wikidata coverage test (875718fd)

- **Abraham (verbatim):** "what about tmdb apps not getting accepted by play store?" (Unspool is iOS-only. The cases found were Samsung's Galaxy Store and one old Play removal, all about artwork, not TMDB) and "I think i'd like to explore this".
- **The script:** the top 500 films by TMDB vote count (the real deal pool is only the top 100). Each film's cast was compared with Wikidata's P161, and the 355 pool actors' filmographies the other way. Matching was by the TMDB ids Wikidata stores, with names as a fallback.
- **Wikidata's main query service was throttled** to "1 req / min" during an outage, so the queries ran against QLever's mirror.
- **The first result had a hole:** 61 films with no cast at all. All were animated (Up, Toy Story, Spirited Away…). Wikidata keeps voice roles in P725, not P161. With both:

| | Wikidata covers |
|---|---|
| Billed 1–3 | 99.5% |
| Billed 4–10 | 91.7% |
| Billed 11–20 | 55.9% |
| Well-known films (≥1000 votes) in actor filmographies | 96.7% |
| Obscure films (<100 votes) | 39.6% |

- **Misses that would hurt:** *Divergent*'s Theo James and Ashley Judd.
- **Images:** 339 of 355 pool actors have a Commons photo (per-image licences). Films have essentially no posters, so the Reel's "frame per film" would go typographic.

### 19:47–19:54 — the other options, and building a database (875718fd)

- **Abraham (verbatim):** "Are these my only options?" and "i imagine its not an easy task to compile a ismilar db to tmdb right"
- **The full table:**
  - TMDB free forever;
  - TMDB commercial;
  - Wikidata with your own fixes;
  - Wikidata data with TMDB images (still the $149);
  - IMDb (enterprise only; the free datasets are non-commercial);
  - OMDb (its data is CC BY-NC, so non-commercial);
  - Gracenote / TiVo (out of reach);
  - Trakt and JustWatch (built on TMDB).

  The graph and the art turned out to be separate decisions.
- **A new risk, raised here:** the Reel turns real actors into collectible cards. Selling around that looks like trading cards, which are licensed through the people on them, whatever the data source. It goes to a lawyer before anything is sold.
- **Building "a TMDB" isn't the job.** Unspool needs a slice: perhaps 20–30k films and their casts, a few megabytes, shipped in the app. Estimate: one to two weeks of work plus an open-ended fixes file. Wikidata has no billing order, so actors would be ranked by their own popularity.

### 19:54–20:06 — "side money", and the $149 (875718fd)

- **Abraham (verbatim):** "i was hoping to add some monetization to make some side money from this though"
- **Abraham (verbatim):** "How would tmdb even know that im offering paid pauses and stuff"
  - **The honest answer:** at small scale, perhaps not for a while. But the App Store listing shows "In-App Purchases", the key identifies the app, Apple's 5.2.2 asks for rights, and the repo is public with the plans in it. And the moment it would pay off is the moment it's visible.
- **Abraham (verbatim):** "if i offered say 2.99 for some sort of credit system like most games like this do, talk to me about the economics of switching to commercial license"
  - About $2.40 kept per sale after Apple's 15% and VAT, so ~62 sales a month to cover $149.
  - At assumed 0.5–3% paying players, that's roughly 1,600–9,500 monthly players to break even (mid case ~3,200).
- **Other ways to earn, ranked:**
  1. a Daily Chain premium or subscription (archive, Practice, stats);
  2. credits;
  3. app icons and themes.

  No ads (privacy and gameplay), no upfront price (the site promises free), no tip jar (TMDB counts tips).
- **Abraham (verbatim, the turn):** "i agree that im overthinking a thing that happens to probably 1% of most apps first launched ever, and with such a niche game, i'm probably even less likely to reach the continued requirement to make money , so i shouldn't overthinking 149, tell me if you agree or not". Agreed, with one caution: build seams, not a store.

### 20:10–20:14 — monetization-ready, and the head-to-head (875718fd)

- **Abraham agreed the five seams one by one** ("1. sure / 2. yeah i think building in credits that then we give out every day or something would be the ideal thing / 3. okay / 4. sure / 5. yes"):
  1. one `Entitlements` access check;
  2. free daily credits;
  3. marked assisted runs;
  4. replayable dailies;
  5. credit events in analytics.
- **Then the feature he wanted:** "a simple here's my chain , start with the same chain and then that turn ends and the user who completed it sees the final head to head score… and the other user also sees it on their end… and there's a list for this. so this is probably downstream of social stuff right"
- **Answer: mostly not.** `SharedChain` already carries the start, links, points, a sharer id and a name. B's head-to-head works from the link alone. A sees it via a manual reply link, with no server needed, or later the 0.8.0 service with a push. The rivalry list lives on the phone, keyed by sharer id. Identity is a display name, not a username.

### 20:17–20:24 — emails: TMDB, and another developer (875718fd)

- A full email to TMDB sales was drafted (five questions: does the plan cover in-app purchases, monthly billing, the Reel's six-month storage, the duotone derivative, proxy caching). Then Abraham cut it down: "I guess i want to just ask them if i can use the free license if i'm just launching and have no idea what the userbase is like". TMDB staff had already said publicly a published app with no revenue is fine, so the short email asks only for written confirmation, which is useful if App Review asks.
- **Abraham found a solo-developer TV tracker on the App Store** (from a Reddit thread) that uses TMDB and sells a premium tier. It proves Apple approves such apps; it can't show whether its developer pays TMDB. Abraham: "reaching out to [the developer] first , so maybe i can ask him". A friendly message went out asking about App Review first and TMDB second. "Okay i reached out to them".

### 21:03–21:21 — attribution fixed, Next up, and PR #36 (875718fd)

- `TMDBAttribution` now uses §3's words ("This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB"), and Settings → About shows it too. Built clean on the iPhone 16 simulator.
- **The roadmap gained:**
  - **Monetization-ready** (the seams, what would be sold, TMDB's terms, $149, the Wikidata numbers);
  - **Head-to-head**;
  - **Next up**: (1) a daily start for everyone from a fixed list, (2) challenge links + head-to-head, (3) free daily credits + hints, with the A→B playtest meanwhile;
  - a note on the proxy's per-IP limit;
  - an App Review note and screenshot guidance ("let names and the game carry the shots, not faces").
- **Abraham (verbatim):** "add the note about the website so i can always ask you in what way the website is out of step". That became `docs/WEBSITE-SYNC.md`, with CLAUDE.md pointing at it. First entry: the site's footer and privacy page still use the old attribution line.
- Commits `a17e94a` and `947d41d`, merged as PR #36 (`45e0165`). Then "merge pr and then run a quick /diary".

### Where things stand (2026-10-26 ~21:21)

- **0.7.0 is tagged** on `main` (`f2d6c4c`), on GitHub only. No TestFlight build has been made, and the build number is still 1. `main` is at `86418b5`, clean and in sync.
- **The website** is at playunspool.com: a Cloudflare Worker with a D1 waitlist, a privacy page, a contact address on the domain, and the UserJot board. The app now links to the privacy page, the board and contact from Settings.
- **The privacy page covers the website only until site PR #1 merges.** The app section is drafted there, names Abraham Mathew as controller, and goes live just before the first TestFlight invite, after a re-check against the code and a decision on three points: analytics on by default versus consent, a retention period, and traceable deletion.
- **The app repo's docs** say all this in the roadmap and CLAUDE.md. The handover's other asks are met: the screenshot flags are listed in CLAUDE.md as ones not to rename, and the site's promises are listed too.
- **Still before launch, as the roadmap and handover now stand:** a TestFlight build to friends (with the privacy page merged first), the site's `/support` page, the daily start, and challenge links. The domain and hosting, which were blockers on Oct 25, are done.
- **Unconfirmed:** whether the site's holo flash is fixed in Safari; the play screen with the software keyboard up; Instruments on a real phone.
- **Noticed, not fixed:** "Jean-Claude Van Damme" crowds the START sticker on the pushed-back start card.
- **Evening update:** Apple Developer enrollment is pending (submitted ~14:40). The bundle ID `abe.movie-quiz` is still undecided and becomes permanent with the app record. `main` is at `45e0165`. Emails are out to TMDB (confirm the free key at launch) and to another solo TMDB developer. The next build is the daily start (ROADMAP *Next up*). The site's attribution wording is stale (`docs/WEBSITE-SYNC.md`). Nothing will be sold until the hint test, the numbers and a legal read on the actor cards say so.

## Era: the daily start, and a backend before launch (2026-10-26 evening)

Item 1 of *Next up* took twenty minutes to build and then raised the bigger question.
Abraham asked how a daily start is served when there's no server. The answer was that
it's compiled into the app. That turned into "should we have a database", then "what
could a database give us", then a decision that reversed Saturday's re-cut: the backend
comes **before** launch. By 23:38 a Supabase project was live with a TMDB proxy and a
shared cache, the TMDB token had left release builds, and two PRs were merged.

### 21:25 — "lets start tackling next roadmap mechanics one by one" (b738c613)

- Read *Next up*, GROWTH D5 and the Daily Chain's day-keying decisions (local midnight, numbered days, results stored by number) and reused them.
- **Four questions, Abraham's answers:**
  - *Attempts:* **strictly one** (offered: one scored then practice, which was the recommendation, or unlimited);
  - *Placement:* the daily is the **first deal of the day**, with a Today pill to come back to it;
  - *Records:* daily runs count toward the best run and the Reel;
  - *The list:* **"You supply it"**, so a nine-entry placeholder list ships for now.
- **Built:** pure `DailyStart` (date → day number, wrap-around list) and `DailyResult`, written **at the start** of the run so a quit or force-quit still uses the attempt. The engine deals the daily before the pool loads. The share text and image say "Unspool #N", and analytics gets `source: daily` plus `daily_number`. `mode` is left for the A→B Daily Chain, because this is the same endless game from a chosen start.
- **Offline:** a first version let the daily hide the "Out of film" screen. Reverted, because a daily you can't play is worse than an honest offline screen.
- Existing deal tests were pinned to `.distantPast` so they never see a daily. 125 tests passed, then 126.

![The SE home on day #1: Tom Hanks with an ACTOR chip and a black DAILY #1 tag, the first deal of the day](media/b738c613/homeSE.png)

- **The tight spot:** after "Deal again" the header carries three pills on an SE. A throwaway `-tmpDealAgain` hook (never committed) rendered it. It fit with an empty Reel, but the estimate was ~18pt spare with a two-digit Reel count, so the pill's padding was trimmed.

![The SE header with TODAY, Reel and gear pills after a random deal (Keanu Reeves), the cramped case checked before committing](media/b738c613/pillSE.png)

### 22:11 — "how is it being served then, is there a server"

- No server: the list is compiled in, and every phone counts days from `firstDay`. That's how Wordle started too. What follows: changing the list means an app update, the list is append-only, and anyone can read ahead.
- **22:12, Abraham:** "no i think this is a natural spot to create a database and backend for stuff like this no?" The first answer was **no database yet: a JSON file on playunspool.com** gives remote edits with nothing to run, because a database earns its place when something *writes*.
- **22:34:** "if we have to do database for head to head stuff, don't we just do it for this too anyway". Agreed on the logic, but head-to-head step one is link-only too. So the real question was *before or after launch*.
- **22:35:** "Thinking the other way and we're not bound by time for launch, what could a database give us". The list that came back, in order:
  - **per-day stats for everyone** ("you beat 74% today"), comparison without a leaderboard;
  - **answer data**: obscurity scored by what players actually remember, dailies picked from data, bad TMDB credits spotted;
  - content and settings changed without an app release;
  - the TMDB proxy;
  - social done properly;
  - data that survives the phone.
- **22:39, the honour system:** "wordle is something people can cahtgpt or google and cheat on easily right, it only works people decide to follow by an honour system". Yes. It holds because there's no prize, the audience is friends, and cheaters barely move aggregate stats. Unspool adds a per-turn clock, so cheating means asking ChatGPT every few seconds.

### 22:43 — the decision

- **Abraham:** "1. yes before launch / 2. the order above". Then a design thought: "i'd like to try different gaming mecahnics … like six degrees of seperation or two start and end points … should we think about that when making the backend". **Answer:** a mode's rules and screens ship as app updates. The service keys puzzles and results by `mode`, with the mode's data in a JSON column (no table per mode), and can switch modes on remotely. Nothing more until a second mode is real.
- **New roadmap section, "Re-cut 2026-10-26: the service before launch":** daily start (built in, kept as the fallback) → TMDB proxy → daily from a table → results table → head-to-head with automatic return → credits and hints.
- Committed as `b3f3c81`. Then 3: "yeah i mean we build it, (can you put it on my mobile phone also)". All phones showed *unavailable*. "sorry wifi was off nowphone should be available". Installed on the iPhone 16 Pro.

### 22:51 — Supabase, and two notes for later

![Supabase's new-project form: organisation abematt (free), project "unspool", region Americas, with Data API and "automatically expose new tables" ticked and automatic RLS unticked, before the two changes](media/b738c613/pasted-1.png)

- **Two notes from playing it on the phone**, filed in the roadmap's *To come back to*:
  - "the shrae image doesn't have the actor or movie names". It's spoiler-free by design, but reads as missing on a phone.
  - "the today button and the daily pill … visually i don't agree with but mechanically it looks like it works".
- **Form review:** untick "Automatically expose new tables" and tick "Enable automatic RLS", so every new table starts locked. Skip GitHub, and keep the password in a password manager.
- The publishable key was pasted in at 22:54. It's public by design, but it's kept out of the public repo (in the gitignored plist) for the same reason as the PostHog token.

### 22:55–23:04 — the proxy

- **The design:** an Edge Function `tmdb` that forwards only the five paths the app uses, plus a `tmdb_cache` table (RLS on, no policies). Cache lifetimes: 1 day for searches, 7 for discover and filmographies, 30 for casts. It serves an expired copy if TMDB fails. The app only changes its base URL and sends `apikey` instead of the token.
- **Gotchas:**
  - Homebrew refused to install the CLI ("Command Line Tools are too outdated"), so it ran through `npx supabase@2`.
  - `sb_publishable_` keys aren't JWTs, so the function needs `verify_jwt = false` and checks the key itself.
  - Abraham ran `login`/`link`/`db push`, because they need a browser and the database password.
- **First test:** gate 401, wrong path 404, the public key denied on the table. But the second request was another **miss**. The cause: with auto-expose off, **even the service role had no grant**, and the function ignored the error. Fixed with a grant migration and logged cache errors. After the second push: miss 1.99s, then **hit 0.43s, hit 0.67s**.
- Committed as `5b74459` (first pushed as `16a27d8`, before the branch split).

### 23:06 — "the supabase should be a seperate branch", the token, the advisor

- **Branches split:** `feature_daily-start` and `feature_tmdb-proxy` stacked on top. Only local branches moved.
- **Security advisor** (`supabase db advisors --linked`): one finding, Supabase's own `rls_auto_enable()` (`SECURITY DEFINER`) callable by the public key. Revoked in a migration, and the advisor came back with "No issues found".
- **The token leaves Release:** secrets split into `AppSecrets.plist` (service key, PostHog, ships) and `TMDBSecrets.plist` (development only), with `EXCLUDED_SOURCE_FILE_NAMES` on the Release configuration. Verified by searching a built Release app for the token: not there.
- **Release had never compiled.** Two `#Preview`s called DEBUG-only demo loaders, and the error message was about `return`. This was already on `main`, and would have hit the first TestFlight upload. Fixed by making them DEBUG-only.
- **Proof the proxy works without the token:** a fresh Release install saved a full pool (76 actors, 100 movies), and its URL cache was all `…supabase.co/functions/v1/tmdb/…`. But the daily had no photo:

![A fresh Release install: Tom Hanks as Daily #1 with a blue placeholder avatar, though the pool it had just loaded held his photo](media/b738c613/release3.png)

- **Two layers of the same bug.** Nodes are equal by TMDB id. `@Observable` skips a set whose new value `==` the old one, so swapping in the pool's copy was never announced. A test that fails without the fix confirmed it. Fixing that wasn't enough: SwiftUI *also* compares a view's inputs with `==`, so the sentence was re-keyed on id plus art path. The pool is now also read before the daily is dealt.

![The same fresh Release install after the fix: Tom Hanks' photo in the avatar](media/b738c613/release4.png)

- Commits `41cf165` (the photo fix, onto the daily branch) and `8b74b0a` (token, previews, advisor), then the proxy branch was rebased.

### 23:21–23:38 — npx, the review, monitoring, merges

- "it always asks me to install supabase?" That's npx's confirmation prompt (`--yes` skips it). The real fix is updating the Command Line Tools and `brew install`. `db push` also warned it will default to local soon, so use `--linked`.
- Abraham asked for "a high level review of what we did with supabase, how we connected, what all this token stuff is", plus why Release didn't compile and why it's safe. That got a table of every key and where it lives.
- **23:32:** "is the tmdb_cache per user?" No: it's shared, keyed by request, with no user data. On abuse and the free-plan pause: "should we note that somewhere for … a dashboard that will sort of aggregate all analytics like posthog, website visits, ad campaigns, supabase traking". That became **`docs/MONITORING.md`** (`fbdb185`), the dashboard's spec. Abuse shows as proxy calls per day outpacing PostHog sessions; a paused project must be decided before the beta (Pro, or a keep-alive).
- **Merges:** #38 merged (`6763823`). **#39 was closed, not retargeted**, when #38's branch was deleted. It was reopened as **#40** from the same branch and merged (`c524212`). A hook then blocked `git branch -D`, and `gh` had already deleted the branches anyway.

### Where things stand (2026-10-26 ~23:38)

- `main` is at `c524212`. The daily start (placeholder list) and the TMDB proxy are merged, and the phone runs the proxy build.
- **Supabase project `unspool`** (free plan): the `tmdb` function is deployed, with migrations `tmdb_cache`, a service grant, and a lock on `rls_auto_enable`. The advisor is clean.
- **Next:** the daily start served from a table, the first table the app *reads*.
- **Owed:** the real start list and `firstDay`; the daily's look; the share image's names; Pro or keep-alive before the beta; the privacy page and App Store label now that data reaches a server; CLT update plus brew for the CLI.

## Era: the daily from a table, and every run recorded (2026-10-26 late – 10-27)

A fresh session half an hour later, past midnight. In half an hour, items 3 and 4 of
the morning's re-cut both went live. The daily start became a row in a Supabase
table, and every finished run started going to a second table. Abraham made the four
calls on the second one, then asked how Wordle shows stats and whether the game
really rewards obscurity. It ended with a real run from his phone sitting in the table.

### 23:58 — "alright what are the next things on our road map" (e81853bc)

A read of `docs/ROADMAP.md`. The re-cut from earlier that evening put the service before
launch, in order: the daily start (done), the TMDB proxy (done), **the daily start
served from a table**, a results table, head-to-head, then free credits and hints. The
recommendation was the table first: small, built on the proxy that had just landed, and
the results table needs it.

### 00:00–00:10 — "alright lets try the daily start from a table"

- **The shape: one `puzzles` table, `(mode, number, revision)` → `data jsonb`.** It
  follows the re-cut's rule about room for new modes: "keyed by a `mode` with the mode's
  data in a JSON column, not a table per mode". The daily start is mode `daily_start`.
- **Immutable once published.** A trigger refuses every update, delete and truncate,
  even from the owner. A fix is the same day number with the next revision, and the app
  plays the highest *playable* revision. This is the roadmap's 0.8.0 rule, "Corrections
  publish a *replacement*", made into SQL.
- **The list stays as the fallback**, as the re-cut said. The migration seeded days 1–9
  from the placeholder list, so nothing changed for anyone who had already played #1,
  and a test reads the migration file and checks the seed against
  `DailyStart.entries`.
- **The app** (`DailyStartFeed.swift`) makes one PostgREST GET with the publishable key
  for today plus seven days, at most once an hour, and keeps the days in
  `UserDefaults`. A served start that differs from the list swaps in on the home, never
  mid-run. Rows are bounded (`Entry.isPlayable`), following the roadmap's "Config must
  never be able to brick the client".
- `NodeKind` became `nonisolated` so the entry could decode off the main actor.
- One build error, `dealtSeed?.name` (it's `displayName`), then 135 tests green.
  PR #42 (`0df4dd3`).
- **00:10:** Abraham ran `db push` himself (the memory rule: he holds the database
  password). The probe with the app's key: all nine days read, while insert, update and
  delete were refused (401, `permission denied`). The advisor was clean. Merged
  (`6c8a51e`).

### 00:11–00:21 — "sure lets do that too": the results table

The docs already had the rules: writes go through an Edge Function, results are keyed by
puzzle number, and runs compare by links with points breaking ties. That left four
questions, asked together:

| Question | Recommended | Abraham's answer |
|---|---|---|
| Which runs? | Every run | **Every run** |
| What answer data? | Links as TMDB ids | **Links as TMDB ids** (no typed misses) |
| Server checks? | Re-check every link against TMDB | **Shape checks only** |
| Show "you beat N%" now? | Collect now, show later | **"How does wordle do this?"** |

- **The one he overruled** was validation. The recommendation was the roadmap's own
  rule, re-check every link. He took the cheaper path. The roadmap had already admitted
  the limit: "Server-side re-validation proves the links are real; it cannot prove they
  were recalled."
- **The Wordle answer:** Wordle shows a personal panel (played, win %, streaks, guess
  distribution), and the WordleBot puts your guesses next to the average, but nothing
  says "you beat N%". The answer flagged its own uncertainty about whether WordleBot also
  shows today's full distribution. The table stores raw rows, so any of those can come
  later. The UI was left alone.
- **~00:16 (inferred), mid-build: "also are we valuing or giving importance to
  obscurity?"** Yes, a little. `Scoring.obscurityBonus` is `30 / (1 + popularity/8)`, so
  a star earns 2–5 points and a deep cut ~24, on top of 10 base and up to 30 for speed.
  But points only break ties, and TMDB popularity is page-view buzz, not difficulty of
  recall. The results table is the fix: count what people actually name.
- **Built:** `results` (RLS on, no public grants, one daily per device by a partial
  unique index), the `results` function (alternating kinds, no repeats, `links` matches
  the chain, points within 10–70 a link, no future day numbers, and the daily's start must
  match the published one), and on the phone `RunResult` plus a `ResultsOutbox` that
  keeps undelivered runs (newest 50) and retries on each visit home. Typed text never
  leaves the phone. Demo launches send nothing, and DEBUG builds tag `-debug`.
- 144 tests green. The function was deployed before the table existed. The probe showed
  401 without a key and 422 for a malformed run, but 500 rather than 422 for a wrong daily
  start: the service role couldn't read `puzzles` yet. PR #43 (`d42b20f`).
- **What it adds to the privacy work:** results leave the phone even with analytics off
  (treated as game data, not analytics), so the privacy page has to cover them, or they
  go behind the opt-out too. Both went into the roadmap's "Before the beta".
- **00:21 "done":** after the push, the wrong start got 422, a valid daily 201, the resend
  200 ("Already stored"), and the public key could neither read nor insert. Advisors
  clean. Merged (`22455b8`).

### 00:22–00:26 — "is this code on my phone"

No. Nothing from the session had left the simulator. A Debug build of `main` was
installed on the iPhone 16 Pro over `devicectl`. Getting there hit two gotchas.
`-destination name=` fell through to a visionOS placeholder that isn't installed. And
the device's `xcodebuild` id (`00008140-…`) isn't its `devicectl` id.

**00:26 "finished a run":** the row was there seconds later, read with `supabase db
query --linked` (a CLI command found that night): daily #2, 12 nodes, **11 links, 563
points**, quit, `0.7.0-debug`. The first real player row.

### Where things stand (2026-10-27 ~00:27)

- `main` at `22455b8`. Supabase: `puzzles` (days 1–9 = the placeholder list), `results`,
  functions `tmdb` and `results`. Advisor clean. Two probe rows to delete
  (`app_version = 'probe-debug'`).
- **Next on the re-cut:** head-to-head (waits on universal links and the developer
  account), then credits and hints.
- **Owed:** the real starts before day 10 (Nov 4) or the list wraps; what the stats panel
  shows; whether results sit behind the analytics opt-out; the privacy page now covering
  `results`.

### 00:31 – 08:41 — loose ends, the time zone, and tidy-up

- **00:31 "put that for me to deal with tomorrow."** The four open items became a
  checklist, "For Abraham, 2026-10-27", under *Next up* in the roadmap, each with what to
  do (the probe-row `delete`, the Nov 4 deadline for real starts, the Wordle comparison
  for the stats panel, the opt-out choice). PR #45 (`01283f8`). It's a list in the repo,
  not a reminder.
- **08:37, the morning after: "why does the results table have null for some numbers
  columns"** `number` is the daily's day; ordinary (`endless`) runs have none, and a
  check constraint enforces it.
- **"it should be decided per device's timezone"** It already is. `DailyStart.number`
  counts calendar days between the phone's local midnights from Oct 26, with the phone's
  calendar. The server only refuses a day that hasn't begun anywhere (UTC+14). One catch
  came up: the engine keeps the calendar it launched with, so a traveller keeps the old
  zone until a relaunch. That matches `DAILY-CHAIN.md` ("read when the app opens");
  `Calendar.autoupdatingCurrent` is the one-line change if that should follow the phone
  live. Left as is.
- **08:38 "did i see tom hanks already because it was past 12 yesterday for me"** Yes:
  Tom Hanks was #1 on Oct 26 in Spain. The 00:26 run was already Oct 27 locally, so #2,
  The Dark Knight, which the results function confirmed when it accepted the row.
- **08:41, tidy-up:** three old local branches (`docs/architecture-overview`,
  `feature_cream-neobrutalist`, `gamification-and-fixes`) were checked first: no commits
  missing from `main`. Deleted, locally and on GitHub. A `fetch --prune` then dropped
  ~28 stale remote-tracking refs for branches GitHub had already deleted.

### Decision log

| Time (local) | Decision | Rationale | Source |
|---|---|---|---|
| Oct 26 08:02 | Cut 0.7.0 as "go ahead and finish up" | The repo's rule is the diary chapter first, and chapter 06 already covered everything under `[Unreleased]` | 4f948fc0 |
| Oct 26 08:03 | Ground & Object ships in 0.7.0 with the first foundations | The roadmap had foundations as 0.7.0 and Ground & Object as "the next minor version"; it was one body of unreleased work | 4f948fc0 |
| Oct 26 08:03 | Leave `CURRENT_PROJECT_VERSION` at 1 | No build is being submitted; the rule is to bump it for a submitted build | 4f948fc0 |
| Oct 26 08:05 | Split the commit, merge and tag from `pkill` after the hook blocked the line | The safety hook blocks force-pushes; it saw a `-f` on a line that also pushed (inferred) | 4f948fc0 |
| Oct 26 08:07 | Apply the handover's docs half at once (PR #32), and treat code and wording separately | Roadmap entries predating the site were wrong now; the Settings rows and the privacy page are different kinds of work | 4f948fc0 |
| Oct 26 08:26 | Name Abraham Mathew as controller on the privacy page | Privacy law expects a named person responsible; no company exists | 4f948fc0 |
| Oct 26 08:29 | The three Settings links send no analytics | A property before an event; the board counts its own visits and none answers a question about play | 4f948fc0 |
| Oct 26 08:29 | Add `-uiOpenSettings` (DEBUG) | A way to screenshot the sheet, documented with the other QA flags | 4f948fc0 |
| Oct 26 08:30 | Write the app section from the app's code, not the handover | The handover said so; the code is the truth at the time | 4f948fc0 |
| Oct 26 08:31 | Leave the privacy PR unmerged | Merging deploys straight to playunspool.com | 4f948fc0 |
| Oct 26 08:32 | The app section goes live just before the first TestFlight invite | Testers' play data reaches PostHog from their first run; until then there's nothing to cover. Not now, not at App Store launch | 4f948fc0 |
| Oct 26 08:33 | Note the plan in the app repo only (roadmap, CLAUDE.md, a PR comment, memory) | Anything pushed to the site's `main` deploys, so its own docs wait for the PR | 4f948fc0 |
| Oct 26 08:34 | Leave the three open privacy questions (consent, retention, deletion) for the pre-invite pass | They need decisions, and the page isn't live yet | 4f948fc0 |
| Oct 26 08:35 | Start chapter 07, and write it without subagents | 0.7.0 is tagged, and a few hours of material is cheaper to write directly | 4f948fc0 |
| Oct 26 14:40 | Flag the bundle ID before the app record exists | `abe.movie-quiz` can never change once App Store Connect has the record | 716720e0 |
| Oct 26 19:31 | Treat any revenue, purchases included, as commercial use | §2.A: "directly or indirectly"; the first example is charging for an app that integrates TMDB | 875718fd |
| Oct 26 19:37 | Query QLever instead of the Wikidata Query Service | WDQS was throttled to 1 request a minute during an outage | 875718fd |
| Oct 26 19:38 | Count P725 (voice actor) with P161 | 61 animated films came back empty without it; Wikidata stores voice roles separately | 875718fd |
| Oct 26 19:47 | Keep TMDB for launch; Wikidata is the fallback, not the plan | A free app is allowed; leaving TMDB doesn't fix image rights; Wikidata's lead coverage is strong but there are no posters | 875718fd |
| Oct 26 19:57 | Don't monetize on the free key and hope | The listing, the key and App Review make it visible exactly when it starts to pay; revocation stops every turn | 875718fd |
| Oct 26 20:06 | Don't overthink the $149; subscribe the day purchases go live | Abraham: most apps never reach the scale where it matters; at scale it's a small share | 875718fd |
| Oct 26 20:06 | Build the money seams now, not the store | Turning purchases on should fill slots, not rework the game; StoreKit, paywall and pricing wait for numbers | 875718fd |
| Oct 26 20:10 | Credits are given out daily, free in the beta | Answers "does a stuck player want a hint?" before anything is sold | 875718fd |
| Oct 26 20:06 | Rank what to sell: Daily Chain premium → credits → icons/themes; no ads, no upfront price, no tip jar | Fits a daily puzzle game; ads cost privacy and the timed recall; the site promises free | 875718fd |
| Oct 26 19:47 | Nothing sold on actor cards without a legal read | Selling around real people's faces looks like trading cards | 875718fd |
| Oct 26 20:14 | Head-to-head works first with reply links, no backend | B's comparison needs only the link; A's needs a return path; the service and accounts upgrade it later | 875718fd |
| Oct 26 20:14 | Identity is a display name, not a username | People find each other by link; the sharer id disambiguates | 875718fd |
| Oct 26 20:17 | Ask TMDB only to confirm the free key at launch | Staff already said so publicly; a written reply helps if App Review asks | 875718fd |
| Oct 26 21:03 | Attribution uses §3's exact wording, also in Settings | The FAQ's line isn't the contract; App Review asks TMDB apps about rights | 875718fd |
| Oct 26 21:03 | Next up: daily start → challenge + head-to-head → free daily credits and hints | Small to large; the daily start needs no backend or developer account | 875718fd |
| Oct 26 21:19 | Track the site's drift in `docs/WEBSITE-SYNC.md` | So "how is the website out of step?" has an answer in any new session | 875718fd |
| Oct 26 21:30 | Daily start: strictly one attempt, used up when the run starts | Abraham's choice over "one scored then practice"; writing at the start closes the force-quit retry | b738c613 |
| Oct 26 21:30 | The daily is the first deal until played; Today pill to return | Leads with the shared start without hiding random deals | b738c613 |
| Oct 26 21:30 | Daily runs count toward best and Reel | Same game from a chosen start | b738c613 |
| Oct 26 21:30 | Placeholder list; Abraham supplies the real one | His call ("You supply it") | b738c613 |
| Oct 26 21:33 | `source: daily` + `daily_number`, not `mode: daily` | `mode` is reserved for the A→B Daily Chain; this is the endless game | b738c613 |
| Oct 26 21:35 | Offline still shows "Out of film" over the daily | The daily can't be played offline either | b738c613 |
| Oct 26 21:38 | Trim the Today pill's padding | Three pills on an SE leave ~18pt with a two-digit Reel | b738c613 |
| Oct 26 22:12 | First answer: a JSON file on the site, not a database | Read-only data; a database earns its place with writes | b738c613 |
| Oct 26 22:39 | The honour system is enough | No prizes, friend audience, aggregates resist cheats; global leaderboards stay dropped | b738c613 |
| Oct 26 22:43 | The backend (Supabase) comes before launch; launch no longer bound to early November | Abraham: "yes before launch"; per-day stats and answer data are what make the game different | b738c613 |
| Oct 26 22:43 | Order: proxy → daily table → results → head-to-head → credits | Proxy first: no visible change, nobody's data at risk | b738c613 |
| Oct 26 22:43 | New modes ship as app updates; the service keys by `mode` with JSON data | No table per mode; nothing more until a second mode exists | b738c613 |
| Oct 26 22:52 | Untick auto-expose, tick automatic RLS | Every new table starts locked; opening one is a written migration | b738c613 |
| Oct 26 22:57 | Publishable key in the gitignored plist, not code | Public by design, but the repo is public: other builds shouldn't run on this project | b738c613 |
| Oct 26 22:58 | Supabase CLI via npx | Homebrew needs newer Command Line Tools (sudo) | b738c613 |
| Oct 26 22:59 | Proxy only the five paths the app uses; gate on the app key | Not an open TMDB mirror | b738c613 |
| Oct 26 22:59 | Cache 1 day (search) / 7 (discover, filmography) / 30 (cast); serve stale on TMDB failure | Near-static responses; inside TMDB's six-month limit; an old cast beats a frozen turn | b738c613 |
| Oct 26 23:03 | Grant the service role on `tmdb_cache` | With auto-expose off it had no access; the cache silently missed | b738c613 |
| Oct 26 23:06 | Separate branches for the daily and the proxy | Abraham: "the supabase should be a seperate branch" | b738c613 |
| Oct 26 23:10 | Split secrets: `AppSecrets` ships, `TMDBSecrets` excluded from Release | The token was in every build; the service key and PostHog are needed in Release | b738c613 |
| Oct 26 23:12 | Revoke public execute on `rls_auto_enable()` | The advisor's only finding | b738c613 |
| Oct 26 23:12 | DEBUG-only previews | Release had never compiled | b738c613 |
| Oct 26 23:15 | `dealtSeed` always notifies; the sentence keyed on art path | Equal-by-id nodes defeated both Observation and SwiftUI's diffing | b738c613 |
| Oct 26 23:33 | `docs/MONITORING.md` as the dashboard's spec | Abuse and the free-plan pause need a place to be watched | b738c613 |
| Oct 27 00:01 | Daily starts live in one `puzzles` table keyed `(mode, number, revision)` with `data jsonb` | The re-cut said a mode's content shares one table so new modes need no new ones | e81853bc |
| Oct 27 00:01 | Published puzzles are immutable (a trigger refuses update/delete/truncate); a fix is the next revision | People may have results against a day once it's out; the roadmap said corrections publish a replacement | e81853bc |
| Oct 27 00:02 | Keep the built-in list as the fallback and seed days 1–9 from it | No change for anyone who already played; the daily still works offline and on a missed publish | e81853bc |
| Oct 27 00:02 | Fetch a week ahead at most once an hour, keep it in UserDefaults, swap the home's daily only before play | Survives losing signal; a same-day fix reaches players within the hour; never changes a run in progress | e81853bc |
| Oct 27 00:15 | Send every run, not only dailies | Answer data for obscurity needs volume; stats use the daily rows | e81853bc |
| Oct 27 00:15 | Links as TMDB ids with per-link seconds; no typed text | Enough to measure recall; nothing personal can end up in the table | e81853bc |
| Oct 27 00:15 | Shape checks only, no re-check against TMDB (overruling the recommendation) | Cheaper; re-validation proves links real but not recalled, and nothing is at stake | e81853bc |
| Oct 27 00:16 | Collect results now, decide the on-screen stats later | Abraham asked how Wordle does it first; raw rows support any panel | e81853bc |
| Oct 27 00:18 | Results are game data, not analytics: sent regardless of the opt-out, for now | Flagged for the privacy pass to confirm or put behind the opt-out | e81853bc |
| Oct 27 00:18 | An outbox keeps undelivered runs (newest 50) and drops ones the server refuses | Offline game overs still count; a refused run would fail forever | e81853bc |
| Oct 27 00:31 | Tomorrow's loose ends go in the roadmap as a checklist | It's where the next session looks before planning; no reminder system is set up | e81853bc |
| Oct 27 08:37 | Keep the day decided by the phone's time zone as read at launch | Matches DAILY-CHAIN.md; `autoupdatingCurrent` is a one-line switch if travel matters | e81853bc |
| Oct 27 08:41 | Delete three old branches after checking they're fully merged | Nothing on them was missing from `main`; the repo rule is to ask only for unmerged work | e81853bc |

### Story material

- **A page waiting for a date.** The draft privacy section was finished by 08:31 and left unmerged on purpose. Abraham's one-line question ("once the app goes live, right?") was almost right, and the correction was only a few weeks: the trigger is the first beta invite, not launch.
- **Three questions a lawyer would ask first.** The draft raised them itself: default-on analytics versus consent, how long data is kept, and how a deletion request could find data tied only to a random ID. None of them was answered, and all of them are in the roadmap now.
- **A document one repo wrote for another.** The handover was written in the site's repo "for agents and people working in the app repo". Its checklist split three ways: docs applied at once, code done as a PR, and wording held until the right day.
- **The hook that read `-f` too eagerly.** A line that committed, merged, tagged and stopped a server was blocked as a force push. Nothing had run. Splitting it into two commands fixed it.
- **Cost, again.** The skill's Sonnet setting held for the `/diary` run only. The next prompt in the same session, "go ahead and finish up", ran on Opus again and the commits that morning say so.
- **Match-day blocks.** On football match days Spanish internet providers block Cloudflare's address ranges, so playunspool.com can be unreachable from Movistar and Vodafone in Spain while a match is on. Abraham is in Spain, so it affects testing. The handover says to check hayahora.futbol before assuming the site is broken.
- **Sixteen hours and fifty-eight minutes of silence.** Chapter 06 ended at 15:07 on Oct 25 and the tag came at 08:05 on Oct 26. This session received no messages in between, while the site was being built elsewhere (inferred).
- **What the diary can't see.** The domain, the Worker, the waitlist, the privacy page and the handover were built in a separate session in the site's repo. This diary captures only sessions in the app's project, so that work shows up here only as what the handover reported.
- **The free key's real price.** The terms never name one. A developer forum thread does: $149 a month under $1M revenue, said plainly by TMDB staff, after an earlier promise of an indie offering that never came.
- **The 61 empty films.** The first coverage run said Wikidata knew nothing about Up, Toy Story or Spirited Away. Wikidata files voice roles under a different property. One OR in the query took coverage of leads from 86.9% to 99.5%.
- **"How would tmdb even know."** The honest answer was that the risk is lopsided: invisible while it earns nothing, visible exactly when it earns.
- **The overthinking turn.** After an hour of terms, forum threads, break-even tables and a coverage test, Abraham's own conclusion closed it: "i'm probably even less likely to reach the continued requirement to make money, so i shouldn't overthinking 149". What survived wasn't a licence decision; it was five cheap seams.
- **Faces are the real licence question.** It started as a data question and ended as an image one. TMDB doesn't own posters, Wikidata can't supply them, App Review rejects over them, and the Reel's actor cards raise a likeness question no data source answers.
- **Break-even arithmetic:** $2.99 → ~$2.40 kept → 62 sales a month → somewhere between 1,600 and 9,500 monthly players.
- **One developer asking another.** The quickest route to an answer turned out to be another solo developer with a TMDB app and a premium tier, found through Reddit.
- **Twenty minutes, then the real question.** The daily start was built and tested before anyone asked where it lives. "how is it being served then, is there a server" led, in four messages, to moving the backend ahead of launch.
- **The recommendation that lost, fairly.** The JSON-file answer was sound for the daily alone. What changed it was Abraham widening the frame ("we're not bound by time for launch") and the list of what a database unlocks: per-day stats and answer data, which nobody else has.
- **Wordle's honesty.** "it only works people decide to follow by an honour system". It works because nothing is at stake but face. Unspool's per-turn clock makes cheating a chore as well as pointless.
- **The cache that cached nothing.** Locking tables down by default locked out the function too. The test caught it: two misses in a row instead of a hit. After the grant, 1.99s became 0.43s.
- **Release had never been built.** Five months in, the first Release build failed on two previews. The first TestFlight upload would have found it instead.
- **Equal, but not the same.** Tom Hanks without a photo `==` Tom Hanks with one, by TMDB id. Swift's observation and SwiftUI's diffing both believed it, so the photo never showed until both layers were told otherwise.
- **The PR GitHub closed.** Deleting a stacked PR's base branch closed it instead of retargeting it. Nothing was lost; it came back as #40.
- **A token search as proof.** "The token leaves release builds" was checked by grepping a built app for its first 24 characters. A fresh install with no token loading a full pool proved the proxy.

- **Two tables in half an hour.** From "what are the next things" at 23:58 to a real run in the results table at 00:26: two migrations, two PRs, one Edge Function, 144 tests.
- **The first row.** Daily #2, The Dark Knight, 11 links, 563 points, quit. Abraham's own run from the phone, seconds after he finished.
- **"How does wordle do this?"** He answered a design question with a question, and it was the right one: Wordle shows a fixed panel and an average, never a percentile.
- **Obscurity, measured honestly.** The bonus is real but small (up to 30 a link, ties only), and it measures TMDB page views. The fix is counting what players actually name.
- **The overruled recommendation.** Re-checking every link was the roadmap's own rule. Abraham chose shape checks, and the roadmap's anti-cheat paragraph had already said why that's fine.
- **The 500 that meant "not yet".** The wrong-start check failed with 500 before the push, because the function's role couldn't read `puzzles`. After the push it returned the intended 422.
- **The morning check.** Abraham opened the table eight hours later and asked about the nulls before anything else. The schema answered: a null number is an ordinary run.
- **Midnight in Spain.** "did i see tom hanks already because it was past 12 yesterday for me": the per-device day worked exactly as specced on its first night, and the results function's start check is what proved it.

### Media index

- `media/4f948fc0/shots_s-settings.png`: Settings in light mode with the new Privacy policy, Suggest a feature and Contact rows. Embedded. Oct 26 ~08:28.
- `media/4f948fc0/shots_s-settings-dark.png`: the same in dark mode. Embedded. ~08:28.
- `media/4f948fc0/shots_settings.png`, `shots_settings-dark.png`: the same two screenshots at full size, before downscaling.
- `media/4f948fc0/privacy.png`: a render of the draft privacy page at phone width, from the site's working copy, used to check the layout. Not embedded: it's a long image that wouldn't be readable at diary size. ~08:31.
- Sessions `be4a0e49`, `716720e0` and `875718fd` captured no screenshots or other media. (`875718fd`'s coverage script and results stayed in that session's temporary folder.)
- `media/b738c613/homeSE.png`: the SE home on day #1 with the DAILY #1 tag. Embedded. Oct 26 ~21:36.
- `media/b738c613/home16.png`: the same on the iPhone 16. ~21:36.
- `media/b738c613/pillSE.png`: the SE header with the TODAY pill after a random deal (rendered by a throwaway hook). Embedded. ~21:36.
- `media/b738c613/pasted-1.png`: Abraham's Supabase new-project form, before the two changes. Embedded. ~22:51.
- `media/b738c613/release.png`, `release2.png`: a fresh Release install, 12s and 27s in, the daily with a placeholder avatar while the pool loaded. ~23:11.
- `media/b738c613/release3.png`: after the first fix (observation only), still no photo. Embedded. ~23:14.
- `media/b738c613/release4.png`: after the second fix, Tom Hanks' photo shows. Embedded. ~23:16.
- Session `e81853bc` captured no screenshots or other media.
