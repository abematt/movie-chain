//
//  HandoffStageTests.swift
//  movie-quizTests
//
//  Locks the home → play handoff's bookkeeping: which frames a flight starts
//  from, that a second tap can't restart it, and when its destinations count as
//  laid out. See `HandoffStage`.
//

import CoreGraphics
import Testing
@testable import movie_quiz

@MainActor
struct HandoffStageTests {

    private let onScreen = ChainNode.actor(Person(id: 1, name: "On Screen"))
    private let dealtOut = ChainNode.actor(Person(id: 2, name: "Dealt Out"))

    private let artRect = CGRect(x: 24, y: 300, width: 40, height: 40)
    private let blankRect = CGRect(x: 24, y: 500, width: 345, height: 59)

    @Test func beginFliesTheStartOnScreenAndTheBlank() throws {
        let stage = HandoffStage()
        stage.reportHome(.art, artRect, for: onScreen.id)
        // The previous start, still reporting as it deals out.
        stage.reportHome(.art, CGRect(x: -400, y: 280, width: 40, height: 40), for: dealtOut.id)
        stage.reportHome(.blank, blankRect)

        stage.begin(with: onScreen)

        let flight = try #require(stage.flight)
        #expect(flight.node == onScreen)
        #expect(flight.from[.art] == artRect, "the dealt-out start's frames are ignored")
        #expect(flight.from[.blank] == blankRect, "the blank belongs to every start")
    }

    @Test func aSecondBeginDoesNotRestartTheFlight() throws {
        let stage = HandoffStage()
        stage.reportHome(.art, artRect, for: onScreen.id)
        stage.reportHome(.blank, blankRect)

        stage.begin(with: onScreen)
        stage.begin(with: onScreen)        // a double tap on the blank

        let flight = try #require(stage.flight)
        #expect(flight.from[.art] == artRect, "the first flight keeps its frames")
        #expect(flight.from[.blank] == blankRect)
    }

    @Test func finishLandsTheFlight() {
        let stage = HandoffStage()
        stage.begin(with: onScreen)
        stage.finish()
        #expect(!stage.isFlying)
    }

    // MARK: Destinations

    nonisolated private static let destinations: [HandoffPart] = [.card, .chip, .art, .name, .dock]

    private func stage(reporting parts: [HandoffPart], sized size: CGSize = CGSize(width: 40, height: 20)) -> HandoffStage {
        let stage = HandoffStage()
        stage.begin(with: onScreen)
        for part in parts { stage.reportPlay(part, CGRect(origin: .zero, size: size)) }
        return stage
    }

    @Test func readyOnceEveryDestinationIsLaidOut() {
        #expect(stage(reporting: Self.destinations).destinationReady)
    }

    @Test(arguments: destinations)
    func notReadyWhileADestinationIsMissing(_ missing: HandoffPart) {
        let stage = stage(reporting: Self.destinations.filter { $0 != missing })
        #expect(!stage.destinationReady)
    }

    @Test(arguments: destinations)
    func notReadyWhileADestinationIsZeroSized(_ empty: HandoffPart) {
        let stage = stage(reporting: Self.destinations.filter { $0 != empty })
        stage.reportPlay(empty, CGRect(x: 10, y: 10, width: 0, height: 20))
        #expect(!stage.destinationReady)
    }
}
