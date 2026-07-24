//
//  GameEngine.swift
//  movie-quiz
//
//  The core chain game: alternating actor/movie nodes, each link validated
//  against the bounded candidate set of the previous node, with a per-turn
//  timer and a running score.
//

import Foundation
import Observation

/// How a run is played. Chosen once per run on the home screen (a *session-level*
/// choice, not per-turn) and fixed for the whole game.
/// - `hardcore`: the recall game — type the answer from memory, fuzzy-matched.
/// - `assisted`: recognition — every turn presents `Config.optionCount` options
///   (1 correct + distractors) and you tap. A wrong tap docks the clock.
///
/// The two never share a leaderboard: an assisted run writes only the assisted
/// record track and never touches the hardcore best. The flag rides along so a
/// future split-leaderboard backend can separate the boards server-side.
enum Difficulty: String, CaseIterable, Sendable, Identifiable {
    case hardcore
    case assisted

    var id: String { rawValue }
    var label: String { self == .hardcore ? "Hardcore" : "Assisted" }
    /// Whether the turn is answered by tapping an option rather than typing.
    var isAssisted: Bool { self == .assisted }
}

@MainActor
@Observable
final class GameEngine {

    enum Phase {
        case seed          // choosing the starting actor/movie
        case playing
        case gameOver
    }

    // MARK: State

    private(set) var phase: Phase = .seed
    private(set) var chain: [ChainNode] = []
    /// The headline metric: chain length (accepted links). Drives the flame and
    /// the hero number.
    private(set) var score = 0
    /// Richer secondary score — base + speed + obscurity, accumulated per link.
    private(set) var points = 0
    /// Points awarded for the most recent link (drives the "+N" flourish).
    private(set) var lastGain = 0
    /// Whether the last accepted answer beat the "fast" threshold.
    private(set) var lastAnswerFast = false
    private(set) var secondsRemaining = Config.secondsPerTurn

    /// What the current turn expects (actor or movie).
    private(set) var expectedKind: NodeKind = .actor

    /// How this run is being played, fixed at `startGame`. Drives whether the UI
    /// docks the keyboard (hardcore) or shows tappable options (assisted), and
    /// which record track the run writes.
    private(set) var difficulty: Difficulty = .hardcore

    /// The multiple-choice option set for the current turn in Assisted mode
    /// (1 correct + distractors, shuffled). Empty in Hardcore. Rebuilt whenever the
    /// candidate set changes (`loadCandidates`).
    private(set) var currentOptions: [ChainNode] = []

    /// Transient feedback for a rejected / off-list answer.
    private(set) var feedback: String?
    private(set) var isChecking = false

    // MARK: Records & recap

    /// Best chain length ever in **Hardcore**, persisted across launches.
    private(set) var bestChain: Int
    /// Best point total ever in **Hardcore**, persisted across launches.
    private(set) var bestPoints: Int
    /// Best chain length / points ever in **Assisted** — a separate track, so an
    /// easy-mode run never clobbers the hardcore record and vice versa.
    private(set) var bestChainAssisted: Int
    private(set) var bestPointsAssisted: Int

    /// The best chain / points for the mode the current run is (or just was)
    /// played in — what the game-over screen shows as "your best".
    var bestChainForRun: Int { difficulty.isAssisted ? bestChainAssisted : bestChain }
    var bestPointsForRun: Int { difficulty.isAssisted ? bestPointsAssisted : bestPoints }
    /// Set at game over when this run beat the previous best chain — the trigger
    /// for the celebration on the game-over screen.
    private(set) var isNewBest = false
    /// A valid answer the player *didn't* give on the turn that timed out — the
    /// "you were one away" near-miss shown at game over. `nil` on a manual quit
    /// (there was no missed turn — the player chose to stop).
    private(set) var missedAnswer: ChainNode?
    /// Whether this run ended because the player tapped Quit (vs. the clock
    /// running out). Lets the summary avoid a misleading "Time's up".
    private(set) var endedByQuit = false
    /// How many brand-new actors/movies this run added to the collection ("Your
    /// Reel") — the "+N to your Reel" figure shown at game over.
    private(set) var reelAdditions = 0

    /// The kind chosen for the seed search.
    var seedKind: NodeKind = .actor

    /// The start currently dealt on the home screen (the "Start with …" button).
    /// `nil` until the popularity pool has loaded and the first deal lands — the
    /// home shows a placeholder until then.
    private(set) var dealtSeed: ChainNode?

    // MARK: Private

    private let provider: MovieDataProvider
    /// Popularity-ranked pools the home deals from, fetched once and cached.
    private var actorPool: [Person] = []
    private var moviePool: [Movie] = []
    /// Per-side load state. Tracked independently so one side failing (or being
    /// rate-limited) can't lock in a *partial* pool for the session — the missing
    /// side is retried on later prepares/shuffles. A side is only "loaded" once it
    /// actually returned entries (an empty result means it failed → retry).
    private var actorsLoaded = false
    private var moviesLoaded = false
    /// Enough of a pool to deal *something* (at least one side landed).
    private var poolReady: Bool { actorsLoaded || moviesLoaded }
    /// Both sides landed — no further loading needed.
    private var poolComplete: Bool { actorsLoaded && moviesLoaded }
    /// `ChainNode.id`s dealt recently, so repeated shuffles stay fresh. Bounded to
    /// `Config.seedRecentWindow`.
    private var recentSeedIds: [String] = []
    /// Concrete generator for deals (a stored `var` so it can be passed `inout` to
    /// the generic `SeedDeal.pick`). Selection policy is unit-tested separately in
    /// `SeedDeal` with a seeded generator, so the engine needs no injectable RNG.
    private var systemRNG = SystemRandomNumberGenerator()
    /// The registry every completed chain is logged into. Optional so previews
    /// and tests can run without touching disk.
    private let collection: CollectionStore?
    /// Valid next nodes for the current turn (cast or filmography), pre-wrapped.
    private var candidates: [ChainNode] = []
    private var usedIds: Set<String> = []
    private var countdownTask: Task<Void, Never>?
    /// Monotonic token identifying the current run/turn's async work. Every
    /// lifecycle transition (start, end, reset) bumps it; an async candidate load
    /// captures it before awaiting and drops its result if the token has moved on.
    /// Without this, a slow `loadCandidates` from a quit/abandoned game can resume
    /// *after* the player has started a new game and install the previous node's
    /// cast/filmography into the new round — the `phase == .playing` guard alone
    /// can't catch it, because the new game is also `.playing`.
    private var generation = 0

    private static let bestChainKey = "bestChain"
    private static let bestPointsKey = "bestPoints"
    private static let bestChainAssistedKey = "bestChainAssisted"
    private static let bestPointsAssistedKey = "bestPointsAssisted"

    init(provider: MovieDataProvider? = nil, collection: CollectionStore? = nil) {
        // Resolve the default in the init body (which is @MainActor-isolated),
        // not in a default argument — default arguments evaluate in a
        // nonisolated context, and Config.makeProvider() is @MainActor under
        // the project's MainActor-default isolation.
        self.provider = provider ?? Config.makeProvider()
        self.collection = collection
        self.bestChain = UserDefaults.standard.integer(forKey: Self.bestChainKey)
        self.bestPoints = UserDefaults.standard.integer(forKey: Self.bestPointsKey)
        self.bestChainAssisted = UserDefaults.standard.integer(forKey: Self.bestChainAssistedKey)
        self.bestPointsAssisted = UserDefaults.standard.integer(forKey: Self.bestPointsAssistedKey)
    }

    var current: ChainNode? { chain.last }

    /// A spoiler-free, shareable recap of the finished run: the score line plus a
    /// blue/purple square rendering of the chain (🟦 actor, 🟪 movie) — the
    /// Connections-style share card. Pure text, so the engine stays UIKit-free.
    var shareSummary: String {
        let squares = chain.map { $0.kind == .actor ? "🟦" : "🟪" }.joined()
        let linkWord = score == 1 ? "link" : "links"
        // Tag assisted runs so the shared 🟦🟪 card stays comparable — an assisted
        // score isn't a hardcore score, and the daily-seed social layer relies on
        // like-for-like comparison.
        let mode = difficulty.isAssisted ? " · assisted" : ""
        return "Movie Chain 🎬\n\(score) \(linkWord) · \(points) pts\(mode)\n\(squares)"
    }

    // MARK: Seed selection

    /// Global search for the starting node.
    func search(_ query: String) async -> [ChainNode] {
        do {
            switch seedKind {
            case .actor:
                return try await provider.searchActors(query).map(ChainNode.actor)
            case .movie:
                return try await provider.searchMovies(query).map(ChainNode.movie)
            }
        } catch {
            // A failed seed search surfaces as an empty result set — `SeedView`
            // shows its "no matches" empty state. Deliberately do *not* write
            // `feedback` here: that field is gameplay feedback (read by `GameView`
            // for rejected links), and a debounced seed search that only resolves
            // *after* the player has tapped a result and the round has begun would
            // otherwise buzz a stale error mid-game.
            return []
        }
    }

    // MARK: Seed deal (the home-screen "Start with …" button)

    /// Load the deal pools (once) and deal a fresh start. Called when the home
    /// screen appears, so every entry to `.seed` — cold launch or "Play again" —
    /// presents a new dealt start. While the pool loads on first launch,
    /// `dealtSeed` stays `nil` and the home shows a placeholder.
    func prepareSeeds() async {
        // Retry a transient pool-load failure a few times so a flaky first launch
        // self-heals while the player is still on the home screen. A hard failure
        // leaves the hero in its "Dealing…" state; leaving and returning retries
        // (a side stays unloaded until it actually returns entries).
        for attempt in 0..<3 {
            await loadSeedPoolsIfNeeded()
            if Task.isCancelled { return }
            if poolComplete { break }
            if attempt < 2 { try? await Task.sleep(for: .seconds(1)) }
            if Task.isCancelled { return }
        }
        guard !Task.isCancelled else { return }   // don't deal into an abandoned screen
        deal()
    }

    /// Deal a new random start on demand (the Shuffle button). Pools are usually
    /// ready by the time the player can tap; if not (a fast tap during first
    /// load), the deal is deferred until a side lands. If a side failed earlier,
    /// quietly retry it in the background so later deals can include it.
    func shuffleSeed() {
        guard poolReady else {
            Task { await loadSeedPoolsIfNeeded(); deal() }
            return
        }
        deal()
        if !poolComplete { Task { await loadSeedPoolsIfNeeded() } }
    }

    /// Re-deal when the app returns from the background while still on the home
    /// screen — "a fresh start every open/resume". No-op mid-game or before a pool
    /// side has landed (cold launch is handled by `prepareSeeds`).
    func dealFreshOnResume() {
        guard phase == .seed, poolReady else { return }
        deal()
        if !poolComplete { Task { await loadSeedPoolsIfNeeded() } }
    }

    /// Load only the pool side(s) not yet loaded, concurrently. Each side is
    /// marked loaded **only when it returns entries** — an empty result (a failed
    /// or rate-limited fetch, incl. the derived-actor task group swallowing
    /// per-cast failures) leaves that side unloaded so it retries later, rather
    /// than caching a partial (e.g. movie-only) pool for the whole session. A
    /// cancelled load (leaving the seed screen) commits nothing.
    private func loadSeedPoolsIfNeeded() async {
        guard !poolComplete else { return }
        async let actorsTask = fetchActorsIfNeeded()
        async let moviesTask = fetchMoviesIfNeeded()
        let actors = await actorsTask
        let movies = await moviesTask
        guard !Task.isCancelled else { return }
        if let actors, !actors.isEmpty { actorPool = actors; actorsLoaded = true }
        if let movies, !movies.isEmpty { moviePool = movies; moviesLoaded = true }
    }

    /// `nil` when the side is already loaded (skip) or the fetch failed.
    private func fetchActorsIfNeeded() async -> [Person]? {
        guard !actorsLoaded else { return nil }
        return try? await provider.popularActors()
    }

    private func fetchMoviesIfNeeded() async -> [Movie]? {
        guard !moviesLoaded else { return nil }
        return try? await provider.popularMovies()
    }

    private func deal() {
        guard let node = SeedDeal.pick(
            actors: actorPool,
            movies: moviePool,
            recentIds: Set(recentSeedIds),
            actorBias: Config.seedActorBias,
            using: &systemRNG
        ) else { return }
        dealtSeed = node
        recentSeedIds.append(node.id)
        if recentSeedIds.count > Config.seedRecentWindow {
            recentSeedIds.removeFirst(recentSeedIds.count - Config.seedRecentWindow)
        }
    }

    func startGame(with seed: ChainNode, difficulty: Difficulty = .hardcore) async {
        generation += 1                            // invalidate any prior run's in-flight load
        let token = generation
        self.difficulty = difficulty
        currentOptions = []
        chain = [seed]
        usedIds = [seed.id]
        score = 0
        points = 0
        lastGain = 0
        lastAnswerFast = false
        isNewBest = false
        missedAnswer = nil
        endedByQuit = false
        reelAdditions = 0
        feedback = nil
        phase = .playing
        await loadCandidates(for: seed, token: token)
        // Bail if a reset/quit/new game happened during the await.
        guard phase == .playing, generation == token else { return }
        startCountdown()
    }

    // MARK: Play

    /// Validate the player's free-text answer against the bounded candidate set.
    func submit(_ text: String) async {
        guard phase == .playing, !isChecking else { return }
        let token = generation
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let match = FuzzyMatch.bestMatch(
            for: trimmed,
            in: candidates,
            nameOf: { $0.matchText }
        )

        guard let match else {
            feedback = "Not in the \(expectedKind == .actor ? "cast" : "filmography") — try again."
            return
        }
        let node = match.item

        guard !usedIds.contains(node.id) else {
            feedback = "\(node.displayName) is already in your chain."
            return
        }
        await accept(node, token: token)
    }

    /// Tap-to-answer for Assisted mode. The tapped option is either the one valid
    /// answer (a member of the bounded candidate set) or a distractor. A correct
    /// tap advances exactly like a typed answer; a wrong tap docks the clock and
    /// keeps the turn alive so the player can pick again.
    func select(_ node: ChainNode) async {
        guard phase == .playing, difficulty.isAssisted, !isChecking else { return }
        let token = generation

        // Correct = a valid, not-yet-used answer. `currentOptions` already excludes
        // used ids and excludes every candidate from its distractors, so this
        // membership check is exactly the accept/reject decision.
        guard candidates.contains(where: { $0.id == node.id }), !usedIds.contains(node.id) else {
            applyWrongTapPenalty()
            return
        }
        await accept(node, token: token)
    }

    /// Commit an accepted link (shared by typed `submit` and tapped `select`):
    /// pause the clock across the fetch, score, extend the chain, load the next
    /// candidate set, then resume — unless the run was reset/quit mid-await.
    private func accept(_ node: ChainNode, token: Int) async {
        // Pause the timer during the network fetch so a slow candidate load can't
        // fire game-over on an answer submitted in time.
        stopCountdown()
        feedback = nil
        // Score before the clock is reset by the next turn: fast answers and
        // obscure picks bank more points.
        lastGain = Scoring.gain(secondsRemaining: secondsRemaining, popularity: node.popularity)
        lastAnswerFast = Scoring.isFast(secondsRemaining: secondsRemaining,
                                        secondsPerTurn: Config.secondsPerTurn)
        chain.append(node)
        usedIds.insert(node.id)
        score += 1
        points += lastGain
        await loadCandidates(for: node, token: token)

        // The game may have been reset/quit (or a new game started) during the
        // await; only resume the clock if this is still the same live turn.
        guard phase == .playing, generation == token else { return }
        startCountdown()
    }

    /// A wrong tap in Assisted mode: dock the clock (the only stake in a
    /// multiple-choice turn) and keep the turn alive. If the penalty runs the
    /// clock out, the turn ends just as a natural timeout would.
    private func applyWrongTapPenalty() {
        feedback = "Not quite — −\(Config.assistedWrongPenalty)s"
        secondsRemaining = max(0, secondsRemaining - Config.assistedWrongPenalty)
        if secondsRemaining == 0 { endGame() }
    }

    /// End the current run in place (the player tapped Quit): stop the clock and
    /// show the game-over summary for the chain as it stands — *not* a reset back
    /// to the seed picker. Records are committed just as a timeout would.
    func quit() {
        guard phase == .playing else { return }
        endGame(quit: true)
    }

    func reset() {
        generation += 1                            // drop any in-flight candidate load
        countdownTask?.cancel()
        countdownTask = nil
        chain = []
        usedIds = []
        candidates = []
        currentOptions = []
        score = 0
        points = 0
        lastGain = 0
        lastAnswerFast = false
        isNewBest = false
        missedAnswer = nil
        endedByQuit = false
        feedback = nil
        isChecking = false
        secondsRemaining = Config.secondsPerTurn
        phase = .seed
    }

    // MARK: Candidates

    private func loadCandidates(for node: ChainNode, token: Int) async {
        // Set synchronously (atomic with accepting the link, before any await), so
        // these are never stale writes — only the post-fetch writes below can be.
        expectedKind = node.nextKind
        isChecking = true
        // Retry a transient failure (a shared-key rate limit or a stalled request —
        // see `Config.makeProvider`'s TODO and `requestTimeout`). The clock is paused
        // across this load, so retries cost the player no time. Without this, one
        // hiccup empties `candidates` and leaves the turn with nothing to answer —
        // in Assisted, no options at all (the reported "stuck turn").
        for attempt in 0..<max(1, Config.candidateLoadAttempts) {
            do {
                let loaded: [ChainNode]
                switch node {
                case .movie(let movie):
                    loaded = try await provider.cast(of: movie).map(ChainNode.actor)
                case .actor(let actor):
                    loaded = try await provider.filmography(of: actor).map(ChainNode.movie)
                }
                // Drop a superseded result: a reset/quit/new game moved the token on
                // while this fetch was in flight, so installing its candidates would
                // corrupt the current round.
                guard generation == token else { return }
                candidates = loaded
                rebuildOptions()
                feedback = nil
                isChecking = false
                return
            } catch {
                guard generation == token else { return }
                if attempt < Config.candidateLoadAttempts - 1 {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard generation == token else { return }
                    continue
                }
                // Exhausted retries: leave an empty set the player can retry by hand
                // (`retryTurn`), rather than a silently dead turn.
                candidates = []
                currentOptions = []
                feedback = "Couldn't load the next round — tap Retry."
                isChecking = false
            }
        }
    }

    /// Whether the turn has no answers to give because the candidate load failed —
    /// the signal for the UI's manual Retry affordance (both modes). Distinct from
    /// a load still in flight (`isChecking`).
    var awaitingRetry: Bool {
        phase == .playing && !isChecking && candidates.isEmpty && !chain.isEmpty
    }

    /// Re-fetch the current turn's candidates after a load failure and restart the
    /// clock fresh (the failed load wasn't the player's fault, so it shouldn't have
    /// burned their time). Same turn/node, so it rides the current `generation`.
    func retryTurn() async {
        guard phase == .playing, !isChecking, let node = chain.last else { return }
        stopCountdown()
        let token = generation
        await loadCandidates(for: node, token: token)
        guard phase == .playing, generation == token else { return }
        startCountdown()
    }

    /// Rebuild the Assisted-mode option set from the freshly loaded candidates and
    /// the popularity pool of the kind the turn now expects. No-op (and clears the
    /// options) in Hardcore. Distractors come from the same cached deal pools the
    /// home screen uses — zero extra network.
    private func rebuildOptions() {
        guard difficulty.isAssisted else { currentOptions = []; return }
        let pool: [ChainNode] = expectedKind == .actor
            ? actorPool.map(ChainNode.actor)
            : moviePool.map(ChainNode.movie)
        currentOptions = Choices.build(
            correctFrom: candidates,
            distractorsFrom: pool,
            count: Config.optionCount,
            excluding: usedIds,
            correctPoolSize: Config.assistCorrectPoolSize,
            using: &systemRNG
        )
    }

    // MARK: Timer

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func startCountdown() {
        stopCountdown()
        secondsRemaining = Config.secondsPerTurn
        countdownTask = Task { [weak self] in
            while let self, self.secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.secondsRemaining -= 1
            }
            self?.endGame()
        }
    }

    private func endGame(quit: Bool = false) {
        // Guard against a double end: a wrong-tap penalty that zeroes the clock
        // ends the run directly, and the (now-cancelled) countdown task must not
        // end it again.
        guard phase == .playing else { return }
        generation += 1                            // drop any in-flight candidate load
        countdownTask?.cancel()
        countdownTask = nil
        endedByQuit = quit

        // "You were one away": surface a valid answer the player didn't give on
        // the turn that ran out — the sting that drives the next run. Skip it on a
        // manual quit: there was no missed turn.
        missedAnswer = quit ? nil : candidates.first { !usedIds.contains($0.id) }

        // Commit records to the track for this run's difficulty. Assisted and
        // Hardcore never cross: an easy-mode run can't set the hardcore best (and
        // vice versa), so each leaderboard stays honest.
        if difficulty.isAssisted {
            if score > bestChainAssisted {
                bestChainAssisted = score
                isNewBest = true
                UserDefaults.standard.set(bestChainAssisted, forKey: Self.bestChainAssistedKey)
            }
            if points > bestPointsAssisted {
                bestPointsAssisted = points
                UserDefaults.standard.set(bestPointsAssisted, forKey: Self.bestPointsAssistedKey)
            }
        } else {
            if score > bestChain {
                bestChain = score
                isNewBest = true
                UserDefaults.standard.set(bestChain, forKey: Self.bestChainKey)
            }
            if points > bestPoints {
                bestPoints = points
                UserDefaults.standard.set(bestPoints, forKey: Self.bestPointsKey)
            }
        }

        // Log the run into the collection. A chain of length ≥ 2 means at least
        // one link was validated, which is exactly the condition we want: the
        // seed (chain[0]) counts only once a real combination lands off it, and
        // a seed-then-quit (length 1) logs nothing. `record` dedups by id, so
        // each entity is counted once per chain.
        if chain.count >= 2 {
            reelAdditions = collection?.record(chain: chain) ?? 0
        }

        phase = .gameOver
    }

    #if DEBUG
    // MARK: Preview / QA hook
    //
    // Jump straight into a mid-game `playing` state with a sample chain so the
    // play screen (and its design-system components) can be inspected without
    // typing. Triggered by the `-uiDemoChain` launch argument in `ContentView`;
    // guarded by `#if DEBUG` so it is never compiled into release builds.
    func loadDemoChain(assisted: Bool = false) {
        func actor(_ id: Int, _ name: String) -> ChainNode { .actor(Person(id: id, name: name)) }
        func movie(_ id: Int, _ title: String, _ year: Int) -> ChainNode {
            .movie(Movie(id: id, title: title, year: year))
        }
        chain = [
            actor(1, "Brad Pitt"),
            movie(1001, "Ocean's Eleven", 2001),
            actor(2, "Matt Damon"),
            movie(1002, "The Departed", 2006),
            actor(3, "Leonardo DiCaprio"),
        ]
        usedIds = Set(chain.map(\.id))
        score = chain.count - 1
        points = score * 24
        lastGain = 24
        difficulty = assisted ? .assisted : .hardcore
        expectedKind = chain.last?.nextKind ?? .movie
        candidates = [.movie(Movie(id: 1003, title: "Inception", year: 2010))]
        currentOptions = assisted
            ? [movie(1003, "Inception", 2010),
               movie(1004, "Gladiator", 2000),
               movie(1005, "Whiplash", 2014)]
            : []
        feedback = nil
        secondsRemaining = 18
        phase = .playing
    }

    /// Same sample chain, but jump straight to the game-over summary.
    func loadDemoGameOver() {
        loadDemoChain()
        missedAnswer = candidates.first
        isNewBest = true
        phase = .gameOver
    }
    #endif
}
