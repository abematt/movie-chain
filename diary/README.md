# Unspool dev diary

Raw reference material for writing about the app. These are not finished posts. Each
chapter is a chronological log of what was built, the decisions taken and why,
Abraham's feedback (quoted verbatim, typos kept), reversals, numbers and screenshots.
Each one ends with a decision-log table, a "story material" list and a media index.
Anything marked **(inferred)** is a reading of the evidence, not something a source
states.

The first six chapters were compiled on 2026-10-22 from git, `CHANGELOG.md`, `docs/`,
the Claude Code transcripts that still existed (Oct 21–22; July–August had aged out)
and phone photos of old builds. From then on the diary grows by itself (below).

## How it grows

1. **Capture (automatic).** When a Claude Code session in this repo ends, the
   `SessionEnd` hook runs `scripts/diary-capture.py`. It writes the slimmed transcript
   to `raw/<date>-<sid8>.txt`, adds the session to `raw/sessions.json`, and copies the
   session's screenshots, recordings and pasted images into `media/<sid8>/`.
2. **Phone photos.** Drop photos and videos of builds into `inbox/`.
3. **Write (`/diary`).** Writes or extends the chapter for the current version from
   whatever isn't covered yet, then rebuilds the page. Run it at the end of a working
   day, and always before tagging a version.
4. **Read.** Open `index.html`: commit timeline, sessions by day, growth charts, a
   searchable decision log and every chapter. `python3 diary/build_html.py` rebuilds it.

## Layout

| Path | What | In git |
|---|---|---|
| `NN-*.md` | Chapters. The front matter (id, label, span, versions, accent, order, sessions, start, end) drives the page. | yes |
| `web/` | Downscaled JPEGs of every image a chapter uses, written by the build. The durable copy. | yes |
| `build_html.py`, `template.html` | The page builder. It makes `.venv/` for the `markdown` package on first run. | yes |
| `media/` | Original screenshots, photos and recordings. | no (local) |
| `raw/` | Captured transcripts and the session index. | no (local) |
| `inbox/` | Phone media waiting to be filed by `/diary`. | no (local) |
| `index.html` | The built page. | no (rebuild it) |

The repo is public. Chapters and `web/` are published with it; `raw/` and `media/`
never are.

## Chapters so far

| File | Span | Versions |
|---|---|---|
| `01-inception-to-oct21.md` | Jul 9 → Oct 21 | → 0.4.0 |
| `00-past-build-media.md` | photos from Jul 11, Jul 13, Aug 29 | pre-0.4.0 / 0.4.0 |
| `02-oct21-design-overhaul.md` | Oct 21 19:18 → Oct 22 11:37 | 0.5.0 |
| `03-oct22-swift-and-motion.md` | Oct 22 11:42 → 13:18 | 0.5.1 |
| `04-oct22-reel-cards.md` | Oct 22 13:17 → 18:08 | 0.5.2, 0.5.3 |
| `05-oct22-unspool.md` | Oct 22 18:21 → 23:55 | 0.6.0 |
| `06-oct23-design-resync.md` | Oct 23 10:35 → Oct 25 15:07 | 0.7.0 |
| `07-oct26-website-and-privacy.md` | Oct 25 15:41 → Oct 26 08:35 | after 0.7.0 (unreleased) |

## Gaps worth filling by hand

- **July–August has no screenshots or transcripts.** `01-inception-to-oct21.md` ends
  with a list of commits worth checking out and screenshotting now.
- **The diary page is local only.** Publish it only after confirming which account
  you're logged into.
