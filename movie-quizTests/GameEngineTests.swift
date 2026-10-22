//
//  GameEngineTests.swift
//  movie-quizTests
//
//  Locks the async-safety of the engine's candidate loading: a slow filmography /
//  cast fetch from an abandoned game must never install its results into a new
//  game started while it was in flight. See `GameEngine.generation`.
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct GameEngineTests {

    /// Each test gets its own defaults suite, so no run writes a best into the
    /// app's real records (or reads one left by another test).
    private let defaults = UserDefaults(suiteName: "GameEngineTests-\(UUID().uuidString)")!

    private func makeEngine(_ provider: any MovieDataProvider, collection: CollectionStore? = nil) -> GameEngine {
        GameEngine(provider: provider, collection: collection, defaults: defaults)
    }

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

    @Test func staleCandidateLoadDoesNotCorruptNewGame() async {
        let provider = RaceProvider()
        provider.filmographies = [
            1: [Movie(id: 101, title: "Aardvark Adventures", year: nil)],
            2: [Movie(id: 202, title: "Bumblebee Ballad", year: nil)],
        ]
        let engine = makeEngine(provider)

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
        #expect(engine.score == 0, "stale candidates from the abandoned game leaked into the new round")
        #expect(engine.feedback != nil)

        // …and actor #2's film accepted.
        await engine.submit("Bumblebee Ballad")
        #expect(engine.score == 1)
        #expect(engine.chain.last?.id == "m202")
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

    @Test func partialPoolLoadRetriesFailedSideOnly() async {
        let provider = CountingPoolProvider()   // actor side fails once, then succeeds
        let engine = makeEngine(provider)

        await engine.prepareSeeds()

        // The movie side landed on the first attempt and must not be re-fetched…
        #expect(provider.movieCalls == 1, "an already-loaded side must not be re-fetched")
        // …while the empty actor side must have been retried (not cached as loaded).
        #expect(provider.actorCalls >= 2, "a failed/empty side must be retried")
        // A start is dealt regardless (movie-only until actors land, then either).
        #expect(engine.dealtSeed != nil)
    }

    // MARK: Reel logging

    /// A small connected graph so a run can actually complete a link.
    @MainActor
    final class SimpleGraphProvider: MovieDataProvider {
        func searchActors(_ query: String) async throws -> [Person] { [] }
        func searchMovies(_ query: String) async throws -> [Movie] { [] }
        func popularActors() async throws -> [Person] { (1...5).map { Person(id: $0, name: "Actor \($0)") } }
        func popularMovies() async throws -> [Movie] { (10...14).map { Movie(id: $0, title: "Movie \($0)", year: 2000) } }
        func cast(of movie: Movie) async throws -> [Person] { (1...4).map { Person(id: $0, name: "Actor \($0)") } }
        func filmography(of actor: Person) async throws -> [Movie] {
            [Movie(id: 100, title: "Film 100", year: 2001),
             Movie(id: 101, title: "Film 101", year: 2002)]
        }
    }

    @Test func completedChainLogsToTheReel() async {
        let store = CollectionStore(fileURL: nil)      // no disk
        let engine = makeEngine(SimpleGraphProvider(), collection: store)
        await engine.startGame(with: .actor(Person(id: 1, name: "Actor 1")))

        await engine.submit("Film 100")
        engine.quit()

        #expect(store.total == 2, "a chain of 2 logs both nodes")
        #expect(engine.summary?.reelAdditions == 2)
        #expect(engine.summary?.missedAnswer == nil, "a quit has no missed turn")
    }

    /// The game-over screen reads the run from its summary, so "Play again" —
    /// which resets the live run while that screen is still sliding away —
    /// can't change what it shows on the way out.
    @Test func summaryKeepsTheRunAfterPlayAgain() async throws {
        let engine = makeEngine(SimpleGraphProvider())
        await engine.startGame(with: .actor(Person(id: 1, name: "Actor 1")))
        await engine.submit("Film 100")
        let points = engine.points
        engine.quit()
        let summary = try #require(engine.summary)

        engine.reset()

        #expect(engine.score == 0 && engine.points == 0 && engine.chain.isEmpty)
        #expect(summary.links == 1)
        #expect(summary.points == points && points > 0)
        #expect(summary.chain.map(\.id) == ["p1", "m100"])
        #expect(summary.shareText.hasSuffix("🟦🟨"))
    }

    // MARK: Candidate-load resilience (the "stuck turn" fix)

    /// Fails the first N candidate fetches (a transient rate limit / timeout), then
    /// succeeds — to exercise `loadCandidates`' retry and the manual `retryTurn`.
    @MainActor
    final class FlakyCandidateProvider: MovieDataProvider {
        var failFilmographyTimes = 1
        private(set) var filmographyCalls = 0

        func searchActors(_ query: String) async throws -> [Person] { [] }
        func searchMovies(_ query: String) async throws -> [Movie] { [] }
        func popularActors() async throws -> [Person] { [] }
        func popularMovies() async throws -> [Movie] { [] }
        func cast(of movie: Movie) async throws -> [Person] { [] }
        func filmography(of actor: Person) async throws -> [Movie] {
            filmographyCalls += 1
            if filmographyCalls <= failFilmographyTimes { throw DataProviderError.badResponse(429) }
            return [Movie(id: 100, title: "Film 100", year: 2001)]
        }
    }

    @Test func candidateLoadRetriesTransientFailure() async {
        let provider = FlakyCandidateProvider()   // first fetch throws, then succeeds
        let engine = makeEngine(provider)
        await engine.startGame(with: .actor(Person(id: 1, name: "Actor 1")))

        #expect(!engine.awaitingRetry, "a transient failure should be retried, not surfaced")
        await engine.submit("Film 100")   // candidates loaded → a valid answer is accepted
        #expect(engine.score == 1, "the turn was not stuck")
    }

    @Test func retryTurnRecoversAfterExhaustedRetries() async {
        let provider = FlakyCandidateProvider()
        provider.failFilmographyTimes = Config.candidateLoadAttempts   // all initial attempts fail
        let engine = makeEngine(provider)
        await engine.startGame(with: .actor(Person(id: 1, name: "Actor 1")))

        #expect(engine.awaitingRetry, "an exhausted load must surface the Retry affordance")
        await engine.retryTurn()           // next fetch succeeds
        #expect(!engine.awaitingRetry)
        await engine.submit("Film 100")
        #expect(engine.score == 1)
    }

    // MARK: Records

    @Test func newRecordPersistsToInjectedDefaults() async {
        let engine = makeEngine(SimpleGraphProvider())
        await engine.startGame(with: .actor(Person(id: 1, name: "Actor 1")))
        await engine.submit("Film 100")
        engine.quit()

        #expect(engine.summary?.isNewBest == true)
        #expect(defaults.integer(forKey: "bestChain") == 1)
        // A fresh engine on the same defaults picks the record back up.
        #expect(makeEngine(SimpleGraphProvider()).bestChain == 1)
    }

}
