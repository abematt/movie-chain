//
//  GameView.swift
//  movie-quiz
//
//  The play screen: current node, timer, chain so far, and the free-text
//  answer field validated against the bounded candidate set.
//

import SwiftUI

struct GameView: View {
    @Bindable var engine: GameEngine

    @State private var answer = ""
    @FocusState private var fieldFocused: Bool

    private var timeFraction: Double {
        Double(engine.secondsRemaining) / Double(Config.secondsPerTurn)
    }

    var body: some View {
        VStack(spacing: 24) {
            header

            Spacer()

            if let current = engine.current {
                currentNode(current)
            }

            answerField

            Spacer()

            chainTrail
        }
        .padding()
        .onAppear { fieldFocused = true }
    }

    // MARK: Header (score + timer)

    private var header: some View {
        HStack {
            Label("\(engine.score)", systemImage: "link")
                .font(.headline)
                .monospacedDigit()

            Spacer()

            Button("Quit") { engine.reset() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .overlay {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                Text("\(engine.secondsRemaining)")
                    .monospacedDigit()
            }
            .font(.headline)
            .foregroundStyle(timeFraction < 0.34 ? .red : .primary)
            .contentTransition(.numericText())
            .animation(.snappy, value: engine.secondsRemaining)
        }
    }

    // MARK: Current node

    private func currentNode(_ node: ChainNode) -> some View {
        VStack(spacing: 8) {
            Image(systemName: {
                if case .actor = node { return "person.fill" } else { return "film" }
            }())
            .font(.largeTitle)
            .foregroundStyle(.tint)

            Text(node.displayName)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)

            Text(engine.expectedKind.prompt)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .transition(.push(from: .trailing))
        .id(node.id)
        .animation(.snappy, value: node.id)
    }

    // MARK: Answer field

    private var answerField: some View {
        VStack(spacing: 8) {
            HStack {
                TextField(engine.expectedKind.placeholder, text: $answer)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .submitLabel(.go)
                    .onSubmit(submit)

                Button(action: submit) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title)
                }
                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty || engine.isChecking)
            }

            if let feedback = engine.feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: engine.feedback)
    }

    // MARK: Chain trail

    private var chainTrail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(engine.chain.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(node.displayName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func submit() {
        let text = answer
        answer = ""
        fieldFocused = true
        Task { await engine.submit(text) }
    }
}
