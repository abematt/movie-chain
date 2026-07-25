//
//  ChoicesTests.swift
//  movie-quizTests
//
//  Locks the Assisted-mode option policy (`Choices.build`): the correct answer is
//  always offered when the turn has one, distractors are never secretly valid,
//  used ids are never re-offered, and a thin pool degrades gracefully.
//

import XCTest
@testable import movie_quiz

final class ChoicesTests: XCTestCase {

    private func movieNodes(_ ids: [Int]) -> [ChainNode] {
        ids.map { .movie(Movie(id: $0, title: "Movie \($0)", year: 2000)) }
    }

    /// The correct option (a candidate) is always present, and the set is exactly
    /// `count` when the pool can supply enough distractors.
    func testCorrectIncludedAndSizedToCount() {
        var g = SystemRandomNumberGenerator()
        let candidates = movieNodes([100, 101])
        let pool = movieNodes([10, 11, 12, 13, 14])
        for _ in 0..<50 {
            let opts = Choices.build(correctFrom: candidates, distractorsFrom: pool,
                                     count: 3, excluding: [], using: &g)
            XCTAssertEqual(opts.count, 3)
            XCTAssertTrue(opts.contains { candidates.map(\.id).contains($0.id) },
                          "the one correct answer must always be offered")
        }
    }

    /// No option other than the correct one is a valid answer — a "wrong" option is
    /// never secretly right, even when a candidate also appears in the pool.
    func testDistractorsAreNeverValidAnswers() {
        var g = SystemRandomNumberGenerator()
        // Movie 100 is both a valid answer *and* in the pool — it must only ever
        // appear as the correct pick, never as a distractor.
        let candidates = movieNodes([100, 101])
        let pool = movieNodes([100, 10, 11, 12])
        let candidateIds = Set(candidates.map(\.id))
        for _ in 0..<50 {
            let opts = Choices.build(correctFrom: candidates, distractorsFrom: pool,
                                     count: 3, excluding: [], using: &g)
            let valid = opts.filter { candidateIds.contains($0.id) }
            XCTAssertEqual(valid.count, 1, "exactly one option may be a valid answer")
        }
    }

    /// Used ids are never re-offered — neither as the correct pick nor a distractor.
    func testExcludesUsedIds() {
        var g = SystemRandomNumberGenerator()
        let candidates = movieNodes([100, 101])
        let pool = movieNodes([10, 11, 12])
        let used: Set<String> = ["m100", "m10"]   // one candidate, one distractor
        for _ in 0..<50 {
            let opts = Choices.build(correctFrom: candidates, distractorsFrom: pool,
                                     count: 3, excluding: used, using: &g)
            XCTAssertFalse(opts.contains { used.contains($0.id) })
            // The only remaining valid answer is m101, so it must be the correct one.
            XCTAssertTrue(opts.contains { $0.id == "m101" })
        }
    }

    /// No unused valid answer → nothing to build a turn around → empty.
    func testEmptyWhenNoUnusedCorrect() {
        var g = SystemRandomNumberGenerator()
        let candidates = movieNodes([100])
        let opts = Choices.build(correctFrom: candidates, distractorsFrom: movieNodes([10, 11]),
                                 count: 3, excluding: ["m100"], using: &g)
        XCTAssertTrue(opts.isEmpty)
    }

    // MARK: The familiarity gate (keeps an assisted chain out of unfamiliar regions)

    private func film(_ id: Int, votes: Int?) -> ChainNode {
        .movie(Movie(id: id, title: "Movie \(id)", year: 2000, voteCount: votes))
    }

    /// A movie turn may only step to a widely-seen film. This is the fix for the
    /// drift bug: a filmography that is almost entirely regional cinema must not
    /// hand the player one of those titles just because it tops that local set.
    func testMovieGateOffersOnlyWidelySeenFilms() {
        var g = SystemRandomNumberGenerator()
        // One globally-seen film buried in a filmography of regional-only titles.
        let candidates = [film(1, votes: 120), film(2, votes: 300),
                          film(3, votes: 9_000), film(4, votes: 80)]
        let pool = movieNodes(Array(100...110))
        for _ in 0..<60 {
            let opts = Choices.build(correctFrom: candidates, distractorsFrom: pool,
                                     count: 3, excluding: [],
                                     gate: .minVoteCount(4_000), using: &g)
            let correct = opts.first { (1...4).map { "m\($0)" }.contains($0.id) }
            XCTAssertEqual(correct?.id, "m3", "only the widely-seen film may be the answer")
        }
    }

    /// An actor turn may only step to a *lead* of the current film — the film already
    /// cleared the gate, so its top-billed cast are recognizable by construction.
    func testActorGateOffersOnlyTopBilled() {
        var g = SystemRandomNumberGenerator()
        // Billing order: p1…p10. Only the first three are leads.
        let candidates = (1...10).map { ChainNode.actor(Person(id: $0, name: "Actor \($0)")) }
        let pool = (100...110).map { ChainNode.actor(Person(id: $0, name: "Pool \($0)")) }
        for _ in 0..<60 {
            let opts = Choices.build(correctFrom: candidates, distractorsFrom: pool,
                                     count: 3, excluding: [],
                                     gate: .topBilled(3), using: &g)
            let correct = opts.first { (1...10).map { "p\($0)" }.contains($0.id) }
            XCTAssertNotNil(correct)
            XCTAssertTrue(["p1", "p2", "p3"].contains(correct!.id),
                          "only top-billed leads may be the answer, got \(correct!.id)")
        }
    }

    /// A dead end (nothing clears the gate) relaxes rather than stalling the turn —
    /// better a less-familiar option than nothing to tap.
    func testGateRelaxesRatherThanStalling() {
        var g = SystemRandomNumberGenerator()
        let candidates = [film(1, votes: 50), film(2, votes: 90)]   // none clear the floor
        let opts = Choices.build(correctFrom: candidates, distractorsFrom: movieNodes([100, 101]),
                                 count: 3, excluding: [],
                                 gate: .minVoteCount(4_000), using: &g)
        XCTAssertFalse(opts.isEmpty, "a gated-out turn must still be playable")
        XCTAssertTrue(opts.contains { ["m1", "m2"].contains($0.id) })
    }

    /// The gate never resurrects a used id (it filters *within* the unused set).
    func testGateStillExcludesUsedIds() {
        var g = SystemRandomNumberGenerator()
        // m3 clears the floor but is already in the chain; m5 is the only other one.
        let candidates = [film(3, votes: 9_000), film(5, votes: 8_000), film(4, votes: 10)]
        for _ in 0..<40 {
            let opts = Choices.build(correctFrom: candidates, distractorsFrom: movieNodes([100, 101]),
                                     count: 3, excluding: ["m3"],
                                     gate: .minVoteCount(4_000), using: &g)
            XCTAssertFalse(opts.contains { $0.id == "m3" })
            let correct = opts.first { ["m4", "m5"].contains($0.id) }
            XCTAssertEqual(correct?.id, "m5")
        }
    }

    /// A pool too thin to fill `count` still returns the correct answer plus
    /// whatever distractors exist — never a padded or duplicated set.
    func testThinPoolDegradesGracefully() {
        var g = SystemRandomNumberGenerator()
        let candidates = movieNodes([100, 101])
        let opts = Choices.build(correctFrom: candidates, distractorsFrom: movieNodes([10]),
                                 count: 3, excluding: [], using: &g)
        XCTAssertEqual(opts.count, 2, "1 correct + the single available distractor")
        XCTAssertEqual(Set(opts.map(\.id)).count, opts.count, "no duplicate options")
        XCTAssertTrue(opts.contains { candidates.map(\.id).contains($0.id) })
    }
}
