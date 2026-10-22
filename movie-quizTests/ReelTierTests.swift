//
//  ReelTierTests.swift
//  movie-quizTests
//
//  Locks the Reel's tier rule: a card is paper until 5 films are linked
//  through the actor, inked until 11, then holo.
//

import Testing
@testable import movie_quiz

struct ReelTierTests {

    @Test(arguments: [
        (0, ReelFinish.paper), (1, .paper), (4, .paper),
        (5, .inked), (10, .inked),
        (11, .holo), (30, .holo),
    ])
    func finish(links: Int, expected: ReelFinish) {
        #expect(ReelTier.finish(links: links) == expected)
    }

    @Test func finishesRiseInOrder() {
        #expect(ReelFinish.paper < .inked && ReelFinish.inked < .holo)
    }
}
