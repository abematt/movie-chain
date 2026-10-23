//
//  movie_quizApp.swift
//  movie-quiz
//
//  Created by Abraham Mathew on 7/9/26.
//

import SwiftUI

@main
struct movie_quizApp: App {
    /// Product analytics, started once here and injected below (see `Analytics.swift`).
    @State private var telemetry: Telemetry

    init() {
        _telemetry = State(initialValue: Telemetry(sink: Self.analytics))
    }

    /// The SDK starts exactly once, however often SwiftUI builds this struct
    /// (a `static let` is initialised once, on first use).
    private static let analytics: any Analytics = {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Telemetry.enabledKey) as? Bool ?? true
        return PostHogAnalytics.start(enabled: enabled, defaults: defaults)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.telemetry, telemetry)
                // App-wide tint: interactive controls (the text cursor, the
                // keyboard's Go key) inherit this one accent — near-black ink,
                // defined in Assets → AccentColor for light/dark.
                .tint(Color.accentColor)
                // No app-wide font design: the puzzle-page look pairs the system
                // serif (wordmark, game-over number) with the default sans for
                // all UI. Views opt into serif with `.system(design: .serif)`.
        }
    }
}
