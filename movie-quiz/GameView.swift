//
//  GameView.swift
//  movie-quiz
//
//  The play screen. The big chain number and its flame sit front-and-centre as
//  the hero, and the current node + answer field anchor the bottom. Every correct
//  link fires a haptic, a rising chime, a "+points" pop and a flame leap; a wrong
//  one shakes and buzzes.
//

import SwiftUI

struct GameView: View {
    @Bindable var engine: GameEngine

    @AppStorage("soundEnabled") private var soundEnabled = true

    @State private var answer = ""
    @FocusState private var fieldFocused: Bool
    @State private var gainToken = 0     // bumps to replay the "+N" pop
    @State private var shakeToken = 0    // bumps to shake the field on reject

    private var timeFraction: Double {
        Double(engine.secondsRemaining) / Double(Config.secondsPerTurn)
    }

    private var heatTier: Int { Scoring.flameTier(links: engine.score) }

    var body: some View {
        // No scrolling: the header is pinned to the top, the answer field is
        // pinned above the keyboard, and the hero + prompt sit centered in the
        // remaining space.
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.md)

            hero

            Spacer(minLength: Theme.Spacing.md)

            if let current = engine.current {
                prompt(for: current)
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.xs)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            answerField
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xs)
                .background(.bar)
        }
        .background(heatBackground.ignoresSafeArea())
        .task {
            // Defer the focus request a beat. On a cold launch the field isn't in
            // the responder chain yet when `onAppear`/`task` first runs, so a
            // synchronous focus set is silently dropped and the keyboard never
            // appears until the app is relaunched. One runloop hop lets the field
            // become first responder reliably.
            try? await Task.sleep(for: .milliseconds(100))
            fieldFocused = true
        }
        .onChange(of: engine.score) { old, new in
            if new > old { onCorrect() }
        }
        .onChange(of: engine.feedback) { _, new in
            if new != nil { onReject() }
        }
    }

    // MARK: Header (sound · timer · quit)

    private var header: some View {
        HStack {
            Button {
                soundEnabled.toggle()
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Spacer()

            TimerRing(fraction: timeFraction, seconds: engine.secondsRemaining)
                .frame(width: 52, height: 52)

            Spacer()

            Button("Quit") { engine.quit() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Hero (chain number + flame + points)

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            StreakFlame(links: engine.score)
                .frame(height: 44)

            Text("\(engine.score)")
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
                .overlay(alignment: .topTrailing) {
                    if gainToken > 0 {
                        FloatingGain(value: engine.lastGain)
                            .id(gainToken)
                            .offset(x: 44)
                    }
                }

            Text(engine.score == 1 ? "link · \(engine.points) pts" : "links · \(engine.points) pts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .animation(.snappy, value: engine.score)
    }

    // MARK: Current node prompt (compact — the snake already shows the node)

    private func prompt(for node: ChainNode) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                NodeGlyph(kind: node.kind, size: 32)
                Text(node.displayName)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(engine.expectedKind.prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .id(node.id)
        .transition(.push(from: .trailing))
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
            .shake(shakeToken)

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

    // MARK: Heat background

    private var heatBackground: some View {
        RadialGradient(
            colors: [Color.orange.opacity(Double(heatTier) * 0.05), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 320
        )
        .animation(.easeInOut(duration: 0.6), value: heatTier)
    }

    // MARK: Feedback reactions

    private func onCorrect() {
        Haptics.correct(streak: engine.score)
        if soundEnabled { SoundPlayer.shared.correct(streak: engine.score) }
        gainToken += 1
    }

    private func onReject() {
        Haptics.wrong()
        if soundEnabled { SoundPlayer.shared.wrong() }
        shakeToken += 1
    }

    private func submit() {
        let text = answer
        answer = ""
        fieldFocused = true
        Task { await engine.submit(text) }
    }
}

#Preview {
    let engine = GameEngine()
    engine.loadDemoChain()
    return GameView(engine: engine)
}
