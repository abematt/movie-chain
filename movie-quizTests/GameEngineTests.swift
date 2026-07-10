//
//  GameEngineTests.swift
//  movie-quizTests
//
//  Locks the async-safety of the engine's candidate loading: a slow filmography /
//  cast fetch from an abandoned game must never install its results into a new
//  game started while it was in flight. See `GameEngine.generation`.
//

import XCTest
@testable import movie_quiz

@MainActor
final class GameEngineTests: XCTestCase {

    /// A provider that holds the *first* filmography fetch open until the test
    /// releases it, so we can deterministically interleave a slow candidate load
    /// with a brand-new game and reproduce the stale-load race. Subsequent fetches
    /// return immediately. `@MainActor` (hence `Sendable`) so all its mutable state
    /// is touched only on the main actor, exactly like the real engine.
    @MainActor
    final class RaceProvider: MovieDataProvider {
        var filmographies: [Int: [Movie]] = [:]
        private var gateFirst = true
        private(set) var firstGateReady = false
        private var firstContinuation: CheckedContinuation<Void, Never>?

        func searchActors(_ query: String) async throws -> [Person] { [] }
        func searchMovies(_ query: String) async throws -> [Movie] { [] }
        func cast(of movie: Movie) async throws -> [Person] { [] }

        func filmography(of actor: Person) async throws -> [Movie] {
            if gateFirst {
                gateFirst = false
                await withCheckedContinuation { cont in
                    firstContinuation = cont
                    firstGateReady = true
                }
            }
            return filmographies[actor.id] ?? []
        }

        /// Let the held-open first fetch complete.
        func releaseFirst() {
            firstContinuation?.resume()
            firstContinuation = nil
        }
    }

    func testStaleCandidateLoadDoesNotCorruptNewGame() async {
        let provider = RaceProvider()
        provider.filmographies = [
            1: [Movie(id: 101, title: "Aardvark Adventures", year: nil)],
            2: [Movie(id: 202, title: "Bumblebee Ballad", year: nil)],
        ]
        let engine = GameEngine(provider: provider)

        // Game 1: seed actor #1. `startGame` suspends inside the gated filmography
        // load and parks there.
        let game1 = Task { await engine.startGame(with: .actor(Person(id: 1, name: "Actor One"))) }
        while !provider.firstGateReady { await Task.yield() }

        // Abandon it and start a fresh game with actor #2, whose filmography loads
        // immediately (only the first fetch is gated).
        engine.reset()
        await engine.startGame(with: .actor(Person(id: 2, name: "Actor Two")))

        // Now let the stale Game-1 load resume. It must be dropped, not installed.
        provider.releaseFirst()
        await game1.value

        // The live candidate set must be actor #2's filmography, not the stale
        // actor #1's. Actor #1's film must be rejected…
        await engine.submit("Aardvark Adventures")
        XCTAssertEqual(engine.score, 0, "stale candidates from the abandoned game leaked into the new round")
        XCTAssertNotNil(engine.feedback)

        // …and actor #2's film accepted.
        await engine.submit("Bumblebee Ballad")
        XCTAssertEqual(engine.score, 1)
        XCTAssertEqual(engine.chain.last?.id, "m202")
    }
}
