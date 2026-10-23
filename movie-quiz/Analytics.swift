//
//  Analytics.swift
//  movie-quiz
//
//  Product analytics: what players do, as a small, closed set of named events.
//  Logging says what broke; this says where runs end, whether the sentence home
//  teaches the rule, and who comes back (see 0.7.0 in docs/ROADMAP.md).
//
//  The rules it keeps:
//  - Events are fired from the view/app layer, never `GameEngine` — the same split
//    as haptics and sound, so the engine stays pure.
//  - `Analytics` is injected through `\.analytics`, defaulting to `NoAnalytics`, so
//    tests and previews never send anything. Only the app root installs PostHog.
//  - Measurement only: no autocapture, screen views, session replay, surveys or
//    feature flags. Remote config belongs to the service (0.8.0), not PostHog.
//  - The player can turn it off in Settings (`analyticsEnabled`).
//

import Foundation
import PostHog
import SwiftUI

/// Everything the app can send. A closed set, so the whole event vocabulary is
/// readable in one place and a new event is a deliberate addition.
enum AnalyticsEvent: Equatable {
    /// A run began, from the dealt start or one the player searched for.
    case runStarted(seed: NodeKind, source: StartSource)
    /// A correct answer landed; `link` is the chain's new link count.
    case linkLanded(link: Int, kind: NodeKind, fast: Bool)
    case runEnded(reason: EndReason, links: Int, points: Int, newBest: Bool, reelAdditions: Int)
    /// A turn's candidates couldn't load and the Retry button replaced the dock.
    case turnLoadFailed(links: Int)
    case dealAgain
    case pickYourOwnOpened
    case playAgain
    case reelOpened(from: Screen)
    case shareTapped(from: Screen)

    enum StartSource: String { case dealt, picked }
    enum EndReason: String { case timeout, quit }
    enum Screen: String { case home, gameOver = "game_over", reel }

    var name: String {
        switch self {
        case .runStarted: "run_started"
        case .linkLanded: "link_landed"
        case .runEnded: "run_ended"
        case .turnLoadFailed: "turn_load_failed"
        case .dealAgain: "deal_again"
        case .pickYourOwnOpened: "pick_your_own_opened"
        case .playAgain: "play_again"
        case .reelOpened: "reel_opened"
        case .shareTapped: "share_tapped"
        }
    }

    /// Counts and categories only — never a name or title the player typed.
    var properties: [String: AnyHashable] {
        switch self {
        case let .runStarted(seed, source):
            ["seed_kind": seed.rawValue, "source": source.rawValue]
        case let .linkLanded(link, kind, fast):
            ["link": link, "kind": kind.rawValue, "fast": fast]
        case let .runEnded(reason, links, points, newBest, reelAdditions):
            ["reason": reason.rawValue, "links": links, "points": points,
             "new_best": newBest, "reel_additions": reelAdditions]
        case let .turnLoadFailed(links):
            ["links": links]
        case let .reelOpened(from), let .shareTapped(from):
            ["from": from.rawValue]
        case .dealAgain, .pickYourOwnOpened, .playAgain:
            [:]
        }
    }
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

struct PostHogAnalytics: Analytics {
    /// Starts the SDK and returns the analytics to inject — `NoAnalytics` when
    /// there's no project token (a fresh clone) or the process is a test host or
    /// a preview, so neither ever reports as a player.
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

extension EnvironmentValues {
    @Entry var analytics: any Analytics = NoAnalytics()
}
