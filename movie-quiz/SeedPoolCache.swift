//
//  SeedPoolCache.swift
//  movie-quiz
//
//  The home's deal pools, kept on disk between launches. Loading them takes ~24
//  TMDB requests (5 `discover` pages, plus a page and 18 casts for the derived
//  actors), and a cold launch used to fire all of them every time. The pool is
//  one fixed `vote_count.desc` query, the same for every player and near-static,
//  so a copy from a few days ago deals as well as a fresh one.
//
//  Two ages matter. A *fresh* copy is dealt from without touching the network. A
//  *stale* one is kept as the fallback: if the refetch fails (offline, rate
//  limited), the home deals from it rather than sitting on "Dealing…".
//

import Foundation

/// What's written to disk: both pools and when they were fetched.
nonisolated struct SeedPoolSnapshot: Codable, Equatable, Sendable {
    /// Bump when the shape or the pool query changes, so an old file is ignored
    /// rather than misread.
    static let currentVersion = 1

    var version = SeedPoolSnapshot.currentVersion
    var savedAt: Date
    var actors: [Person]
    var movies: [Movie]

    func isFresh(at now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(savedAt) < maxAge
    }
}

/// Reads and writes the snapshot. Storage and the clock are injected so tests
/// never touch the app's real cache.
nonisolated struct SeedPoolCache: Sendable {
    let fileURL: URL
    var maxAge: TimeInterval = Config.seedPoolMaxAge
    var now: @Sendable () -> Date = { Date() }

    /// Caches, not Application Support: the system may purge it, and losing it
    /// only costs one refetch.
    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("seed-pool.json")
    }

    /// The saved pools, and whether they're young enough to deal from without
    /// refetching. `nil` when there's no file, it doesn't decode, or it was
    /// written by another version.
    func load() -> (snapshot: SeedPoolSnapshot, isFresh: Bool)? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(SeedPoolSnapshot.self, from: data),
              snapshot.version == SeedPoolSnapshot.currentVersion
        else { return nil }
        return (snapshot, snapshot.isFresh(at: now(), maxAge: maxAge))
    }

    /// Write freshly fetched pools, off the main actor. A failed write only
    /// means the next launch fetches again.
    @concurrent
    func save(actors: [Person], movies: [Movie]) async {
        let snapshot = SeedPoolSnapshot(savedAt: now(), actors: actors, movies: movies)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
