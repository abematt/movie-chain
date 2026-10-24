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

    /// What the bar is drawing. Follows `clamped` with a direction-aware animation
    /// (see `onChange`), so it can't simply be an implicit animation on `clamped`.
    @State private var shown: Double = 1

    var body: some View {
        GeometryReader { geo in
            // The spec's progress bar: 6pt, muted track, full radius, no border
            // and no shadow.
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Color.socket)
                // Full width, slid left out of the track rather than resized: an
                // offset moves pixels already drawn, where an animated width
                // redrew the capsule every frame of the whole turn. The track's
                // clip rounds the fill's leading edge, so it looks the same.
                Capsule()
                    .fill(lowTime ? Theme.Color.danger : Theme.Color.ink)
                    .offset(x: -(1 - shown) * geo.size.width)
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .animation(Theme.Motion.standard, value: lowTime)
        .onAppear { shown = clamped }
        .onChange(of: clamped) { old, new in
            // The engine ticks once a second. Draining linearly over the whole
            // second makes consecutive ticks join into one continuous drain (it
            // trails the clock by under a second); a new turn's refill is a quick
            // snap rather than a slow slide backwards.
            withAnimation(new < old ? .linear(duration: 1) : Theme.Motion.standard) {
                shown = new
            }
        }
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
