//
//  SeedDealTests.swift
//  movie-quizTests
//
//  Locks the home-screen deal policy: actor/movie bias, avoidance of
//  recently-dealt starts (with a full-pool fallback so a tiny pool never deals
//  nothing), and the other-kind fallback when a chosen pool is empty.
//

import Testing
@testable import movie_quiz

struct SeedDealTests {

    private func actors(_ ids: [Int]) -> [Person] { ids.map { Person(id: $0, name: "Actor \($0)") } }
    private func movies(_ ids: [Int]) -> [Movie] { ids.map { Movie(id: $0, title: "Movie \($0)", year: 2000) } }

    private func deal(actors: [Person], movies: [Movie], recent: Set<String> = [], bias: Double) -> ChainNode? {
        var g = SystemRandomNumberGenerator()
        return SeedDeal.pick(actors: actors, movies: movies, recentIds: recent, actorBias: bias, using: &g)
    }

    private func kind(of node: ChainNode?) -> NodeKind? {
        switch node {
        case .actor: .actor
        case .movie: .movie
        case nil: nil
        }
    }

    @Test func emptyPoolsReturnNil() {
        #expect(deal(actors: [], movies: [], bias: 0.6) == nil)
    }

    @Test(arguments: zip([1.0, 0.0], [NodeKind.actor, .movie]))
    func extremeBiasAlwaysDealsThatKind(bias: Double, kind: NodeKind) {
        for _ in 0..<50 {
            let node = deal(actors: actors([1, 2, 3]), movies: movies([10, 11]), bias: bias)
            #expect(self.kind(of: node) == kind, "bias \(bias) must deal a \(kind)")
        }
    }

    @Test func avoidsRecentlyDealtIds() {
        // Actors 1 & 2 are recent, so only actor 3 can be dealt.
        for _ in 0..<50 {
            let node = deal(actors: actors([1, 2, 3]), movies: [], recent: ["p1", "p2"], bias: 1.0)
            #expect(node?.id == "p3", "must deal the only start not dealt recently")
        }
    }

    @Test func fallsBackToFullPoolWhenEveryCandidateIsRecent() {
        // The only actor is "recent"; rather than deal nothing, fall back to it.
        #expect(deal(actors: actors([1]), movies: [], recent: ["p1"], bias: 1.0)?.id == "p1")
    }

    @Test func fallsBackToOtherKindWhenChosenPoolEmpty() {
        // Wants an actor (bias 1.0) but there are none — deal a movie instead.
        let node = deal(actors: [], movies: movies([10, 11]), bias: 1.0)
        #expect(kind(of: node) == .movie, "expected a movie fallback")
    }
}
