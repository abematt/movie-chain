//
//  Telemetry.swift
//  movie-quiz
//
//  The one thing views call for analytics. It keeps the context events need
//  (which screen is up and since when, the run in progress, the lifted Reel card)
//  and builds every event, so what an event means lives here and not at call
//  sites. The plan it implements is docs/ANALYTICS.md.
//
//  Layout: this file is the core — the sink, the clock, shared context, screens,
//  identity. Each area of the game adds its own extension file
//  (`Telemetry+Runs.swift`, `Telemetry+Reel.swift`) with its own state struct,
//  stored here as one property. A new mode adds `Telemetry+<Mode>.swift` the same
//  way rather than growing an existing file.
//
//  `GameEngine` never calls this (swift-check enforces it): the engine records
//  plain facts (`GameEngine.Turn`, `Summary`) and views pass them in.
//

import Foundation
import SwiftUI

@MainActor
final class Telemetry {
    enum Screen: String { case home, gameOver = "game_over", reel }

    /// Which game is being played. Rides on every event, so a new mode reuses the
    /// run events instead of inventing its own.
    enum Mode: String { case endless }

    /// Facts about the player's setup, sent on every event. A setting is a
    /// property here, never an event.
    struct Context {
        var mode: Mode = .endless
        var signedIn = false
        var soundOn = true
    }

    /// Bump when an existing property changes meaning, so charts can split old
    /// data from new. Adding a property doesn't need a bump.
    static let schema = 1
    /// Long enough for any real title or name; caps whatever else gets typed.
    static let typedLimit = 60
    /// The Settings opt-out, read at launch and written by the toggle.
    static let enabledKey = "analyticsEnabled"

    private let sink: any Analytics
    /// The clock every duration is measured on. Injected so tests are exact.
    let now: () -> Date
    var context = Context()

    // Per-area state, owned here because extensions can't store properties.
    var runs = RunState()
    var reel = ReelState()

    init(sink: any Analytics = NoAnalytics(), now: @escaping () -> Date = Date.init) {
        self.sink = sink
        self.now = now
        screen = ScreenState(since: now())
    }

    func setEnabled(_ enabled: Bool) { sink.setEnabled(enabled) }

    // MARK: Identity (0.9.0)

    /// The player signed in: their events from here on belong to the account,
    /// and PostHog links the device's earlier anonymous events to it.
    func signedIn(accountID: String) {
        context.signedIn = true
        sink.identify(accountID)
    }

    func signedOut() {
        context.signedIn = false
        sink.reset()
    }

    // MARK: Screens

    struct ScreenState {
        /// When the current home or game-over screen appeared.
        var since: Date
        var onGameOver = false
        var dealsSinceHome = 0
        /// Time on the last game-over screen, sent with the next run's start.
        var lastGameOverSeconds: Double?
    }

    var screen: ScreenState

    /// Called on every phase change, from the root. Screen times start here, and
    /// every run ends here, whichever screen it ended on.
    func phaseChanged(to phase: GameEngine.Phase) {
        switch phase {
        case .seed:
            if screen.onGameOver { screen.lastGameOverSeconds = seconds(since: screen.since) }
            screen.onGameOver = false
            screen.since = now()
            screen.dealsSinceHome = 0
        case .playing:
            break
        case .gameOver(let summary):
            runEnded(summary)
            screen.onGameOver = true
            screen.since = now()
        }
    }

    /// Back from the background: time away isn't time on the screen.
    func resumed() { screen.since = now() }

    func dealt() { screen.dealsSinceHome += 1 }

    func shared(from screen: Screen) {
        send(.shareTapped, ["from": screen.rawValue])
    }

    // MARK: For the extensions

    /// Sends an event with the shared context added. Every event goes through here.
    func send(_ name: EventName, _ properties: [String: AnyHashable]) {
        let shared: [String: AnyHashable] = [
            "mode": context.mode.rawValue,
            "signed_in": context.signedIn,
            "sound_on": context.soundOn,
            "schema": Self.schema,
        ]
        sink.capture(AnalyticsEvent(name: name.rawValue,
                                    properties: properties.merging(shared) { own, _ in own }))
    }

    func seconds(since date: Date) -> Double { Self.round(now().timeIntervalSince(date)) }

    /// One decimal place: the precision anyone reads a duration at.
    static func round(_ seconds: Double) -> Double { (max(0, seconds) * 10).rounded() / 10 }

    static func ms(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    static func clip(_ text: String) -> String { String(text.prefix(typedLimit)) }
}

extension EnvironmentValues {
    /// Set at the root; `nil` (send nothing) in previews.
    @Entry var telemetry: Telemetry? = nil
}
