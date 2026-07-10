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
    private(set) var score = 0
    private(set) var secondsRemaining = Config.secondsPerTurn

    /// What the current turn expects (actor or movie).
    private(set) var expectedKind: NodeKind = .actor

    /// Transient feedback for a rejected / off-list answer.
    private(set) var feedback: String?
    private(set) var isChecking = false

    /// The kind chosen for the seed search.
    var seedKind: NodeKind = .actor

    // MARK: Private

    private let provider: MovieDataProvider
    /// Valid next nodes for the current turn (cast or filmography), pre-wrapped.
    private var candidates: [ChainNode] = []
    private var usedIds: Set<String> = []
    private var countdownTask: Task<Void, Never>?

    init(provider: MovieDataProvider? = nil) {
        // Resolve the default in the init body (which is @MainActor-isolated),
        // not in a default argument — default arguments evaluate in a
        // nonisolated context, and Config.makeProvider() is @MainActor under
        // the project's MainActor-default isolation.
        self.provider = provider ?? Config.makeProvider()
    }

    var current: ChainNode? { chain.last }

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
            feedback = error.localizedDescription
            return []
        }
    }

    func startGame(with seed: ChainNode) async {
        chain = [seed]
        usedIds = [seed.id]
        score = 0
        feedback = nil
        phase = .playing
        await loadCandidates(for: seed)
        guard phase == .playing else { return }   // reset() during the await
        startCountdown()
    }

    // MARK: Play

    /// Validate the player's free-text answer against the bounded candidate set.
    func submit(_ text: String) async {
        guard phase == .playing, !isChecking else { return }
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
        chain.append(node)
        usedIds.insert(node.id)
        score += 1
        await loadCandidates(for: node)

        // The game may have been reset (or otherwise left play) during the
        // await; only resume the clock if we're still playing this chain.
        guard phase == .playing else { return }
        startCountdown()
    }

    func reset() {
        countdownTask?.cancel()
        countdownTask = nil
        chain = []
        usedIds = []
        candidates = []
        score = 0
        feedback = nil
        secondsRemaining = Config.secondsPerTurn
        phase = .seed
    }

    // MARK: Candidates

    private func loadCandidates(for node: ChainNode) async {
        expectedKind = node.nextKind
        isChecking = true
        defer { isChecking = false }
        do {
            switch node {
            case .movie(let movie):
                candidates = try await provider.cast(of: movie).map(ChainNode.actor)
            case .actor(let actor):
                candidates = try await provider.filmography(of: actor).map(ChainNode.movie)
            }
        } catch {
            candidates = []
            feedback = error.localizedDescription
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

    private func endGame() {
        countdownTask?.cancel()
        countdownTask = nil
        phase = .gameOver
    }
}
