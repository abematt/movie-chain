# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope note

This repo lives under `/Users/abrahammathew/dev/`, which is nested inside a Measure Protocol
workspace. Ancestor `CLAUDE.md` files (Measure workspace, Django/Docker services, survey tooling,
etc.) are **not relevant here** — this is a standalone native iOS/SwiftUI app. Ignore the Measure
guidance when working in this repository; only this file and the code apply.

## Project

`movie-quiz` — a SwiftUI game (working title "Movie Chain"). You build a chain
that alternates actor → movie → actor → movie …, where each link must be real
(the actor appeared in the movie). Score = chain length; each turn is timed.

- Bundle ID: `abe.movie-quiz`
- Language: Swift 5.0, SwiftUI + Observation (`@Observable`), iOS 17+ APIs
- Deployment target: iOS 26.2 (high — only installs on a 26.x runtime; lower it
  in build settings if broader device/simulator support is wanted)
- Supported platforms: iOS, iPad, macOS, visionOS
- Single app target (`movie-quiz`), single scheme. No test target yet.
- Files are auto-included via `PBXFileSystemSynchronizedRootGroup` — just add
  `.swift` files under `movie-quiz/`, no `.pbxproj` editing needed.

## Commands

Build/run/test from the command line with `xcodebuild` (project, not workspace):

```bash
# List targets, configs, schemes
xcodebuild -list -project movie-quiz.xcodeproj

# Build for the simulator
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests (no test target exists yet — add one before this is useful)
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test after tests exist (XCTest)
xcodebuild -scheme movie-quiz -project movie-quiz.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:movie-quizTests/SomeTestCase/testSomething
```

Day-to-day development is normally done in Xcode (⌘B build, ⌘R run, ⌘U test). `#Preview` blocks
drive SwiftUI canvas previews.

## Architecture

The game logic is fully decoupled from both the UI and the data source.

**Data layer** — everything speaks the `MovieDataProvider` protocol
(`MovieDataProvider.swift`): global `searchActors`/`searchMovies` (used only to
pick the seed node) plus `cast(of:)` and `filmography(of:)` (the *bounded
candidate sets* used to validate every subsequent link).
- `TMDBProvider.swift` — live implementation over the TMDB REST API.
- `StubProvider.swift` — a small hardcoded movie/cast graph so the game is
  playable with no network/key. `Config.makeProvider()` picks TMDB when a token
  is set, else the stub.

**Validation & the spelling problem** — players type free text; there is no
autocomplete (that would spoil a recall game). Because the set of valid answers
each turn is small and known (one movie's cast, or one actor's filmography),
`FuzzyMatch.bestMatch` matches the typed text against just that bounded set with
spelling tolerance (diacritic-folded, punctuation-stripped Levenshtein + whole-
word/substring boosts, threshold ~0.72). This is why misspellings like "John
Malkovic" resolve correctly without global fuzzy search or false positives.

**Game engine** — `GameEngine.swift` (`@MainActor @Observable`) owns all state:
`phase` (seed → playing → gameOver), the `chain`, `score`, per-turn countdown,
the current candidate set, and `usedIds` (no-repeat rule). Every entity resolves
to a stable TMDB id, so validation and dedup are exact. `Config.swift` holds
tunables (`secondsPerTurn`) and loads the TMDB credential at runtime from a
**gitignored** `movie-quiz/TMDBSecrets.plist` (copy `TMDBSecrets.example.plist`
and paste a token; absent → app falls back to `StubProvider` demo data). The
token is never committed to source.

**UI** — `ContentView.swift` routes on `engine.phase` between `SeedView`,
`GameView`, and `GameOverView`.

Planned fan-out modes (genre locks, memory-recall every Nth link, leaderboards)
all layer on this same engine — keep the engine/provider split clean.

## Running it

Build succeeds for the simulator. Because the deployment target is iOS 26.2, run
on a 26.x simulator runtime (e.g. iOS 26.4), not 18.x. In Xcode: pick an iOS 26+
simulator and ⌘R.
