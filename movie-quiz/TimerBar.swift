//
//  TimerBar.swift
//  movie-quiz
//
//  The per-turn countdown as a slim linear bar — the restrained, puzzle-page
//  answer to a bezel-heavy ring. It drains left-to-right in ink, and only in the
//  final stretch shifts to a warning red so the pressure reads without shouting.
//  (Urgency red is a semantic signal, deliberately separate from the two
//  category accents.)
//

import SwiftUI

struct TimerBar: View {
    /// Remaining fraction of the turn, 1 → 0.
    let fraction: Double

    private var clamped: Double { max(0, min(1, fraction)) }
    private var lowTime: Bool { clamped <= 0.25 }

    var body: some View {
        GeometryReader { geo in
            // The spec's progress bar: 6pt, muted track, full radius, no border
            // and no shadow.
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Color.hairline)
                Capsule()
                    .fill(lowTime ? Theme.Color.danger : Theme.Color.ink)
                    .frame(width: clamped * geo.size.width)
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.25), value: clamped)
        .animation(Theme.Motion.standard, value: lowTime)
    }
}

#Preview("Timer bar") {
    VStack(spacing: 24) {
        TimerBar(fraction: 0.9)
        TimerBar(fraction: 0.5)
        TimerBar(fraction: 0.15)
    }
    .padding()
    .background(Theme.Color.canvas)
}
