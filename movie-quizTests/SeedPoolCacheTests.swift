//
//  SeedPoolCacheTests.swift
//  movie-quizTests
//
//  The deal pools saved on disk: a fresh copy deals with no requests, a stale one
//  is refetched and rewritten, and when the network fails the home deals from
//  the stale copy or, with none, reports `dealFailed` instead of hanging on
//  "Dealing…".
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct SeedPoolCacheTests {

    private let defaults = UserDefaults(suiteName: "SeedPoolCacheTests-\(UUID().uuidString)")!
    private let fileURL = URL.temporaryDirectory.appending(path: "seed-pool-\(UUID().uuidString).json")
    private static let day: TimeInterval = 24 * 60 * 60

    private let cachedActors = [Person(id: 1, name: "Cached Actor")]
    private let cachedMovies = [Movie(id: 10, title: "Cached Movie", year: 1999)]

    /// Serves one fixed pool, or throws while `offline`, counting every call.
    @MainActor
    final class PoolProvider: MovieDataProvider {
        struct Offline: Error {}
        var offline = false
        private(set) var calls = 0
        static let actors = [Person(id: 2, name: "Live Actor")]
        static let movies = [Movie(id: 20, title: "Live Movie", year: 2010)]

        func searchActors(_ query: String) async throws -> [Person] { [] }
        func searchMovies(_ query: String) async throws -> [Movie] { [] }
        func cast(of movie: Movie) async throws -> [Person] { [] }
        func filmography(of actor: Person) async throws -> [Movie] { [] }
        func popularActors() async throws -> [Person] {
            calls += 1
            if offline { throw Offline() }
            return Self.actors
        }
        func popularMovies() async throws -> [Movie] {
            calls += 1
            if offline { throw Offline() }
            return Self.movies
        }
    }

    private func cache(maxAge: TimeInterval = 7 * day) -> SeedPoolCache {
        SeedPoolCache(fileURL: fileURL, maxAge: maxAge)
    }

    /// Writes the cached pools as if fetched `age` ago.
    private func seedCache(age: TimeInterval) throws {
        let snapshot = SeedPoolSnapshot(savedAt: Date().addingTimeInterval(-age),
                                        actors: cachedActors, movies: cachedMovies)
        try JSONEncoder().encode(snapshot).write(to: fileURL)
    }

    private func dealtIDs(_ engine: GameEngine) -> Int? { engine.dealtSeed?.tmdbID }

    // MARK: The engine

    @Test func aFreshCopyDealsWithoutAnyRequests() async throws {
        try seedCache(age: Self.day)
        let provider = PoolProvider()
        let engine = GameEngine(provider: provider, poolCache: cache(), defaults: defaults,
                                today: { .distantPast })   // before the daily start, so these deal from the pool

        await engine.prepareSeeds()

        #expect(provider.calls == 0)
        #expect([1, 10].contains(dealtIDs(engine)))
        #expect(!engine.dealFailed)
    }

    @Test func aStaleCopyIsRefetchedAndRewritten() async throws {
        try seedCache(age: 8 * Self.day)
        let provider = PoolProvider()
        let engine = GameEngine(provider: provider, poolCache: cache(), defaults: defaults,
                                today: { .distantPast })   // before the daily start, so these deal from the pool

        await engine.prepareSeeds()

        #expect(provider.calls == 2)
        #expect([2, 20].contains(dealtIDs(engine)))
        let saved = try #require(cache().load())
        #expect(saved.isFresh)
        #expect(saved.snapshot.actors == PoolProvider.actors)
        #expect(saved.snapshot.movies == PoolProvider.movies)
    }

    @Test func offlineDealsFromTheStaleCopy() async throws {
        try seedCache(age: 30 * Self.day)
        let provider = PoolProvider()
        provider.offline = true
        let engine = GameEngine(provider: provider, poolCache: cache(), defaults: defaults,
                                today: { .distantPast })   // before the daily start, so these deal from the pool

        await engine.prepareSeeds()

        #expect([1, 10].contains(dealtIDs(engine)))
        #expect(!engine.dealFailed)
        // The fallback isn't new data, so it's never written back as fresh.
        #expect(cache().load()?.isFresh == false)
    }

    @Test func offlineWithNothingSavedFailsThenRecoversOnRetry() async {
        let provider = PoolProvider()
        provider.offline = true
        let engine = GameEngine(provider: provider, poolCache: cache(), defaults: defaults,
                                today: { .distantPast })   // before the daily start, so these deal from the pool

        await engine.prepareSeeds()
        #expect(engine.dealtSeed == nil)
        #expect(engine.dealFailed)

        provider.offline = false
        await engine.prepareSeeds()   // the home's "Reconnect"
        #expect(engine.dealtSeed != nil)
        #expect(!engine.dealFailed)
    }

    // MARK: The file

    @Test func aMissingOrUnreadableFileIsNoCopy() throws {
        #expect(cache().load() == nil)
        try Data("not json".utf8).write(to: fileURL)
        #expect(cache().load() == nil)
    }

    @Test func anotherVersionsFileIsIgnored() throws {
        var snapshot = SeedPoolSnapshot(savedAt: Date(), actors: cachedActors, movies: cachedMovies)
        snapshot.version = SeedPoolSnapshot.currentVersion + 1
        try JSONEncoder().encode(snapshot).write(to: fileURL)
        #expect(cache().load() == nil)
    }

    @Test(arguments: [(age: 6.9, fresh: true), (age: 7.1, fresh: false)])
    func freshnessIsTheMaxAge(age: Double, fresh: Bool) {
        let now = Date()
        let snapshot = SeedPoolSnapshot(savedAt: now.addingTimeInterval(-age * Self.day),
                                        actors: [], movies: [])
        #expect(snapshot.isFresh(at: now, maxAge: 7 * Self.day) == fresh)
    }
}
