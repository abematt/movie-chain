//
//  ScoringTests.swift
//  movie-quizTests
//
//  Locks the point math and flame-tier thresholds so tuning the game balance
//  can't silently break the scoring contract the UI relies on.
//

import XCTest
@testable import movie_quiz

final class ScoringTests: XCTestCase {

    // MARK: The record rule (most links, points break ties)

    func testMoreLinksIsARecordEvenWithFewerPoints() {
        XCTAssertTrue(Scoring.isNewRecord(links: 19, points: 100, bestLinks: 18, bestPoints: 848))
    }

    func testMorePointsAloneIsNotARecord() {
        XCTAssertFalse(Scoring.isNewRecord(links: 17, points: 2000, bestLinks: 18, bestPoints: 848))
    }

    func testPointsBreakATieOnLinks() {
        XCTAssertTrue(Scoring.isNewRecord(links: 18, points: 900, bestLinks: 18, bestPoints: 848))
        XCTAssertFalse(Scoring.isNewRecord(links: 18, points: 848, bestLinks: 18, bestPoints: 848))
    }

    func testAZeroLinkRunIsNeverARecord() {
        XCTAssertFalse(Scoring.isNewRecord(links: 0, points: 0, bestLinks: 0, bestPoints: 0))
    }

    // MARK: Passing the record (the in-play "a new best" cue)

    func testPassesRecordFiresOnlyOnTheLinkThatPassesIt() {
        XCTAssertFalse(Scoring.passesRecord(score: 5, previousBest: 5))   // tying isn't passing
        XCTAssertTrue(Scoring.passesRecord(score: 6, previousBest: 5))    // this link passes it
        XCTAssertFalse(Scoring.passesRecord(score: 7, previousBest: 5))   // once, not every link after
    }

    func testPassesRecordNeverFiresOnAFirstGame() {
        XCTAssertFalse(Scoring.passesRecord(score: 1, previousBest: 0))
    }

    // MARK: Speed bonus

    func testSpeedBonusIsSecondsRemaining() {
        XCTAssertEqual(Scoring.speedBonus(secondsRemaining: 27), 27)
        XCTAssertEqual(Scoring.speedBonus(secondsRemaining: 0), 0)
    }

    func testSpeedBonusNeverNegative() {
        XCTAssertEqual(Scoring.speedBonus(secondsRemaining: -5), 0)
    }

    // MARK: Obscurity bonus

    func testObscurityBonusRewardsDeepCuts() {
        let obscure = Scoring.obscurityBonus(popularity: 1)
        let aLister = Scoring.obscurityBonus(popularity: 100)
        XCTAssertGreaterThan(obscure, aLister,
                             "A low-popularity pick must be worth more than an A-lister")
    }

    func testObscurityBonusZeroWhenUnknown() {
        XCTAssertEqual(Scoring.obscurityBonus(popularity: nil), 0)
        XCTAssertEqual(Scoring.obscurityBonus(popularity: 0), 0)
    }

    func testObscurityBonusClamped() {
        XCTAssertLessThanOrEqual(Scoring.obscurityBonus(popularity: 0.001), 30)
    }

    // MARK: Total gain

    func testGainCombinesBaseSpeedAndObscurity() {
        // Unknown popularity → base + speed only.
        XCTAssertEqual(Scoring.gain(secondsRemaining: 20, popularity: nil),
                       Scoring.base + 20)
        // Known popularity adds the obscurity bonus on top.
        let withObscurity = Scoring.gain(secondsRemaining: 20, popularity: 2)
        XCTAssertEqual(withObscurity,
                       Scoring.base + 20 + Scoring.obscurityBonus(popularity: 2))
    }

    // MARK: Fast flourish

    func testIsFast() {
        XCTAssertTrue(Scoring.isFast(secondsRemaining: 25, secondsPerTurn: 30))
        XCTAssertFalse(Scoring.isFast(secondsRemaining: 10, secondsPerTurn: 30))
    }

    // MARK: Flame tiers

    func testFlameTierThresholds() {
        XCTAssertEqual(Scoring.flameTier(links: 0), 0)
        XCTAssertEqual(Scoring.flameTier(links: 2), 0)
        XCTAssertEqual(Scoring.flameTier(links: 3), 1)
        XCTAssertEqual(Scoring.flameTier(links: 4), 1)
        XCTAssertEqual(Scoring.flameTier(links: 5), 2)
        XCTAssertEqual(Scoring.flameTier(links: 7), 2)
        XCTAssertEqual(Scoring.flameTier(links: 8), 3)
        XCTAssertEqual(Scoring.flameTier(links: 11), 3)
        XCTAssertEqual(Scoring.flameTier(links: 12), 4)
        XCTAssertEqual(Scoring.flameTier(links: 99), 4)
    }
}
