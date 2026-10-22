//
//  ScoringTests.swift
//  movie-quizTests
//
//  Locks the point math and flame-tier thresholds so tuning the game balance
//  can't silently break the scoring contract the UI relies on.
//

import Testing
@testable import movie_quiz

struct ScoringTests {

    // MARK: The record rule (most links, points break ties)

    @Test func moreLinksIsARecordEvenWithFewerPoints() {
        #expect(Scoring.isNewRecord(links: 19, points: 100, bestLinks: 18, bestPoints: 848))
    }

    @Test func morePointsAloneIsNotARecord() {
        #expect(!Scoring.isNewRecord(links: 17, points: 2000, bestLinks: 18, bestPoints: 848))
    }

    @Test func pointsBreakATieOnLinks() {
        #expect(Scoring.isNewRecord(links: 18, points: 900, bestLinks: 18, bestPoints: 848))
        #expect(!Scoring.isNewRecord(links: 18, points: 848, bestLinks: 18, bestPoints: 848))
    }

    @Test func aZeroLinkRunIsNeverARecord() {
        #expect(!Scoring.isNewRecord(links: 0, points: 0, bestLinks: 0, bestPoints: 0))
    }

    // MARK: Passing the record (the in-play "a new best" cue)

    @Test func passesRecordFiresOnlyOnTheLinkThatPassesIt() {
        #expect(!Scoring.passesRecord(score: 5, previousBest: 5))   // tying isn't passing
        #expect(Scoring.passesRecord(score: 6, previousBest: 5))    // this link passes it
        #expect(!Scoring.passesRecord(score: 7, previousBest: 5))   // once, not every link after
    }

    @Test func passesRecordNeverFiresOnAFirstGame() {
        #expect(!Scoring.passesRecord(score: 1, previousBest: 0))
    }

    // MARK: Speed bonus

    @Test(arguments: [(27, 27), (0, 0), (-5, 0)])
    func speedBonusIsSecondsRemainingNeverNegative(seconds: Int, expected: Int) {
        #expect(Scoring.speedBonus(secondsRemaining: seconds) == expected)
    }

    // MARK: Obscurity bonus

    @Test func obscurityBonusRewardsDeepCuts() {
        #expect(Scoring.obscurityBonus(popularity: 1) > Scoring.obscurityBonus(popularity: 100),
                "A low-popularity pick must be worth more than an A-lister")
    }

    @Test(arguments: [nil, 0.0])
    func obscurityBonusZeroWhenUnknown(popularity: Double?) {
        #expect(Scoring.obscurityBonus(popularity: popularity) == 0)
    }

    @Test func obscurityBonusClamped() {
        #expect(Scoring.obscurityBonus(popularity: 0.001) <= 30)
    }

    // MARK: Total gain

    @Test func gainCombinesBaseSpeedAndObscurity() {
        // Unknown popularity → base + speed only.
        #expect(Scoring.gain(secondsRemaining: 20, popularity: nil) == Scoring.base + 20)
        // Known popularity adds the obscurity bonus on top.
        #expect(Scoring.gain(secondsRemaining: 20, popularity: 2)
                == Scoring.base + 20 + Scoring.obscurityBonus(popularity: 2))
    }

    // MARK: Fast flourish

    @Test func isFast() {
        #expect(Scoring.isFast(secondsRemaining: 25, secondsPerTurn: 30))
        #expect(!Scoring.isFast(secondsRemaining: 10, secondsPerTurn: 30))
    }

    // MARK: Flame tiers

    @Test(arguments: [
        (0, 0), (2, 0),
        (3, 1), (4, 1),
        (5, 2), (7, 2),
        (8, 3), (11, 3),
        (12, 4), (99, 4),
    ])
    func flameTierThresholds(links: Int, tier: Int) {
        #expect(Scoring.flameTier(links: links) == tier)
    }
}
