---
id: website
label: Site & money
span: Oct 25 15:41 – Oct 26 21:21
versions: after 0.7.0 (unreleased)
accent: blue
order: 7
sessions: 4f948fc0 be4a0e49 716720e0 875718fd
start: 2026-10-25
end: 2026-10-26T21:21
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

### Media index

- `media/4f948fc0/shots_s-settings.png`: Settings in light mode with the new Privacy policy, Suggest a feature and Contact rows. Embedded. Oct 26 ~08:28.
- `media/4f948fc0/shots_s-settings-dark.png`: the same in dark mode. Embedded. ~08:28.
- `media/4f948fc0/shots_settings.png`, `shots_settings-dark.png`: the same two screenshots at full size, before downscaling.
- `media/4f948fc0/privacy.png`: a render of the draft privacy page at phone width, from the site's working copy, used to check the layout. Not embedded: it's a long image that wouldn't be readable at diary size. ~08:31.
- Sessions `be4a0e49`, `716720e0` and `875718fd` captured no screenshots or other media. (`875718fd`'s coverage script and results stayed in that session's temporary folder.)
