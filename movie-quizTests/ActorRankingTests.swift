//
//  ActorRankingTests.swift
//  movie-quizTests
//
//  Locks the seed-search ranking: canonical record first, obvious stubs
//  dropped, but distinct ids for same-name people (homonyms) always preserved
//  — identity is the TMDB id, never the name.
//

import XCTest
@testable import movie_quiz

final class ActorRankingTests: XCTestCase {

    // The real "Tom Cruise" query shape: canonical (id 500) + a near-empty
    // stub sharing the exact name + two unrelated low-popularity people.
    private let tomCruiseResults = [
        ActorSearchCandidate(id: 6092083, name: "Tom Cruise", department: "Acting", popularity: 0.0, knownForCount: 1),
        ActorSearchCandidate(id: 500, name: "Tom Cruise", department: "Acting", popularity: 8.41, knownForCount: 3),
        ActorSearchCandidate(id: 3921757, name: "João Augusto Abreu", department: "Acting", popularity: 0.04, knownForCount: 3),
    ]

    func testCanonicalRecordLeads() {
        let ranked = ActorRanking.rank(tomCruiseResults)
        XCTAssertEqual(ranked.first?.id, 500, "Most-popular record must be first")
    }

    func testSameNameStubIsPreservedNotDropped() {
        // The stub has a known_for entry, so it is real-enough to keep — it must
        // still be selectable, just ranked below the canonical record. Dropping
        // it by name would also drop legitimate homonyms.
        let ranked = ActorRanking.rank(tomCruiseResults)
        XCTAssertTrue(ranked.contains { $0.id == 6092083 })
        XCTAssertEqual(ranked.map(\.id), [500, 3921757, 6092083])
    }

    func testHomonymsAllPreservedAndOrderedByPopularity() {
        // Two genuinely different people with the same name — BOTH must survive.
        let evans = [
            ActorSearchCandidate(id: 16828, name: "Chris Evans", department: "Acting", popularity: 5.09, knownForCount: 3),
            ActorSearchCandidate(id: 1212362, name: "Chris Evans", department: "Acting", popularity: 1.07, knownForCount: 3),
        ]
        let ranked = ActorRanking.rank(evans)
        XCTAssertEqual(ranked.map(\.id), [16828, 1212362])
    }

    func testProvablyEmptyStubIsDropped() {
        // No popularity AND no known work → not demonstrably a real person.
        let results = [
            ActorSearchCandidate(id: 1, name: "Real Actor", department: "Acting", popularity: 2.0, knownForCount: 2),
            ActorSearchCandidate(id: 2, name: "Empty Stub", department: "Acting", popularity: 0.0, knownForCount: 0),
        ]
        let ranked = ActorRanking.rank(results)
        XCTAssertEqual(ranked.map(\.id), [1])
    }

    func testNonActingDepartmentFilteredOut() {
        let results = [
            ActorSearchCandidate(id: 1, name: "Some Director", department: "Directing", popularity: 9.0, knownForCount: 3),
            ActorSearchCandidate(id: 2, name: "Some Actor", department: "Acting", popularity: 1.0, knownForCount: 1),
        ]
        let ranked = ActorRanking.rank(results)
        XCTAssertEqual(ranked.map(\.id), [2])
    }
}
