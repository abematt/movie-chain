//
//  Haptics.swift
//  movie-quiz
//
//  Thin wrapper over UIKit feedback generators so the game can make each correct
//  link *feel* satisfying. Deliberately fired from the view layer (in reaction to
//  engine state changes), never from `GameEngine` itself — that keeps the engine
//  free of UIKit and unit-testable.
//
//  Guarded to iOS: macOS and visionOS don't offer the same taptic feedback, so
//  every call is a no-op there rather than a build error.
//

import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
enum Haptics {

    // Long-lived, pre-warmed generators. Apple's fluid-interface bar: feedback
    // must land on the *same frame* as its cause, and `prepare()` only buys that
    // when it runs *ahead* of the event — warming the taptic engine so the impact
    // fires with zero latency. Recreating a generator per hit (and preparing it
    // inline, one line before firing) defeats the purpose, so we hold them and
    // re-warm after each use.
    #if os(iOS)
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static let notifyGen = UINotificationFeedbackGenerator()
    #endif

    /// Warm the taptic engine ahead of the first hit of a turn, so it lands in
    /// sync with the chime and the tile drop instead of arriving late.
    static func prepare() {
        #if os(iOS)
        lightGen.prepare()
        mediumGen.prepare()
        heavyGen.prepare()
        notifyGen.prepare()
        #endif
    }

    /// A correct link. Intensity ramps with the streak so link #12 lands heavier
    /// than link #2 — the chain literally feels weightier as it grows.
    static func correct(streak: Int) {
        #if os(iOS)
        let generator = streak >= 8 ? heavyGen : streak >= 4 ? mediumGen : lightGen
        let intensity = min(1.0, 0.6 + Double(streak) * 0.04)
        generator.impactOccurred(intensity: intensity)
        generator.prepare()   // re-warm for the next link
        #endif
    }

    /// A rejected / off-list answer.
    static func wrong() {
        #if os(iOS)
        notifyGen.notificationOccurred(.error)
        notifyGen.prepare()   // re-warm for the next event
        #endif
    }

    /// A celebratory beat — a new best chain on the game-over screen.
    static func celebrate() {
        #if os(iOS)
        notifyGen.notificationOccurred(.success)
        #endif
    }
}
