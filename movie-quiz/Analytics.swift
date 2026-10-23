//
//  Analytics.swift
//  movie-quiz
//
//  Product analytics: what players do. Logging says what broke; this says where
//  runs end, how long turns take, what people try, and how the Reel gets used
//  (see 0.7.0 in docs/ROADMAP.md).
//
//  The rules it keeps:
//  - Few events, rich properties. A screen's time rides on the event that ends
//    it, misses ride on the turn they belong to, a card's whole look is one event
//    — about 47 events a session, so the 1M/month free tier holds ~700 daily
//    players. Add a property before adding an event.
//  - `Telemetry` is the only thing views call. It keeps the context an event needs
//    (run id, when a screen or card appeared) and builds every event, so the
//    vocabulary lives in this file. Events fire from the view layer, never
//    `GameEngine` — the same split as haptics and sound.
//  - `Analytics` is the sink, injected so tests and previews never send. Only the
//    app root installs PostHog.
//  - Ids are TMDB ids. Typed text is sent (truncated) because what people try is
//    the game; the opt-out in Settings covers it, and it's declared on the privacy
//    label as Other User Content.
//  - Measurement only: no autocapture, screen views, replay, surveys or flags.
//    Remote config belongs to the service (0.8.0), not PostHog.
//

import Foundation
import PostHog
import SwiftUI

nonisolated struct AnalyticsEvent: Equatable {
    let name: String
    let properties: [String: AnyHashable]
}

protocol Analytics: Sendable {
    func capture(_ event: AnalyticsEvent)
    /// The Settings opt-out. Off means nothing is sent, including lifecycle events.
    func setEnabled(_ enabled: Bool)
}

/// The default everywhere but the app root: tests and previews send nothing.
struct NoAnalytics: Analytics {
    func capture(_ event: AnalyticsEvent) {}
    func setEnabled(_ enabled: Bool) {}
}

// MARK: - Telemetry

/// Builds and sends every event, holding the bits of context they need.
@MainActor
final class Telemetry {
    enum StartSource: String { case dealt, picked }
    enum Screen: String { case home, gameOver = "game_over", reel }

    /// Long enough for any real title or name; caps whatever else gets typed.
    static let typedLimit = 60

    private let sink: any Analytics
    private let now: () -> Date

    init(sink: any Analytics = NoAnalytics(), now: @escaping () -> Date = Date.init) {
        self.sink = sink
        self.now = now
        screenSince = now()
    }

    func setEnabled(_ enabled: Bool) { sink.setEnabled(enabled) }

    // MARK: Screens

    /// When the current home or game-over screen appeared.
    private var screenSince: Date
    private var onGameOver = false
    private var dealsSinceHome = 0
    /// Time spent on the last game-over screen, sent with the next run's start.
    private var lastGameOverSeconds: Double?

    /// Called on every phase change, from the root.
    func phaseChanged(to phase: GameEngine.Phase) {
        switch phase {
        case .seed:
            if onGameOver { lastGameOverSeconds = seconds(since: screenSince) }
            onGameOver = false
            screenSince = now()
            dealsSinceHome = 0
        case .playing:
            break
        case .gameOver(let summary):
            runEnded(summary)
            onGameOver = true
            screenSince = now()
        }
    }

    /// Back from the background: time away isn't time on the screen.
    func resumed() { screenSince = now() }

    func dealt() { dealsSinceHome += 1 }

    // MARK: Runs

    private var runID: UUID?
    private var runStartedAt: Date?

    func runStarted(seed: ChainNode, source: StartSource) {
        let id = UUID()
        runID = id
        runStartedAt = now()
        var properties: [String: AnyHashable] = [
            "run_id": id.uuidString,
            "seed_id": seed.tmdbID,
            "seed_kind": seed.kind.rawValue,
            "source": source.rawValue,
            "deals_before_start": dealsSinceHome,
            "home_s": seconds(since: screenSince),
        ]
        if let lastGameOverSeconds { properties["game_over_s"] = lastGameOverSeconds }
        lastGameOverSeconds = nil
        send("run_started", properties)
    }

    func linkLanded(_ turn: GameEngine.Turn, link: Int, fast: Bool) {
        send("link_landed", runProperties([
            "link": link,
            "prompt_id": turn.prompt.tmdbID,
            "prompt_kind": turn.prompt.kind.rawValue,
            "answer_id": turn.answer.tmdbID,
            "typed": Self.clip(turn.typed),
            "misses": turn.misses.map(Self.clip),
            "answer_ms": Self.ms(turn.answerTime),
            "load_ms": Self.ms(turn.loadTime),
            "fast": fast,
        ]))
    }

    func turnLoadFailed(links: Int) {
        send("turn_load_failed", runProperties(["links": links]))
    }

    private func runEnded(_ summary: GameEngine.Summary) {
        let answers = summary.turns.map { Self.ms($0.answerTime) }
        var properties: [String: AnyHashable] = [
            "reason": summary.endedByQuit ? "quit" : "timeout",
            "links": summary.links,
            "points": summary.points,
            "new_best": summary.isNewBest,
            "reel_additions": summary.reelAdditions,
            "play_s": Self.round(Double(Self.ms(summary.playTime)) / 1000),
            "wrong_guesses": summary.turns.reduce(summary.finalMisses.count) { $0 + $1.misses.count },
            "final_misses": summary.finalMisses.map(Self.clip),
            "retries": summary.retries,
        ]
        if let runStartedAt { properties["duration_s"] = seconds(since: runStartedAt) }
        if !answers.isEmpty {
            properties["avg_answer_ms"] = answers.reduce(0, +) / answers.count
            properties["slowest_answer_ms"] = answers.max()
        }
        if let last = summary.chain.last { properties["final_prompt_id"] = last.tmdbID }
        if let missed = summary.missedAnswer { properties["near_miss_id"] = missed.tmdbID }
        send("run_ended", runProperties(properties))
        runID = nil
        runStartedAt = nil
    }

    func shared(from screen: Screen) {
        send("share_tapped", ["from": screen.rawValue])
    }

    // MARK: Reel

    private var reelOpenedFrom: Screen?
    private var reelOpenedAt: Date?
    private var cardsViewed = 0
    private var flips = 0
    private var filtersUsed: [String] = []
    /// The card that's out of the grid right now.
    private var lifted: (entity: CollectedEntity, at: Date, flipped: Bool, dragged: Bool)?

    func reelOpened(from screen: Screen) {
        reelOpenedFrom = screen
        reelOpenedAt = now()
        cardsViewed = 0
        flips = 0
        filtersUsed = []
    }

    func cardLifted(_ entity: CollectedEntity) {
        lifted = (entity, now(), false, false)
    }

    func cardFlipped() {
        flips += 1
        lifted?.flipped = true
    }

    func cardDragged() { lifted?.dragged = true }

    func cardPutDown() {
        guard let card = lifted else { return }
        lifted = nil
        cardsViewed += 1
        var properties: [String: AnyHashable] = [
            "tmdb_id": card.entity.tmdbID,
            "kind": card.entity.kind.rawValue,
            "linked": card.entity.links.count,
            "duration_s": seconds(since: card.at),
            "flipped": card.flipped,
            "dragged": card.dragged,
        ]
        if card.entity.kind == .actor {
            properties["finish"] = ReelTier.finish(links: card.entity.links.count).label.lowercased()
        }
        send("card_viewed", properties)
    }

    /// A tab, decade or genre chosen — named like `decade:1990`, `genre:18`.
    func reelFiltered(_ filter: String) {
        if !filtersUsed.contains(filter) { filtersUsed.append(filter) }
    }

    func reelClosed() {
        cardPutDown()   // a card still out when the sheet goes counts as viewed
        guard let opened = reelOpenedAt else { return }
        send("reel_closed", [
            "from": reelOpenedFrom?.rawValue ?? "unknown",
            "duration_s": seconds(since: opened),
            "cards_viewed": cardsViewed,
            "flips": flips,
            "filters": filtersUsed,
        ])
        reelOpenedAt = nil
    }

    // MARK: Helpers

    private func send(_ name: String, _ properties: [String: AnyHashable]) {
        sink.capture(AnalyticsEvent(name: name, properties: properties))
    }

    private func runProperties(_ properties: [String: AnyHashable]) -> [String: AnyHashable] {
        guard let runID else { return properties }
        return properties.merging(["run_id": runID.uuidString]) { old, _ in old }
    }

    private func seconds(since date: Date) -> Double { Self.round(now().timeIntervalSince(date)) }

    /// One decimal place: the precision anyone reads a duration at.
    private static func round(_ seconds: Double) -> Double { (max(0, seconds) * 10).rounded() / 10 }

    private static func ms(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }

    static func clip(_ text: String) -> String { String(text.prefix(typedLimit)) }
}

extension EnvironmentValues {
    /// Set at the root; `nil` (send nothing) in previews.
    @Entry var telemetry: Telemetry? = nil
}

// MARK: - PostHog

struct PostHogAnalytics: Analytics {
    /// Starts the SDK and returns the sink to use — `NoAnalytics` when there's no
    /// project token (a fresh clone) or the process is a test host or a preview,
    /// so neither ever reports as a player.
    static func start(enabled: Bool, defaults: UserDefaults) -> any Analytics {
        let env = ProcessInfo.processInfo.environment
        let isTestHost = env["XCTestConfigurationFilePath"] != nil
        let isPreview = env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        guard Config.hasPostHogToken, !isTestHost, !isPreview else { return NoAnalytics() }

        let config = PostHogConfig(projectToken: Config.postHogToken, host: Config.postHogHost)
        // App opened / installed / updated stay on: they're the retention signal.
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.sessionReplay = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        // No swizzling: nothing that needs it (autocapture, replay, surveys,
        // push registration) is wanted.
        config.enableSwizzling = false
        config.optOut = !enabled
        // Our device id is the anonymous id, so a future account (0.9.0) and these
        // events agree on who the player was before signing in.
        let deviceID = DeviceID.current(in: defaults)
        config.getAnonymousId = { @Sendable _ in deviceID }
        PostHogSDK.shared.setup(config)

        #if DEBUG
        // Filter your own development traffic out in PostHog on this property.
        PostHogSDK.shared.register(["debug_build": true])
        #endif
        return PostHogAnalytics()
    }

    func capture(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? PostHogSDK.shared.optIn() : PostHogSDK.shared.optOut()
    }
}

/// A random identifier made on first launch and kept on this device. Owns no
/// personal data; it's what local records and analytics are stamped with until
/// an account (0.9.0) claims them. A reinstall starts a new one.
enum DeviceID {
    static let key = "deviceID"

    static func current(in defaults: UserDefaults) -> UUID {
        if let stored = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) {
            return stored
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
