//
//  CollectionStoreTests.swift
//  movie-quizTests
//
//  Locks the "Your Reel" logging rule: a chain is logged only when a real
//  combination landed (length ≥ 2), the seed counts once that happens, every
//  entity is deduped by TMDB id, and `timesLogged` counts distinct chains — not
//  submissions or links.
//

import XCTest
@testable import movie_quiz

@MainActor
final class CollectionStoreTests: XCTestCase {

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

    func testChainOfTwoLogsEveryNodeOnce() {
        let store = makeStore()
        let added = store.record(chain: [actor(1), movie(10)])

        XCTAssertEqual(added, 2, "Both brand-new nodes count as additions")
        XCTAssertEqual(store.total, 2)
        XCTAssertEqual(store.actorCount, 1)
        XCTAssertEqual(store.movieCount, 1)
        XCTAssertEqual(store.chainsLogged, 1)
        XCTAssertEqual(store.entities["p1"]?.timesLogged, 1)
        XCTAssertEqual(store.entities["m10"]?.timesLogged, 1)
    }

    func testSeedOnlyChainLogsNothing() {
        // A seed the player quit on before any link landed: length 1 → not a
        // successful combination, so nothing is logged.
        let store = makeStore()
        let added = store.record(chain: [actor(1)])

        XCTAssertEqual(added, 0)
        XCTAssertEqual(store.total, 0)
        XCTAssertEqual(store.chainsLogged, 0)
        XCTAssertTrue(store.isEmpty)
    }

    func testSeedIsLoggedOnceALinkLands() {
        // The seed (chain[0]) is included exactly when a link exists off it.
        let store = makeStore()
        store.record(chain: [actor(1, "Seed"), movie(10)])
        XCTAssertNotNil(store.entities["p1"], "Seed is logged once a link lands off it")
    }

    // MARK: Dedup / times-logged semantics

    func testRepeatAcrossGamesIncrementsTimesLoggedNotLinkCount() {
        let store = makeStore()
        // Two separate games that both used actor 1.
        store.record(chain: [actor(1), movie(10)])
        store.record(chain: [actor(1), movie(20)])

        XCTAssertEqual(store.entities["p1"]?.timesLogged, 2, "Counted once per chain, twice total")
        XCTAssertEqual(store.total, 3, "actor 1 + two distinct movies")
        XCTAssertEqual(store.actorCount, 1)
        XCTAssertEqual(store.movieCount, 2)
        XCTAssertEqual(store.chainsLogged, 2)
    }

    func testNoDoubleCountWithinASingleChain() {
        // usedIds prevents repeats in a real chain, but even if an id recurred the
        // store must not double-count it within one record() call.
        let store = makeStore()
        store.record(chain: [actor(1), movie(10), actor(2), movie(20)])
        XCTAssertEqual(store.total, 4)
        for key in ["p1", "m10", "p2", "m20"] {
            XCTAssertEqual(store.entities[key]?.timesLogged, 1)
        }
    }

    // MARK: Rollups

    func testMostLoggedRollup() {
        let store = makeStore()
        store.record(chain: [actor(1, "Regular"), movie(10)])
        store.record(chain: [actor(1, "Regular"), movie(20)])
        store.record(chain: [actor(2, "One-off"), movie(30)])

        XCTAssertEqual(store.mostLoggedActor?.tmdbID, 1)
        XCTAssertEqual(store.mostLoggedActor?.timesLogged, 2)
        // Sorted most-logged first.
        XCTAssertEqual(store.sortedActors.first?.tmdbID, 1)
    }

    func testNewThisSessionTracksFreshInsertsOnly() {
        let store = makeStore()
        store.record(chain: [actor(1), movie(10)])
        store.record(chain: [actor(1), movie(20)])  // actor 1 no longer "new"

        XCTAssertTrue(store.newThisSession.contains("m20"))
        XCTAssertTrue(store.newThisSession.contains("p1"),
                      "Still new this session — it was first seen this session")
    }

    // MARK: Clock-driven stats

    func testAddedThisWeekExcludesOlderEntries() {
        final class MutableClock { var date: Date; init(_ d: Date) { date = d } }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = CollectionStore(fileURL: nil, now: { clock.date })

        store.record(chain: [actor(1), movie(10)])
        XCTAssertEqual(store.addedThisWeek, 2, "Just logged — both within the week")

        clock.date = clock.date.addingTimeInterval(10 * 24 * 60 * 60) // +10 days
        XCTAssertEqual(store.addedThisWeek, 0, "Now older than a week")
    }

    // MARK: Persistence shape

    /// Regression: rapid successive records must persist the **newest** snapshot,
    /// never let an older in-flight write win. The serial save queue + `flush()`
    /// guarantee the on-disk file equals the final in-memory state.
    func testRapidRecordsPersistNewestSnapshotToDisk() throws {
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

        XCTAssertEqual(disk.chainsLogged, 12, "Newest snapshot wins — all 12 chains persisted")
        XCTAssertEqual(disk.entities.count, store.total, "On-disk entity count matches memory")
        XCTAssertEqual(Set(disk.entities.map(\.id)), Set(store.entities.keys),
                       "Persisted snapshot is the latest in-memory state, not a stale one")
    }

    func testCollectedEntityCodableRoundTrip() throws {
        let original = CollectedEntity(from: movie(42, "Fargo"),
                                       at: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CollectedEntity.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, "m42")
        XCTAssertEqual(decoded.displayName, "Fargo (1999)")
    }
}
