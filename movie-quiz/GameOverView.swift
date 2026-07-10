//
//  GameOverView.swift
//  movie-quiz
//
//  End-of-run summary: final score and the full chain, with a play-again.
//

import SwiftUI

struct GameOverView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Time's up")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("\(engine.score)")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text(engine.score == 1 ? "link" : "links")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            List {
                Section("Your chain") {
                    ForEach(Array(engine.chain.enumerated()), id: \.element.id) { index, node in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 24, alignment: .trailing)
                            Image(systemName: {
                                if case .actor = node { return "person.fill" } else { return "film" }
                            }())
                            .foregroundStyle(.secondary)
                            Text(node.displayName)
                        }
                    }
                }
            }
            .listStyle(.inset)

            Button {
                engine.reset()
            } label: {
                Label("Play again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}
