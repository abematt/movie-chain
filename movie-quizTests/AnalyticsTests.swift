//
//  AnalyticsTests.swift
//  movie-quizTests
//
//  Locks what `Telemetry` sends. Event and property names are what dashboards
//  query, so a rename silently breaks them; durations ride on the event that ends
//  a screen, so the clock bookkeeping is the part most worth pinning down. Also
//  keeps docs/ANALYTICS.md honest, and the device id's one promise: stable.
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct AnalyticsTests {

    @MainActor
    final class Recorder: Analytics {
        private(set) var events: [AnalyticsEvent] = []
        private(set) var account: String?
        func capture(_ event: AnalyticsEvent) { events.append(event) }
        func setEnabled(_ enabled: Bool) {}
        func identify(_ accountID: String) { account = accountID }
        func reset() { account = nil }

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

    // MARK: Shared context and identity

    // MARK: Challenges

    @Test mutating func aChallengeRunCarriesTheScoreToBeatAndTheOutcome() throws {
        let challenge = SharedChain(start: .init(kind: .actor, id: 1, name: "Actor 1"), links: [100, 2],
                                    points: 90, sharer: UUID(), senderName: "Sam")
        telemetry.runStarted(seed: actor1, source: .challenge, challenge: challenge)
        let started = try recorder.last("run_started")
        #expect(started["source"] == AnyHashable("challenge"))
        #expect(started["rival_links"] == AnyHashable(2) && started["rival_points"] == AnyHashable(90))

        telemetry.runEnded(GameEngine.Summary(chain: [actor1, film100], links: 1, points: 30,
                                              challenge: challenge))
        #expect(try recorder.last("run_ended")["challenge_outcome"] == AnyHashable("loss"))
    }

    @Test mutating func anOpenedLinkSaysWhatItWas() throws {
        let challenge = SharedChain(start: .init(kind: .actor, id: 1, name: "Actor 1"), links: [100],
                                    points: 40, sharer: UUID())
        telemetry.challengeOpened(.challenge(challenge))
        let opened = try recorder.last("challenge_opened")
        #expect(opened["result"] == AnyHashable("new") && opened["rival_links"] == AnyHashable(1))

        let match = Match(id: "s|x", direction: .sent, startKind: .actor, startID: 1, startName: "Actor 1",
                          theirs: RunScore(links: 1, points: 1), mine: RunScore(links: 2, points: 1),
                          date: clock.time)
        telemetry.challengeOpened(.reply(match, Rival(id: UUID(), name: "Sam", matches: [match])))
        let reply = try recorder.last("challenge_opened")
        #expect(reply["result"] == AnyHashable("reply") && reply["outcome"] == AnyHashable("win"))
        #expect(reply["rival_matches"] == AnyHashable(1))

        telemetry.challengeOpened(.own)
        #expect(try recorder.last("challenge_opened")["result"] == AnyHashable("own"))
    }

    @Test mutating func aShareSaysWhatLinkItCarried() throws {
        telemetry.shared(from: .gameOver, link: .reply)
        #expect(try recorder.last("share_tapped")["link"] == AnyHashable("reply"))
        telemetry.shared(from: .reel)
        #expect(try recorder.last("share_tapped")["link"] == AnyHashable("none"))
    }

    @Test mutating func everyEventCarriesTheSharedContext() throws {
        telemetry.context.soundOn = false
        telemetry.shared(from: .reel)
        let shared = try recorder.last("share_tapped")
        #expect(shared["mode"] == AnyHashable("endless"))
        #expect(shared["signed_in"] == AnyHashable(false))
        #expect(shared["sound_on"] == AnyHashable(false))
        #expect(shared["schema"] == AnyHashable(Telemetry.schema))
        #expect(shared["from"] == AnyHashable("reel"), "an event's own properties survive the merge")
    }

    @Test mutating func signingInTiesEventsToTheAccountUntilSignOut() throws {
        telemetry.signedIn(accountID: "acct-1")
        #expect(recorder.account == "acct-1")
        telemetry.shared(from: .reel)
        #expect(try recorder.last("share_tapped")["signed_in"] == AnyHashable(true))

        telemetry.signedOut()
        #expect(recorder.account == nil)
        telemetry.shared(from: .reel)
        #expect(try recorder.last("share_tapped")["signed_in"] == AnyHashable(false))
    }

    // MARK: The tracking plan

    /// docs/ANALYTICS.md documents each event under a `### `name`` heading; it
    /// must list exactly the events the code can send.
    @Test func theTrackingPlanDocumentsEveryEvent() throws {
        let plan = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/ANALYTICS.md")
        let text = try String(contentsOf: plan, encoding: .utf8)
        let documented = Set(text.matches(of: /^### `(\w+)`/.anchorsMatchLineEndings())
            .map { String($0.1) })
        #expect(documented == Set(EventName.allCases.map(\.rawValue)))
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
