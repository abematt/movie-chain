---
name: diary
description: Write the next chapter of the Unspool dev diary from captured sessions, commits and phone photos, then rebuild the diary page. Use when the user says "/diary", "write the diary", "diary entry", or when cutting a version.
---

# /diary — write the next chapter

The diary lives in `diary/`. It is raw reference material Abraham writes posts from:
complete, concrete, his own words, the *why* behind decisions. Not polished prose.
`diary/README.md` describes the layout; `diary/05-oct22-unspool.md` is a good model
of a finished chapter.

## 1. Capture

Run `scripts/diary-capture.py --backfill`. The SessionEnd hook normally does this,
but a session killed without ending (closed terminal) is only picked up here, and
the current session hasn't ended yet.

## 2. Find what's unwritten

- `diary/raw/sessions.json` lists every captured session (start, end, branches,
  first prompt). Each chapter's front matter lists the sessions it covers
  (`sessions:`) and when it ends (`end:`).
- New material is every session not listed in any chapter, plus the part of a
  listed session after that chapter's `end`.
- Also: `git log` since the last chapter's `end`, `CHANGELOG.md` `[Unreleased]`,
  and anything in `diary/inbox/`.
- If nothing is new, say so and stop.

## 3. File phone media from `diary/inbox/`

Move each file to `diary/media/past-builds/` (or `media/<YYYY-MM-DD>/` for new
captures), named `PHOTO-YYYY-MM-DD-HH-MM.jpg` / `VIDEO-…mp4` from the capture time
(filename, else `mdls -name kMDItemContentCreationDate`). Match each to the latest
commit before it, and say when the screen shows something that wasn't committed yet.
Look at every image before using it. Leave out anything that isn't the app
(screenshots of other apps, bills, personal messages) and tell the user.

## 4. Write the chapter

One chapter per release: if the latest chapter's `versions:` is a version that hasn't
been tagged yet, extend that chapter; otherwise start `NN-<mmmdd>-<slug>.md` with the
next number. Front matter (the build reads it):

```
---
id: <short-slug>
label: <2–3 word nav label>
span: <e.g. Oct 23 09:10 – 18:40>
versions: <version this work ships in>
accent: blue | coral | yellow | good   (rotate; differ from the previous chapter)
order: <next number>
sessions: <sid8 sid8 …>
start: <YYYY-MM-DD>
end: <YYYY-MM-DDTHH:MM>  (local time of the last thing covered)
---
```

Body, in this order:
- `## Era: <title>` and a short arc paragraph.
- Dated entries, `### YYYY-MM-DD ~HH:MM — <headline>` (local time), each with: the ask,
  what was tried, **Decisions** (decision — why — alternatives rejected), Abraham's
  words quoted verbatim (short, typos kept), bugs and gotchas, commit SHAs, and
  screenshots embedded as `![what's on screen and why it was taken](media/<sid8>/<file>)`.
  Recordings are links: `[▶ name.mp4](media/<sid8>/name.mp4)`.
- `### Decision log` — a 4-column table `| Time (local) | Decision | Rationale | Source |`.
  The page's decision explorer reads this table, so keep the four columns.
- `### Story material` — anecdotes, reversals, numbers, quotes worth reusing.
- `### Media index` — every file in the session media folders, one line each.

Read `diary/raw/<date>-<sid8>.txt` for each session. Several long sessions: hand
one to each subagent, then merge their sections. View the images you embed with
Read; don't caption from filenames alone. Mark inferences "(inferred)". Times are
local (the raw files already are).

## 5. Rebuild and commit

- `python3 diary/build_html.py`. It writes downscaled copies of the referenced
  images to `diary/web/` and builds `diary/index.html`.
- Commit the chapter and `diary/web/` together: `Diary: <what the chapter covers>`.
  `diary/media/`, `diary/raw/`, `diary/inbox/` and `index.html` are gitignored and
  stay local. The repo is public: no secrets, tokens or other people's personal
  details in a chapter.
- Don't publish the page anywhere. If the user asks, build it locally and ask which
  account they're logged into first.
