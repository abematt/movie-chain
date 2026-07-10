//
//  FuzzyMatchTests.swift
//  movie-quizTests
//
//  Locks the spelling-tolerant matcher, especially the Roman→Arabic sequel fix:
//  players type "mission impossible 3" but TMDB titles it "Mission: Impossible
//  III", and raw edit distance used to prefer "…II" (2 edits) over "…III" (3).
//

import XCTest
@testable import movie_quiz

final class FuzzyMatchTests: XCTestCase {

    private let missionImpossible = [
        "Mission: Impossible",
        "Mission: Impossible II",
        "Mission: Impossible III",
        "Mission: Impossible - Ghost Protocol",
        "Mission: Impossible - Rogue Nation",
        "Mission: Impossible - Fallout",
        "Mission: Impossible - Dead Reckoning Part One",
    ]

    private func match(_ input: String, in candidates: [String]) -> String? {
        FuzzyMatch.bestMatch(for: input, in: candidates, nameOf: { $0 })?.item
    }

    // MARK: Roman-numeral sequels (the reported bug)

    func testArabicSequelMatchesRomanTitle() {
        XCTAssertEqual(match("mission impossible 3", in: missionImpossible), "Mission: Impossible III")
        XCTAssertEqual(match("mission impossible 2", in: missionImpossible), "Mission: Impossible II")
        // NOTE: "mission impossible 1" is deliberately not asserted. The first
        // film carries no numeral ("Mission: Impossible"), so a typed "1" has no
        // exact target and currently lands on the nearest numbered sequel. That
        // franchise-first-installment ambiguity is a separate, unbuilt heuristic.
    }

    func testRomanInputAlsoMatches() {
        XCTAssertEqual(match("mission impossible iii", in: missionImpossible), "Mission: Impossible III")
    }

    func testNormalizeFoldsRomanNumerals() {
        XCTAssertEqual(FuzzyMatch.normalize("Mission: Impossible III"), "mission impossible 3")
        XCTAssertEqual(FuzzyMatch.normalize("Rocky IV"), "rocky 4")
    }

    // MARK: Single letters that are NOT sequels must still match themselves

    func testNonSequelSingleLettersStillMatch() {
        let titles = ["Malcolm X", "X-Men", "I Am Legend", "Ocean's Eleven", "Top Gun: Maverick"]
        XCTAssertEqual(match("malcolm x", in: titles), "Malcolm X")
        XCTAssertEqual(match("x men", in: titles), "X-Men")
        XCTAssertEqual(match("i am legend", in: titles), "I Am Legend")
        XCTAssertEqual(match("oceans eleven", in: titles), "Ocean's Eleven")
        XCTAssertEqual(match("top gun maverick", in: titles), "Top Gun: Maverick")
    }

    func testRoundTripRejectsMalformedRomanTokens() {
        // "iiii" / "vv" are not canonical Roman numerals — leave them untouched.
        XCTAssertEqual(FuzzyMatch.normalize("iiii"), "iiii")
        XCTAssertEqual(FuzzyMatch.normalize("vv"), "vv")
    }

    // MARK: Spelling tolerance & rejection

    func testForgivesMisspelling() {
        XCTAssertEqual(match("mission imposible 3", in: missionImpossible), "Mission: Impossible III")
    }

    func testRejectsOffListAnswer() {
        XCTAssertNil(match("the godfather", in: missionImpossible))
    }
}
