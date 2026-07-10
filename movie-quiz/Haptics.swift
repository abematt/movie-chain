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

    /// A correct link. Intensity ramps with the streak so link #12 lands heavier
    /// than link #2 — the chain literally feels weightier as it grows.
    static func correct(streak: Int) {
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle =
            streak >= 8 ? .heavy : streak >= 4 ? .medium : .light
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        let intensity = min(1.0, 0.6 + Double(streak) * 0.04)
        generator.impactOccurred(intensity: intensity)
        #endif
    }

    /// A rejected / off-list answer.
    static func wrong() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }

    /// A celebratory beat — a new best chain on the game-over screen.
    static func celebrate() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}
