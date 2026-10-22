//
//  ReelTierTests.swift
//  movie-quizTests
//
//  Locks the Reel's card rules: a card is paper until 5 films are linked
//  through the actor, pastel until 11, then holo; its dots fill toward holo and
//  are only all full there; collector numbers follow the order actors were
//  first linked; and each actor keeps one duotone.
//

import Foundation
import Testing
@testable import movie_quiz

struct ReelTierTests {

    @Test(arguments: [
        (0, ReelFinish.paper), (1, .paper), (4, .paper),
        (5, .pastel), (10, .pastel),
        (11, .holo), (30, .holo),
    ])
    func finish(links: Int, expected: ReelFinish) {
        #expect(ReelTier.finish(links: links) == expected)
    }

    @Test func finishesRiseInOrder() {
        #expect(ReelFinish.paper < .pastel && ReelFinish.pastel < .holo)
    }

    @Test(arguments: [
        (0, 0), (1, 1), (2, 1), (4, 1), (5, 2), (8, 3), (10, 4), (11, 5), (40, 5),
    ])
    func dots(links: Int, filled: Int) {
        #expect(ReelTier.filledDots(links: links) == filled)
    }

    @Test func fullDotsOnlyAtHolo() {
        for links in 0..<ReelTier.holoAt {
            #expect(ReelTier.filledDots(links: links) < ReelTier.dots)
        }
    }
}

struct ReelNumberTests {

    private func actor(_ id: Int, firstSeen: TimeInterval) -> CollectedEntity {
        var e = CollectedEntity(from: .actor(Person(id: id, name: "A\(id)", imagePath: nil)),
                                at: Date(timeIntervalSince1970: firstSeen))
        e.links = [1]
        return e
    }

    @Test func numbersFollowFirstLinked() {
        let late = actor(1, firstSeen: 300), early = actor(2, firstSeen: 100), mid = actor(3, firstSeen: 200)
        let numbers = ReelNumber.numbers(for: [late, early, mid])
        #expect(numbers[early.id] == 1)
        #expect(numbers[mid.id] == 2)
        #expect(numbers[late.id] == 3)
    }

    @Test func tiesBreakByTMDBID() {
        let b = actor(20, firstSeen: 100), a = actor(10, firstSeen: 100)
        let numbers = ReelNumber.numbers(for: [b, a])
        #expect(numbers[a.id] == 1 && numbers[b.id] == 2)
    }

    @Test(arguments: [(1, "No. 001"), (27, "No. 027"), (999, "No. 999"), (1234, "No. 1234")])
    func label(number: Int, expected: String) {
        #expect(ReelNumber.label(number) == expected)
    }
}

struct DuotoneTests {

    @Test func anActorKeepsOnePair() {
        #expect(Duotone.forActor(tmdbID: 6384) == Duotone.forActor(tmdbID: 6384))
    }

    @Test func everyPairIsReachable() {
        let reached = Set((0..<Duotone.palette.count).map { Duotone.forActor(tmdbID: $0).index })
        #expect(reached.count == Duotone.palette.count)
    }

    @Test func negativeIDsStillMap() {
        #expect(Duotone.palette.indices.contains(Duotone.forActor(tmdbID: -7).index))
    }
}
