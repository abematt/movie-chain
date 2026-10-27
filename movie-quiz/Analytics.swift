//
//  Analytics.swift
//  movie-quiz
//
//  The analytics *sink*: where events go, and nothing about what they mean.
//  `Telemetry` (Telemetry.swift and its per-area extensions) builds every event;
//  this file is the only one that may import PostHog (swift-check enforces it).
//
//  The tracking plan — every event, every property, the rules, and the checklist
//  for adding analytics to a new feature — is docs/ANALYTICS.md. Read it first.
//

import Foundation
import PostHog

/// Every event the app can send. A new event is a deliberate addition: add the
/// case, document it in docs/ANALYTICS.md (a test keeps the two in step), and
/// check the volume budget there first — a property on an existing event is
/// usually the better answer.
enum EventName: String, CaseIterable {
    case runStarted = "run_started"
    case linkLanded = "link_landed"
    case runEnded = "run_ended"
    case turnLoadFailed = "turn_load_failed"
    case dealFailed = "deal_failed"
    case shareTapped = "share_tapped"
    case cardViewed = "card_viewed"
    case reelClosed = "reel_closed"
    case challengeOpened = "challenge_opened"
}

nonisolated struct AnalyticsEvent: Equatable {
    let name: String
    let properties: [String: AnyHashable]
}

protocol Analytics: Sendable {
    func capture(_ event: AnalyticsEvent)
    /// The Settings opt-out. Off means nothing is sent, including lifecycle events.
    func setEnabled(_ enabled: Bool)
    /// Ties this device's events to an account from here on (0.9.0).
    func identify(_ accountID: String)
    /// Back to the anonymous device id, on sign-out.
    func reset()
}

/// The default everywhere but the app root: tests and previews send nothing.
struct NoAnalytics: Analytics {
    func capture(_ event: AnalyticsEvent) {}
    func setEnabled(_ enabled: Bool) {}
    func identify(_ accountID: String) {}
    func reset() {}
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
        // events agree on who the player was before signing in. `reset()` comes
        // back to the same id, since this hook supplies it again.
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

    func identify(_ accountID: String) { PostHogSDK.shared.identify(accountID) }

    func reset() { PostHogSDK.shared.reset() }
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
