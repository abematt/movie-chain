//
//  FuzzyMatchTests.swift
//  movie-quizTests
//
//  Locks the spelling-tolerant matcher, especially the Roman→Arabic sequel fix:
//  players type "mission impossible 3" but TMDB titles it "Mission: Impossible
//  III", and raw edit distance used to prefer "…II" (2 edits) over "…III" (3).
//

import Testing
@testable import movie_quiz

struct FuzzyMatchTests {

    private static let missionImpossible = [
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

    // NOTE: "mission impossible 1" is deliberately not covered. The first film
    // carries no numeral ("Mission: Impossible"), so a typed "1" has no exact
    // target and currently lands on the nearest numbered sequel. That
    // franchise-first-installment ambiguity is a separate, unbuilt heuristic.
    @Test(arguments: [
        ("mission impossible 3", "Mission: Impossible III"),
        ("mission impossible 2", "Mission: Impossible II"),
        ("mission impossible iii", "Mission: Impossible III"),   // Roman input too
        ("mission imposible 3", "Mission: Impossible III"),      // and misspelled
    ])
    func sequelMatchesRomanTitle(input: String, expected: String) {
        #expect(match(input, in: Self.missionImpossible) == expected)
    }

    @Test(arguments: [
        ("Mission: Impossible III", "mission impossible 3"),
        ("Rocky IV", "rocky 4"),
        // "iiii" / "vv" are not canonical Roman numerals — leave them untouched.
        ("iiii", "iiii"),
        ("vv", "vv"),
    ])
    func normalizeFoldsOnlyCanonicalRomanNumerals(input: String, expected: String) {
        #expect(FuzzyMatch.normalize(input) == expected)
    }

    // MARK: Single letters that are NOT sequels must still match themselves

    @Test(arguments: [
        ("malcolm x", "Malcolm X"),
        ("x men", "X-Men"),
        ("i am legend", "I Am Legend"),
        ("oceans eleven", "Ocean's Eleven"),
        ("top gun maverick", "Top Gun: Maverick"),
    ])
    func nonSequelSingleLettersStillMatch(input: String, expected: String) {
        let titles = ["Malcolm X", "X-Men", "I Am Legend", "Ocean's Eleven", "Top Gun: Maverick"]
        #expect(match(input, in: titles) == expected)
    }

    // MARK: Rejection

    @Test func rejectsOffListAnswer() {
        #expect(match("the godfather", in: Self.missionImpossible) == nil)
    }

    // MARK: Subset ties prefer the closest title (the "Making of" bug)

    @Test func prefersClosestTitleOnSubsetTie() {
        // Both titles contain every typed word, so both hit the same whole-word
        // boost floor. The winner must be the closer literal match, regardless of
        // candidate order — not the "making of" featurette just because TMDB
        // happens to list it first.
        let candidates = ["Making of School of Rock", "The School of Rock"]
        #expect(match("school of rock", in: candidates) == "The School of Rock")
        #expect(match("school of rock", in: candidates.reversed()) == "The School of Rock")
    }
}
