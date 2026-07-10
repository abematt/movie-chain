//
//  TimerRing.swift
//  movie-quiz
//
//  The per-turn countdown as a draining ring with the seconds in the middle.
//  Turns the timer from a bare number into visible pressure — the arc empties
//  and shifts green → orange → red as the clock runs down.
//

import SwiftUI

struct TimerRing: View {
    /// Remaining fraction of the turn, 1 → 0.
    let fraction: Double
    let seconds: Int

    private var tint: Color {
        switch fraction {
        case ..<0.34: return .red
        case ..<0.66: return .orange
        default: return .green
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(seconds)")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .animation(.snappy, value: fraction)
    }
}

#Preview("Timer ring") {
    HStack(spacing: 20) {
        TimerRing(fraction: 0.9, seconds: 27)
        TimerRing(fraction: 0.5, seconds: 15)
        TimerRing(fraction: 0.2, seconds: 6)
    }
    .frame(height: 56)
    .padding()
}
