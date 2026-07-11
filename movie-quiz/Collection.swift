//
//  Collection.swift
//  movie-quiz
//
//  "Your Reel" — the registry of every actor and movie the player has logged
//  through play. Each accepted chain contributes its links; the store dedups by
//  stable TMDB id so the counts mean "distinct people/films you knew", not raw
//  submissions.
//
//  Two pieces, mirroring the rest of the app's split:
//  - `CollectedEntity` is a pure `Codable` value (like `Scoring`/`FuzzyMatch`
//    inputs) so the dedup/rollup logic is unit-testable with no container.
//  - `CollectionStore` is the `@Observable` owner the views read, persisting a
//    JSON snapshot to Application Support (no SwiftData — the data is a small
//    bounded dictionary, and this keeps parity with the engine's UserDefaults
//    records).
//
//  The one logging rule lives in `record(chain:)`, called once from
//  `GameEngine.endGame`: see that method for why a chain of length ≥ 2 is the
//  exact condition that makes "seeds count, but only once a link lands off them,
//  and only for successful combinations" fall out for free.
//

import Foundation
import Observation

// MARK: - CollectedEntity

/// One actor or movie the player has logged, deduped by TMDB id. A plain value
/// type persisted as JSON. `nonisolated` so its `Codable` conformance can be
/// used off the main actor (the background save task) under the project's
/// MainActor-default isolation.
nonisolated struct CollectedEntity: Codable, Identifiable, Hashable, Sendable {
    let kind: NodeKind
    let tmdbID: Int
    /// Bare name / title (no year decoration) — refreshed if we later see richer
    /// metadata for the same id.
    var name: String
    /// Release year, movies only.
    var year: Int?
    /// TMDB `profile_path` / `poster_path`, when known.
    var imagePath: String?
    /// First time this entity entered a completed chain.
    var firstSeen: Date
    /// Most recent completed chain it appeared in.
    var lastSeen: Date
    /// Number of distinct completed chains this entity has appeared in — the
    /// "in N chains" figure. Incremented once per chain, never per submission.
    var timesLogged: Int

    /// Matches `ChainNode.id` ("p{id}" people, "m{id}" movies) so the store keys
    /// line up exactly with the game's no-repeat ids.
    var id: String { kind == .actor ? "p\(tmdbID)" : "m\(tmdbID)" }

    /// Title with year for movies (`Fargo (1996)`), plain name for actors —
    /// mirrors `ChainNode.displayName`.
    var displayName: String {
        if kind == .movie, let year { return "\(name) (\(year))" }
        return name
    }

    init(from node: ChainNode, at now: Date) {
        switch node {
        case .actor(let p):
            kind = .actor; tmdbID = p.id; name = p.name; year = nil; imagePath = p.imagePath
        case .movie(let m):
            kind = .movie; tmdbID = m.id; name = m.title; year = m.year; imagePath = m.imagePath
        }
        firstSeen = now
        lastSeen = now
        timesLogged = 1
    }
}

// MARK: - CollectionStore

/// On-disk shape: the entity list plus the aggregate counters. File-scoped (not
/// nested in the `@MainActor` store) so its `Codable` conformance stays
/// nonisolated and can be encoded on the background save task.
nonisolated private struct CollectionSnapshot: Codable, Sendable {
    var entities: [CollectedEntity]
    var chainsLogged: Int
}

@MainActor
@Observable
final class CollectionStore {

    /// The registry, keyed by `CollectedEntity.id`.
    private(set) var entities: [String: CollectedEntity]

    /// Count of completed chains logged (length ≥ 2) — the "chains" stat.
    private(set) var chainsLogged: Int

    /// Ids first discovered during this app session — drives the "New" badge in
    /// the grid. In-memory only; resets on launch.
    private(set) var newThisSession: Set<String> = []

    @ObservationIgnored private let fileURL: URL?
    /// Injectable clock so "added this week" and timestamps are testable.
    @ObservationIgnored private let clock: () -> Date

    init(fileURL: URL? = CollectionStore.defaultFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.clock = now
        let snapshot = CollectionStore.load(from: fileURL)
        self.entities = Dictionary(snapshot.entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.chainsLogged = snapshot.chainsLogged
    }

    // MARK: Recording

    /// Log a finished chain into the collection. Every node is upserted once, so
    /// `timesLogged` counts distinct chains (a chain never repeats an id). The
    /// caller (`GameEngine.endGame`) only invokes this for chains of length ≥ 2;
    /// the guard here is belt-and-suspenders. Returns the number of brand-new
    /// entities added — the "+N to your Reel" figure.
    @discardableResult
    func record(chain: [ChainNode]) -> Int {
        guard chain.count >= 2 else { return 0 }
        let now = clock()
        var added = 0
        for node in chain where upsert(node, at: now) { added += 1 }
        chainsLogged += 1
        save()
        return added
    }

    /// Insert or bump one node. Returns `true` if it was brand new.
    private func upsert(_ node: ChainNode, at now: Date) -> Bool {
        let key = node.id
        if var existing = entities[key] {
            existing.timesLogged += 1
            existing.lastSeen = now
            // Fill in art / name if a later encounter carried richer metadata.
            if existing.imagePath == nil { existing.imagePath = node.imagePath }
            entities[key] = existing
            return false
        } else {
            entities[key] = CollectedEntity(from: node, at: now)
            newThisSession.insert(key)
            return true
        }
    }

    // MARK: Rollups (read by the view)

    var actorCount: Int { entities.values.lazy.filter { $0.kind == .actor }.count }
    var movieCount: Int { entities.values.lazy.filter { $0.kind == .movie }.count }
    var total: Int { entities.count }
    var isEmpty: Bool { entities.isEmpty }

    /// Most-logged first, then most-recent — the grid and "regulars" ordering.
    var sortedActors: [CollectedEntity] { sorted(.actor) }
    var sortedMovies: [CollectedEntity] { sorted(.movie) }

    var mostLoggedActor: CollectedEntity? { sortedActors.first }
    var mostLoggedMovie: CollectedEntity? { sortedMovies.first }

    /// Entities first discovered within the last 7 days — the "this week" stat.
    var addedThisWeek: Int {
        let cutoff = clock().addingTimeInterval(-7 * 24 * 60 * 60)
        return entities.values.lazy.filter { $0.firstSeen >= cutoff }.count
    }

    func isNew(_ entity: CollectedEntity) -> Bool { newThisSession.contains(entity.id) }

    /// Spoiler-free stats card for sharing — no chains, just the tallies.
    var shareText: String {
        "My Movie Chain reel 🎬\n\(actorCount) actors · \(movieCount) movies logged"
    }

    private func sorted(_ kind: NodeKind) -> [CollectedEntity] {
        entities.values
            .filter { $0.kind == kind }
            .sorted { ($0.timesLogged, $0.lastSeen) > ($1.timesLogged, $1.lastSeen) }
    }

    // MARK: Persistence

    nonisolated static var defaultFileURL: URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true) else { return nil }
        return dir.appendingPathComponent("collection.json")
    }

    nonisolated private static func load(from url: URL?) -> CollectionSnapshot {
        guard let url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CollectionSnapshot.self, from: data)
        else { return CollectionSnapshot(entities: [], chainsLogged: 0) }
        return decoded
    }

    /// Serial queue for disk writes — the crux of persistence correctness.
    /// `save()` is only ever called from the main actor, so its calls are already
    /// ordered by mutation; a **serial** queue preserves that order (FIFO), which
    /// means the newest snapshot is always the *last* write to land. An older
    /// in-flight write can therefore never clobber a newer one — the data-loss
    /// race an unordered `Task.detached`-per-save was exposed to (a stale
    /// snapshot finishing after a fresh one and overwriting `collection.json`).
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "abe.movie-quiz.collection-save", qos: .utility)

    /// Persist off the main actor — a game-over write of a few KB should never
    /// hitch the celebration. Encodes a value snapshot on the queue, so it's
    /// race-free and ordered.
    private func save() {
        guard let fileURL else { return }
        let snapshot = CollectionSnapshot(entities: Array(entities.values), chainsLogged: chainsLogged)
        saveQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Block until every queued write has flushed. Call from the app-lifecycle
    /// hook before suspension so the latest snapshot is guaranteed on disk even
    /// if the process is killed while backgrounded (the async saves alone give no
    /// such guarantee). Cheap: the file is a few KB and the queue is usually empty
    /// or a single write deep. FIFO ensures this barrier runs after all pending
    /// writes complete.
    func flush() {
        guard fileURL != nil else { return }
        saveQueue.sync {}
    }
}
