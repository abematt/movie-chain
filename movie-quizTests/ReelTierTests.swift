//
//  ReelTierTests.swift
//  movie-quizTests
//
//  Locks the Reel's tier rules: Rank's card ranks and fixed thresholds, Share's
//  per-actor thresholds and their clamps, and Plain having no tiers at all.
//

import Testing
@testable import movie_quiz

struct ReelTierTests {

    // MARK: Rank

    @Test(arguments: [
        (0, "·"), (1, "A"), (2, "2"), (10, "10"), (11, "J"), (12, "Q"), (13, "K"), (20, "K"),
    ])
    func rankCorner(links: Int, expected: String) {
        #expect(ReelTier.corner(links: links, model: .rank) == expected)
    }

    @Test(arguments: [
        (1, ReelFinish.paper), (4, .paper), (5, .inked), (10, .inked), (11, .holo), (30, .holo),
    ])
    func rankFinish(links: Int, expected: ReelFinish) {
        // Rank ignores the filmography entirely.
        #expect(ReelTier.finish(links: links, wellKnown: 3, model: .rank) == expected)
        #expect(ReelTier.finish(links: links, wellKnown: nil, model: .rank) == expected)
    }

    // MARK: Share

    /// Inked at a quarter of the well-known films (2…5), holo at half (4…10).
    @Test(arguments: [
        (52, 5, 10),   // Tom Hanks: both capped
        (14, 4, 7),    // Florence Pugh: scaled
        (20, 5, 10),   // Uma Thurman
        (3, 2, 4),     // a short filmography hits the floors
        (0, 2, 4),     // the stub graph: no vote counts at all
    ])
    func shareThresholds(wellKnown: Int, inked: Int, holo: Int) throws {
        let t = try #require(ReelTier.thresholds(wellKnown: wellKnown, model: .share))
        #expect(t.inked == inked)
        #expect(t.holo == holo)
    }

    @Test func shareFallsBackToRankBeforeAFilmographyLoads() throws {
        let t = try #require(ReelTier.thresholds(wellKnown: nil, model: .share))
        #expect(t.inked == ReelTier.rankThresholds.inked)
        #expect(t.holo == ReelTier.rankThresholds.holo)
    }

    @Test func shareCornerIsTheCount() {
        #expect(ReelTier.corner(links: 11, model: .share) == "11")
    }

    // MARK: Plain

    @Test func plainHasNoTiers() {
        #expect(ReelTier.thresholds(wellKnown: 14, model: .plain) == nil)
        #expect(ReelTier.finish(links: 50, wellKnown: 14, model: .plain) == .paper)
        #expect(ReelTier.next(links: 1, wellKnown: 14, model: .plain) == nil)
    }

    // MARK: Next tier

    @Test func nextTierWalksUpThenStops() throws {
        let fromPaper = try #require(ReelTier.next(links: 2, wellKnown: nil, model: .rank))
        #expect(fromPaper.finish == .inked && fromPaper.at == 5)

        let fromInked = try #require(ReelTier.next(links: 6, wellKnown: nil, model: .rank))
        #expect(fromInked.finish == .holo && fromInked.at == 11)

        #expect(ReelTier.next(links: 11, wellKnown: nil, model: .rank) == nil)
    }
}
