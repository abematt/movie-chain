//
//  GameOverView.swift
//  movie-quiz
//
//  End-of-run summary: final score, a "new best" celebration, the near-miss that
//  ended the run, the full chain, and a play-again.
//

import SwiftUI

struct GameOverView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        ZStack {
            VStack(spacing: Theme.Spacing.lg) {
                scoreHeader

                if let missed = engine.missedAnswer {
                    oneAway(missed)
                }

                chainList

                Button {
                    engine.reset()
                } label: {
                    Label("Play again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.primary)
                .padding(.horizontal)
            }
            .padding(.vertical)

            if engine.isNewBest {
                ConfettiView()
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if engine.isNewBest { Haptics.celebrate() }
        }
    }

    // MARK: Score header

    private var scoreHeader: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if engine.isNewBest {
                Text("🏆 NEW BEST!")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(.orange)
                    .transition(.scale)
            } else {
                Text(engine.endedByQuit ? "Chain ended" : "Time's up")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text("\(engine.score)")
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(engine.score == 1 ? "link · \(engine.points) pts" : "links · \(engine.points) pts")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.Spacing.md) {
                Label("Best \(engine.bestChain)", systemImage: "trophy.fill")
                Label("\(engine.bestPoints) pts", systemImage: "star.fill")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: One-away near-miss

    private func oneAway(_ node: ChainNode) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("You were one away")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: node.symbol)
                    .foregroundStyle(node.accent)
                Text(node.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            Text(node.kind == .actor ? "was in the cast" : "was in the filmography")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .card()
        .padding(.horizontal)
    }

    // MARK: Chain recap

    private var chainList: some View {
        List {
            Section("Your chain") {
                ForEach(Array(engine.chain.enumerated()), id: \.element.id) { index, node in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)
                        Image(systemName: node.symbol)
                            .foregroundStyle(node.accent)
                        Text(node.displayName)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

#Preview {
    let engine = GameEngine()
    engine.loadDemoGameOver()
    return GameOverView(engine: engine)
}
