# Website sync — where playunspool.com is out of step with the app

The site lives in its own repo, [`../unspool-site`](https://github.com/abematt/unspool-site).
Its [`docs/handover-app.md`](https://github.com/abematt/unspool-site/blob/main/docs/handover-app.md)
says what the app owes the site; **this file is the other direction**: what the site
currently says or does that the app has moved past, plus what upcoming app work will
need from the site.

**When asked "how is the website out of step?":** read this list, then re-check the
site's claims against the code (its hero copy, the footer, `privacy.html`, and the
DEBUG screenshot flags in CLAUDE.md), and update this file with what you find. When a
drift item is fixed on the site, delete it here.

## Out of step now

- **TMDB attribution wording** *(2026-10-26)*. The footer of `index.html` and
  `privacy.html` still say "This product uses the TMDB API but is not endorsed or
  certified by TMDB" (the FAQ's line). The API terms' §3 wording, which the app now
  uses, is: "This website uses TMDB and the TMDB APIs but is not endorsed, certified,
  or otherwise approved by TMDB." §3 covers websites too.

## Will need the site when it lands

- **Challenge links and the head-to-head** ([ROADMAP](ROADMAP.md#head-to-head--same-start-both-sides-see-the-score)),
  *built in the app 2026-10-27, waiting on the site*: an `apple-app-site-association`
  file so `playunspool.com/c?d=…` opens the app (app id `8ZDTABCQFP.abe.movie-quiz`,
  path `/c`), and a fallback page at `/c` for anyone without it ("Sam challenged you —
  get Unspool"). The page can read the sender's name and score from the `d` parameter
  (base64url JSON: `f` name, `l` links, `p` points, `n` the start), but should show the
  start's name at most, never the route. A reply link (with `r`) uses the same path.
- **The privacy page** must describe anything new the app collects before it ships —
  e.g. display names sent in challenges (built: a name and a random sharer id travel
  in every challenge link, and stay on the friend's phone), credit and hint analytics
  events.
- **"A frame per film"** is a site promise. If film data ever moves off TMDB to Wikidata
  ([ROADMAP](ROADMAP.md#monetization-ready--built-in-switched-off)), film cards lose
  their posters and the site's wording and hero screens need re-checking.
- **"Free on iPhone"** still holds under freemium (free to play, optional purchases);
  revisit the wording if purchases ship.
