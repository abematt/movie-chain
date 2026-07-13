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

    /// Transient feedback for a rejected / off-list answer.
    private(set) var feedback: String?
    private(set) var isChecking = false

    // MARK: Records & recap

    /// Best chain length ever, persisted across launches.
    private(set) var bestChain: Int
    /// Best point total ever, persisted across launches.
    private(set) var bestPoints: Int
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

    // MARK: Private

    private let provider: MovieDataProvider
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

    init(provider: MovieDataProvider? = nil, collection: CollectionStore? = nil) {
        // Resolve the default in the init body (which is @MainActor-isolated),
        // not in a default argument — default arguments evaluate in a
        // nonisolated context, and Config.makeProvider() is @MainActor under
        // the project's MainActor-default isolation.
        self.provider = provider ?? Config.makeProvider()
        self.collection = collection
        self.bestChain = UserDefaults.standard.integer(forKey: Self.bestChainKey)
        self.bestPoints = UserDefaults.standard.integer(forKey: Self.bestPointsKey)
    }

    var current: ChainNode? { chain.last }

    /// A spoiler-free, shareable recap of the finished run: the score line plus a
    /// blue/purple square rendering of the chain (🟦 actor, 🟪 movie) — the
    /// Connections-style share card. Pure text, so the engine stays UIKit-free.
    var shareSummary: String {
        let squares = chain.map { $0.kind == .actor ? "🟦" : "🟪" }.joined()
        let linkWord = score == 1 ? "link" : "links"
        return "Movie Chain 🎬\n\(score) \(linkWord) · \(points) pts\n\(squares)"
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

    func startGame(with seed: ChainNode) async {
        generation += 1                            // invalidate any prior run's in-flight load
        let token = generation
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

        // Accept the link. Pause the timer during the network fetch so a slow
        // candidate load can't fire game-over on an answer submitted in time.
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
            isChecking = false
        } catch {
            guard generation == token else { return }
            candidates = []
            feedback = error.localizedDescription
            isChecking = false
        }
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
        generation += 1                            // drop any in-flight candidate load
        countdownTask?.cancel()
        countdownTask = nil
        endedByQuit = quit

        // "You were one away": surface a valid answer the player didn't give on
        // the turn that ran out — the sting that drives the next run. Skip it on a
        // manual quit: there was no missed turn.
        missedAnswer = quit ? nil : candidates.first { !usedIds.contains($0.id) }

        // Commit records.
        if score > bestChain {
            bestChain = score
            isNewBest = true
            UserDefaults.standard.set(bestChain, forKey: Self.bestChainKey)
        }
        if points > bestPoints {
            bestPoints = points
            UserDefaults.standard.set(bestPoints, forKey: Self.bestPointsKey)
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
    func loadDemoChain() {
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
        expectedKind = chain.last?.nextKind ?? .movie
        candidates = [.actor(Person(id: 9, name: "Jack Nicholson"))]
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
