//
//  StreakFlame.swift
//  movie-quiz
//
//  The "you're on fire" indicator that sits with the hero chain number. It stays
//  hidden until the chain reaches 3, then grows through tiers — bigger emoji, a
//  hotter glow (orange → red → white-hot), and more flames — and pops upward on
//  every successful link so the streak literally leaps as it grows.
//

import SwiftUI

struct StreakFlame: View {
    /// Chain length; drives the tier via `Scoring.flameTier`.
    let links: Int

    private var tier: Int { Scoring.flameTier(links: links) }

    private var emoji: String {
        switch tier {
        case 4: return "🔥🔥🔥"
        case 3: return "🔥🔥"
        default: return "🔥"
        }
    }

    private var size: CGFloat {
        switch tier {
        case 1: return 30
        case 2: return 38
        case 3: return 46
        default: return 56
        }
    }

    /// Glow warms toward white as the streak climbs.
    private var glow: Color {
        switch tier {
        case 1: return .orange
        case 2: return .red
        case 3: return .pink
        default: return .white
        }
    }

    var body: some View {
        if tier > 0 {
            Text(emoji)
                .font(.system(size: size))
                .shadow(color: glow.opacity(0.9), radius: CGFloat(6 + tier * 4))
                .shadow(color: glow.opacity(0.5), radius: CGFloat(2 + tier * 2))
                // Pop up and settle each time a link is added.
                .phaseAnimator([0, 1], trigger: links) { view, phase in
                    view
                        .scaleEffect(phase == 0 ? 1 : 1.35)
                        .offset(y: phase == 0 ? 0 : -10)
                } animation: { _ in .bouncy(duration: 0.45) }
                .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview("Flame tiers") {
    HStack(spacing: 24) {
        ForEach([2, 3, 6, 9, 14], id: \.self) { n in
            VStack {
                StreakFlame(links: n)
                    .frame(height: 60)
                Text("\(n)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
