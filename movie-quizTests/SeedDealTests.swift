//
//  SeedDealTests.swift
//  movie-quizTests
//
//  Locks the home-screen deal policy: actor/movie bias, avoidance of
//  recently-dealt starts (with a full-pool fallback so a tiny pool never deals
//  nothing), and the other-kind fallback when a chosen pool is empty.
//

import XCTest
@testable import movie_quiz

final class SeedDealTests: XCTestCase {

    private func actors(_ ids: [Int]) -> [Person] { ids.map { Person(id: $0, name: "Actor \($0)") } }
    private func movies(_ ids: [Int]) -> [Movie] { ids.map { Movie(id: $0, title: "Movie \($0)", year: 2000) } }

    func testEmptyPoolsReturnNil() {
        var g = SystemRandomNumberGenerator()
        XCTAssertNil(SeedDeal.pick(actors: [], movies: [], recentIds: [], actorBias: 0.6, using: &g))
    }

    func testBiasOneAlwaysDealsActor() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let node = SeedDeal.pick(actors: actors([1, 2, 3]), movies: movies([10, 11]),
                                     recentIds: [], actorBias: 1.0, using: &g)
            guard case .actor = node else { return XCTFail("bias 1.0 must deal an actor") }
        }
    }

    func testBiasZeroAlwaysDealsMovie() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let node = SeedDeal.pick(actors: actors([1, 2, 3]), movies: movies([10, 11]),
                                     recentIds: [], actorBias: 0.0, using: &g)
            guard case .movie = node else { return XCTFail("bias 0.0 must deal a movie") }
        }
    }

    func testAvoidsRecentlyDealtIds() {
        var g = SystemRandomNumberGenerator()
        let recent: Set<String> = ["p1", "p2"]      // actors 1 & 2 are recent
        for _ in 0..<50 {
            let node = SeedDeal.pick(actors: actors([1, 2, 3]), movies: [],
                                     recentIds: recent, actorBias: 1.0, using: &g)
            XCTAssertEqual(node?.id, "p3", "must deal the only start not dealt recently")
        }
    }

    func testFallsBackToFullPoolWhenEveryCandidateIsRecent() {
        var g = SystemRandomNumberGenerator()
        // The only actor is "recent"; rather than deal nothing, fall back to it.
        let node = SeedDeal.pick(actors: actors([1]), movies: [],
                                 recentIds: ["p1"], actorBias: 1.0, using: &g)
        XCTAssertEqual(node?.id, "p1")
    }

    func testFallsBackToOtherKindWhenChosenPoolEmpty() {
        var g = SystemRandomNumberGenerator()
        // Wants an actor (bias 1.0) but there are none — deal a movie instead.
        let node = SeedDeal.pick(actors: [], movies: movies([10, 11]),
                                 recentIds: [], actorBias: 1.0, using: &g)
        guard case .movie = node else { return XCTFail("expected a movie fallback") }
    }
}
