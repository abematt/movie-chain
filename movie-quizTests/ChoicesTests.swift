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
