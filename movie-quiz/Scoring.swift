//
//  Scoring.swift
//  movie-quiz
//
//  Pure, stateless scoring rules. Kept separate from `GameEngine` so the point
//  math and flame-tier thresholds are unit-testable without any game state, a
//  network, or the clock — the same reason `FuzzyMatch` and `ActorRanking` are
//  their own pure types.
//
//  The headline metric is still the **chain length** (one point of "streak" per
//  accepted link, which drives the flame). `points` is a richer secondary score
//  layered on top: every link banks a base amount plus a speed bonus (answer
//  fast, score more) and an obscurity bonus (a deep-cut pick beats naming the
//  obvious A-lister). This rewards both decisiveness and real film knowledge.
//

import Foundation

enum Scoring {

    /// Flat points every accepted link is worth, before bonuses.
    static let base = 10

    /// Speed bonus: one point per whole second left on the clock when the answer
    /// landed. Answer instantly and bank the full turn; dither and bank little.
    static func speedBonus(secondsRemaining: Int) -> Int {
        max(0, secondsRemaining)
    }

    /// Obscurity bonus: lower TMDB popularity → more points. A-listers sit at
    /// popularity ~40–120; deep cuts are in the low single digits. The curve is
    /// smooth and clamped so the reward tapers rather than spiking. `nil`
    /// popularity (e.g. the offline stub graph) earns nothing extra.
    static func obscurityBonus(popularity: Double?) -> Int {
        guard let popularity, popularity > 0 else { return 0 }
        let raw = 30.0 / (1.0 + popularity / 8.0)
        return min(30, max(0, Int(raw.rounded())))
    }

    /// Total points awarded for one accepted link.
    static func gain(secondsRemaining: Int, popularity: Double?) -> Int {
        base
            + speedBonus(secondsRemaining: secondsRemaining)
            + obscurityBonus(popularity: popularity)
    }

    /// Whether an answer counts as "fast" — used only to trigger extra flourish
    /// (a stronger haptic / label), not the score itself.
    static func isFast(secondsRemaining: Int, secondsPerTurn: Int) -> Bool {
        guard secondsPerTurn > 0 else { return false }
        return Double(secondsRemaining) >= Double(secondsPerTurn) * 0.66
    }

    /// Flame tier for a given chain length. 0 = no flame; higher tiers burn
    /// bigger and hotter. The chain only starts to "catch fire" at 3.
    ///   0: 0–2   1: 3–4   2: 5–7   3: 8–11   4: 12+
    static func flameTier(links: Int) -> Int {
        switch links {
        case ..<3:  return 0
        case 3...4: return 1
        case 5...7: return 2
        case 8...11: return 3
        default:    return 4
        }
    }
}
