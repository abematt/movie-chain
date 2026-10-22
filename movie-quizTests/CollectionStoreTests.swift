//
//  CollectionStoreTests.swift
//  movie-quizTests
//
//  Locks the "Your Reel" logging rule: a chain is logged only when a real
//  combination landed (length ≥ 2), the seed counts once that happens, every
//  entity is deduped by TMDB id, and `timesLogged` counts distinct chains — not
//  submissions or links.
//

import Foundation
import Testing
@testable import movie_quiz

struct CollectionStoreTests {

    /// In-memory store (no disk) with a fixed clock unless overridden.
    private func makeStore(now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }) -> CollectionStore {
        CollectionStore(fileURL: nil, now: now)
    }

    private func actor(_ id: Int, _ name: String = "Actor") -> ChainNode {
        .actor(Person(id: id, name: name))
    }
    private func movie(_ id: Int, _ title: String = "Movie") -> ChainNode {
        .movie(Movie(id: id, title: title, year: 1999))
    }

    // MARK: The core rule

    @Test func chainOfTwoLogsEveryNodeOnce() {
        let store = makeStore()
        let added = store.record(chain: [actor(1), movie(10)])

        #expect(added == 2, "Both brand-new nodes count as additions")
        #expect(store.total == 2)
        #expect(store.actorCount == 1)
        #expect(store.movieCount == 1)
        #expect(store.chainsLogged == 1)
        #expect(store.entities["p1"]?.timesLogged == 1)
        #expect(store.entities["m10"]?.timesLogged == 1)
    }

    @Test func seedOnlyChainLogsNothing() {
        // A seed the player quit on before any link landed: length 1 → not a
        // successful combination, so nothing is logged.
        let store = makeStore()
        let added = store.record(chain: [actor(1)])

        #expect(added == 0)
        #expect(store.total == 0)
        #expect(store.chainsLogged == 0)
        #expect(store.isEmpty)
    }

    @Test func seedIsLoggedOnceALinkLands() {
        // The seed (chain[0]) is included exactly when a link exists off it.
        let store = makeStore()
        store.record(chain: [actor(1, "Seed"), movie(10)])
        #expect(store.entities["p1"] != nil, "Seed is logged once a link lands off it")
    }

    // MARK: Dedup / times-logged semantics

    @Test func repeatAcrossGamesIncrementsTimesLoggedNotLinkCount() {
        let store = makeStore()
        // Two separate games that both used actor 1.
        store.record(chain: [actor(1), movie(10)])
        store.record(chain: [actor(1), movie(20)])

        #expect(store.entities["p1"]?.timesLogged == 2, "Counted once per chain, twice total")
        #expect(store.total == 3, "actor 1 + two distinct movies")
        #expect(store.actorCount == 1)
        #expect(store.movieCount == 2)
        #expect(store.chainsLogged == 2)
    }

    @Test func noDoubleCountWithinASingleChain() {
        // usedIds prevents repeats in a real chain, but even if an id recurred the
        // store must not double-count it within one record() call.
        let store = makeStore()
        store.record(chain: [actor(1), movie(10), actor(2), movie(20)])
        #expect(store.total == 4)
        for key in ["p1", "m10", "p2", "m20"] {
            #expect(store.entities[key]?.timesLogged == 1)
        }
    }

    // MARK: Rollups

    @Test func mostLoggedRollup() {
        let store = makeStore()
        store.record(chain: [actor(1, "Regular"), movie(10)])
        store.record(chain: [actor(1, "Regular"), movie(20)])
        store.record(chain: [actor(2, "One-off"), movie(30)])

        #expect(store.mostLoggedActor?.tmdbID == 1)
        #expect(store.mostLoggedActor?.timesLogged == 2)
        // Sorted most-logged first, and the one-pass rollup agrees with the sort.
        #expect(store.sortedActors.first?.tmdbID == 1)
        #expect(store.mostLoggedMovie == store.sortedMovies.first)
    }

    @Test func newThisSessionTracksFreshInsertsOnly() {
        let store = makeStore()
        store.record(chain: [actor(1), movie(10)])
        store.record(chain: [actor(1), movie(20)])  // actor 1 no longer "new"

        #expect(store.newThisSession.contains("m20"))
        #expect(store.newThisSession.contains("p1"),
                "Still new this session — it was first seen this session")
    }

    // MARK: Clock-driven stats

    @Test func addedThisWeekExcludesOlderEntries() {
        final class MutableClock { var date: Date; init(_ d: Date) { date = d } }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = CollectionStore(fileURL: nil, now: { clock.date })

        store.record(chain: [actor(1), movie(10)])
        #expect(store.addedThisWeek == 2, "Just logged — both within the week")

        clock.date = clock.date.addingTimeInterval(10 * 24 * 60 * 60) // +10 days
        #expect(store.addedThisWeek == 0, "Now older than a week")
    }

    // MARK: Persistence shape

    /// Regression: rapid successive records must persist the **newest** snapshot,
    /// never let an older in-flight write win. The serial save queue + `flush()`
    /// guarantee the on-disk file equals the final in-memory state.
    @Test func rapidRecordsPersistNewestSnapshotToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = CollectionStore(fileURL: url)
        // Fire many records back-to-back — the pattern an unordered per-save task
        // could reorder on disk, silently dropping the latest game after relaunch.
        for i in 1...12 {
            store.record(chain: [actor(i), movie(1000 + i)])
        }
        store.flush() // drain the serial write queue

        struct DiskShape: Decodable { let chainsLogged: Int; let entities: [CollectedEntity] }
        let disk = try JSONDecoder().decode(DiskShape.self, from: Data(contentsOf: url))

        #expect(disk.chainsLogged == 12, "Newest snapshot wins — all 12 chains persisted")
        #expect(disk.entities.count == store.total, "On-disk entity count matches memory")
        #expect(Set(disk.entities.map(\.id)) == Set(store.entities.keys),
                "Persisted snapshot is the latest in-memory state, not a stale one")
    }

    @Test func collectedEntityCodableRoundTrip() throws {
        let original = CollectedEntity(from: movie(42, "Fargo"),
                                       at: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CollectedEntity.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == "m42")
        #expect(decoded.displayName == "Fargo (1999)")
    }

    // MARK: Links — the actor card's number

    @Test func adjacentPairsAreLinkedBothWays() {
        let store = makeStore()
        store.record(chain: [actor(1), movie(10), actor(2), movie(20)])

        #expect(store.entities["p1"]?.links == [10])
        #expect(store.entities["m10"]?.links == [1, 2])
        #expect(store.entities["p2"]?.links == [10, 20])
        #expect(store.entities["m20"]?.links == [2])
    }

    @Test func linksAccumulateAcrossChainsWithoutDuplicates() {
        let store = makeStore()
        store.record(chain: [actor(1), movie(10)])
        store.record(chain: [actor(1), movie(20)])
        store.record(chain: [movie(10), actor(1)])  // the same pair again

        #expect(store.entities["p1"]?.links == [10, 20])
        #expect(store.entities["p1"]?.timesLogged == 3)
    }

    /// Movie 10 and actor 2 are both in the Reel, but were never linked to each
    /// other — only films linked *through* an actor count.
    @Test func onlyAdjacentPairsCount() {
        let store = makeStore()
        store.record(chain: [actor(1), movie(10)])
        store.record(chain: [actor(2), movie(20)])

        #expect(store.entities["p2"]?.links == [20])
    }

    @Test func linkedResolvesFilmsNewestFirst() throws {
        let store = makeStore()
        store.record(chain: [actor(1), .movie(Movie(id: 10, title: "Old", year: 1990)),
                             actor(2), .movie(Movie(id: 20, title: "New", year: 2020))])
        store.record(chain: [actor(1), .movie(Movie(id: 20, title: "New", year: 2020))])

        let actor1 = try #require(store.entities["p1"])
        #expect(store.linked(to: actor1).map(\.name) == ["New", "Old"])
    }

    @Test func wellKnownSnapshotIsStoredAndRefreshed() {
        let store = makeStore()
        store.record(chain: [actor(1), movie(10)], wellKnownFilms: [1: 40])
        #expect(store.entities["p1"]?.wellKnownFilms == 40)

        store.record(chain: [actor(1), movie(20)], wellKnownFilms: [1: 42])
        #expect(store.entities["p1"]?.wellKnownFilms == 42)

        // A run where their filmography didn't load keeps the last snapshot.
        store.record(chain: [actor(1), movie(30)])
        #expect(store.entities["p1"]?.wellKnownFilms == 42)
    }

    @Test func deckLeadsWithTheMostLinks() {
        let store = makeStore()
        for _ in 0..<3 { store.record(chain: [actor(1), movie(10)]) }  // logged most, one film
        store.record(chain: [actor(2), movie(20)])
        store.record(chain: [actor(2), movie(30)])                       // two films

        #expect(store.sortedActors.first?.tmdbID == 2)
    }

    /// A Reel saved before links existed must still load — a failed decode
    /// would start the player over with an empty collection.
    @Test func reelSavedBeforeLinksStillDecodes() throws {
        let legacy = """
        {"entities":[{"kind":"actor","tmdbID":1,"name":"Uma Thurman","firstSeen":0,
          "lastSeen":0,"timesLogged":3}],"chainsLogged":3}
        """
        struct DiskShape: Decodable { let chainsLogged: Int; let entities: [CollectedEntity] }
        let disk = try JSONDecoder().decode(DiskShape.self, from: Data(legacy.utf8))

        #expect(disk.entities.first?.name == "Uma Thurman")
        #expect(disk.entities.first?.links == [])
        #expect(disk.entities.first?.wellKnownFilms == nil)
    }

    @Test func linksSurviveACodableRoundTrip() throws {
        let store = makeStore()
        store.record(chain: [actor(1), movie(10), actor(2)], wellKnownFilms: [1: 12])
        let original = try #require(store.entities["p1"])

        let decoded = try JSONDecoder().decode(CollectedEntity.self,
                                               from: JSONEncoder().encode(original))
        #expect(decoded.links == [10])
        #expect(decoded.wellKnownFilms == 12)
    }
}
