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
        func popularActors() async throws -> [Person] { [] }
        func popularMovies() async throws -> [Movie] { [] }
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

    // MARK: Seed-pool per-side load / retry

    /// Counts pool fetches and can fail the actor side for the first N calls, to
    /// exercise the per-side load: a failed/empty side must NOT be cached as
    /// loaded (so it retries), while an already-loaded side must NOT be re-fetched.
    @MainActor
    final class CountingPoolProvider: MovieDataProvider {
        private(set) var actorCalls = 0
        private(set) var movieCalls = 0
        /// The actor side returns empty (simulating a rate-limited/failed derive)
        /// until this many calls have been made.
        var actorsSucceedFromCall = 2

        func searchActors(_ query: String) async throws -> [Person] { [] }
        func searchMovies(_ query: String) async throws -> [Movie] { [] }
        func cast(of movie: Movie) async throws -> [Person] { [] }
        func filmography(of actor: Person) async throws -> [Movie] { [] }

        func popularActors() async throws -> [Person] {
            actorCalls += 1
            return actorCalls < actorsSucceedFromCall ? [] : [Person(id: 1, name: "Famous Actor")]
        }
        func popularMovies() async throws -> [Movie] {
            movieCalls += 1
            return [Movie(id: 10, title: "Famous Movie", year: 2001)]
        }
    }

    func testPartialPoolLoadRetriesFailedSideOnly() async {
        let provider = CountingPoolProvider()   // actor side fails once, then succeeds
        let engine = GameEngine(provider: provider)

        await engine.prepareSeeds()

        // The movie side landed on the first attempt and must not be re-fetched…
        XCTAssertEqual(provider.movieCalls, 1, "an already-loaded side must not be re-fetched")
        // …while the empty actor side must have been retried (not cached as loaded).
        XCTAssertGreaterThanOrEqual(provider.actorCalls, 2, "a failed/empty side must be retried")
        // A start is dealt regardless (movie-only until actors land, then either).
        XCTAssertNotNil(engine.dealtSeed)
    }
}
