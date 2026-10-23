//
//  AnalyticsTests.swift
//  movie-quizTests
//
//  Locks what `Telemetry` sends. Event and property names are what dashboards
//  query, so a rename silently breaks them; durations ride on the event that ends
//  a screen, so the clock bookkeeping is the part most worth pinning down. Also
//  the device id's one promise: stable.
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct AnalyticsTests {

    @MainActor
    final class Recorder: Analytics {
        private(set) var events: [AnalyticsEvent] = []
        func capture(_ event: AnalyticsEvent) { events.append(event) }
        func setEnabled(_ enabled: Bool) {}

        func last(_ name: String) throws -> [String: AnyHashable] {
            try #require(events.last { $0.name == name }).properties
        }
    }

    final class Clock {
        var time = Date(timeIntervalSince1970: 0)
        func advance(_ seconds: Double) { time += seconds }
    }

    private let recorder = Recorder()
    private let clock = Clock()
    private lazy var telemetry = Telemetry(sink: recorder, now: { [clock] in clock.time })

    private let actor1 = ChainNode.actor(Person(id: 1, name: "Actor 1"))
    private let film100 = ChainNode.movie(Movie(id: 100, title: "Film 100", year: 2001))

    private func turn(misses: [String] = [], typed: String = "Film 100") -> GameEngine.Turn {
        GameEngine.Turn(prompt: actor1, answer: film100, typed: typed, misses: misses,
                        answerTime: .milliseconds(4200), loadTime: .milliseconds(300))
    }

    // MARK: Runs

    @Test mutating func aRunCarriesItsContextFromStartToEnd() throws {
        telemetry.dealt()
        telemetry.dealt()
        clock.advance(5)
        telemetry.runStarted(seed: actor1, source: .dealt)

        let started = try recorder.last("run_started")
        #expect(started["seed_id"] == AnyHashable(1) && started["seed_kind"] == AnyHashable("actor"))
        #expect(started["source"] == AnyHashable("dealt"))
        #expect(started["deals_before_start"] == AnyHashable(2))
        #expect(started["home_s"] == AnyHashable(5.0))
        #expect(started["game_over_s"] == nil, "the first run of a session has no game over before it")
        let runID = try #require(started["run_id"])

        clock.advance(6)
        telemetry.linkLanded(turn(misses: ["Malkovic"]), link: 1, fast: true)
        let landed = try recorder.last("link_landed")
        #expect(landed["run_id"] == runID)
        #expect(landed["prompt_id"] == AnyHashable(1) && landed["answer_id"] == AnyHashable(100))
        #expect(landed["typed"] == AnyHashable("Film 100"))
        #expect(landed["misses"] == AnyHashable(["Malkovic"]))
        #expect(landed["answer_ms"] == AnyHashable(4200) && landed["load_ms"] == AnyHashable(300))

        clock.advance(9)
        var summary = GameEngine.Summary(chain: [actor1, film100], links: 1, points: 40,
                                         turns: [turn(misses: ["Malkovic"])],
                                         finalMisses: ["Actor 9"], playTime: .seconds(34))
        summary.missedAnswer = .actor(Person(id: 7, name: "Actor 7"))
        telemetry.phaseChanged(to: .gameOver(summary))

        let ended = try recorder.last("run_ended")
        #expect(ended["run_id"] == runID)
        #expect(ended["reason"] == AnyHashable("timeout"))
        #expect(ended["duration_s"] == AnyHashable(15.0))
        #expect(ended["play_s"] == AnyHashable(34.0))
        #expect(ended["wrong_guesses"] == AnyHashable(2), "one mid-run miss plus one on the last turn")
        #expect(ended["avg_answer_ms"] == AnyHashable(4200) && ended["slowest_answer_ms"] == AnyHashable(4200))
        #expect(ended["final_prompt_id"] == AnyHashable(100))
        #expect(ended["near_miss_id"] == AnyHashable(7))
    }

    @Test mutating func gameOverTimeRidesOnTheNextRun() throws {
        telemetry.runStarted(seed: actor1, source: .dealt)
        telemetry.phaseChanged(to: .gameOver(GameEngine.Summary(chain: [actor1])))
        clock.advance(8)
        telemetry.phaseChanged(to: .seed)
        clock.advance(2)
        telemetry.runStarted(seed: film100, source: .picked)

        let started = try recorder.last("run_started")
        #expect(started["game_over_s"] == AnyHashable(8.0))
        #expect(started["home_s"] == AnyHashable(2.0))
        #expect(started["source"] == AnyHashable("picked"))
    }

    @Test mutating func timeInTheBackgroundIsNotTimeOnScreen() throws {
        clock.advance(600)
        telemetry.resumed()
        clock.advance(3)
        telemetry.runStarted(seed: actor1, source: .dealt)
        #expect(try recorder.last("run_started")["home_s"] == AnyHashable(3.0))
    }

    @Test mutating func typedTextIsClipped() throws {
        telemetry.runStarted(seed: actor1, source: .dealt)
        telemetry.linkLanded(turn(misses: [String(repeating: "y", count: 200)],
                                  typed: String(repeating: "x", count: 200)),
                             link: 1, fast: false)
        let landed = try recorder.last("link_landed")
        #expect(landed["typed"] == AnyHashable(String(repeating: "x", count: Telemetry.typedLimit)))
        #expect(landed["misses"] == AnyHashable([String(repeating: "y", count: Telemetry.typedLimit)]))
    }

    // MARK: Reel

    private func actorCard(links: Int) -> CollectedEntity {
        var entity = CollectedEntity(from: actor1, at: clock.time)
        entity.links = Set(1...links)
        return entity
    }

    @Test mutating func aReelVisitIsOneEventPerCardAndOneForTheVisit() throws {
        telemetry.reelOpened(from: .home)
        clock.advance(1)
        telemetry.cardLifted(actorCard(links: 6))
        telemetry.cardFlipped()
        telemetry.cardDragged()
        clock.advance(3)
        telemetry.cardPutDown()
        telemetry.reelFiltered("decade:1990")
        telemetry.reelFiltered("decade:1990")
        clock.advance(6)
        telemetry.reelClosed()

        let card = try recorder.last("card_viewed")
        #expect(card["tmdb_id"] == AnyHashable(1) && card["kind"] == AnyHashable("actor"))
        #expect(card["linked"] == AnyHashable(6) && card["finish"] == AnyHashable("pastel"))
        #expect(card["duration_s"] == AnyHashable(3.0))
        #expect(card["flipped"] == AnyHashable(true) && card["dragged"] == AnyHashable(true))

        let visit = try recorder.last("reel_closed")
        #expect(visit["from"] == AnyHashable("home"))
        #expect(visit["duration_s"] == AnyHashable(10.0))
        #expect(visit["cards_viewed"] == AnyHashable(1) && visit["flips"] == AnyHashable(1))
        #expect(visit["filters"] == AnyHashable(["decade:1990"]))
        #expect(recorder.events.map(\.name) == ["card_viewed", "reel_closed"])
    }

    @Test mutating func aCardStillOutWhenTheReelClosesIsCounted() throws {
        telemetry.reelOpened(from: .gameOver)
        telemetry.cardLifted(actorCard(links: 1))
        clock.advance(2)
        telemetry.reelClosed()

        #expect(try recorder.last("card_viewed")["duration_s"] == AnyHashable(2.0))
        #expect(try recorder.last("reel_closed")["cards_viewed"] == AnyHashable(1))
    }

    // MARK: Device id

    @Test func deviceIDIsMadeOnceAndKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "AnalyticsTests-\(UUID())"))
        let first = DeviceID.current(in: defaults)
        #expect(DeviceID.current(in: defaults) == first)
    }

    @Test func deviceIDReplacesAnUnreadableValue() throws {
        let defaults = try #require(UserDefaults(suiteName: "AnalyticsTests-\(UUID())"))
        defaults.set("not-a-uuid", forKey: DeviceID.key)
        let id = DeviceID.current(in: defaults)
        #expect(defaults.string(forKey: DeviceID.key) == id.uuidString)
    }
}
