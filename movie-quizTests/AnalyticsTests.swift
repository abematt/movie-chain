//
//  AnalyticsTests.swift
//  movie-quizTests
//
//  Locks the analytics vocabulary: event names are what dashboards query, so a
//  rename silently breaks them, and properties must stay counts and categories —
//  never a name the player typed. Also the device id's one promise: stable.
//

import Foundation
import Testing
@testable import movie_quiz

struct AnalyticsTests {

    @Test(arguments: [
        (AnalyticsEvent.runStarted(seed: .actor, source: .dealt), "run_started"),
        (.linkLanded(link: 3, kind: .movie, fast: true), "link_landed"),
        (.runEnded(reason: .timeout, links: 4, points: 90, newBest: false, reelAdditions: 2), "run_ended"),
        (.turnLoadFailed(links: 2), "turn_load_failed"),
        (.dealAgain, "deal_again"),
        (.pickYourOwnOpened, "pick_your_own_opened"),
        (.playAgain, "play_again"),
        (.reelOpened(from: .home), "reel_opened"),
        (.shareTapped(from: .gameOver), "share_tapped"),
    ])
    func eventNamesAreStable(event: AnalyticsEvent, name: String) {
        #expect(event.name == name)
    }

    @Test func runEndedCarriesTheOutcome() {
        let event = AnalyticsEvent.runEnded(reason: .quit, links: 7, points: 140,
                                            newBest: true, reelAdditions: 3)
        #expect(event.properties == ["reason": "quit", "links": 7, "points": 140,
                                     "new_best": true, "reel_additions": 3])
    }

    @Test func screensUseSnakeCase() {
        #expect(AnalyticsEvent.reelOpened(from: .gameOver).properties == ["from": "game_over"])
    }

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
