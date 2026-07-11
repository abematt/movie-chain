//
//  GameView.swift
//  movie-quiz
//
//  The play screen, designed around the one constant of a typing game: the
//  software keyboard is up the entire time. So the layout is three bands —
//  compact chrome (sound · timer · score) at the top, the chain building as a
//  rising Tetris-style stack of category tiles in the middle, and the answer
//  input docked directly above the keyboard. Every correct link drops a new tile
//  in with a haptic and a chime; a wrong one shakes and buzzes.
//

import SwiftUI

struct GameView: View {
    @Bindable var engine: GameEngine

    @AppStorage("soundEnabled") private var soundEnabled = true

    @State private var answer = ""
    @FocusState private var fieldFocused: Bool
    @State private var gainToken = 0     // bumps to replay the "+N" pop
    @State private var shakeToken = 0    // bumps to shake the field on reject

    /// How many links stay visible in the rising window before older ones
    /// collapse into "+N earlier". Tuned to the band above the keyboard.
    private let visibleLinks = 5

    private var timeFraction: Double {
        Double(engine.secondsRemaining) / Double(Config.secondsPerTurn)
    }

    private var lowTime: Bool { timeFraction <= 0.25 }

    private var canSubmit: Bool {
        !answer.trimmingCharacters(in: .whitespaces).isEmpty && !engine.isChecking
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            header
            TimerBar(fraction: timeFraction)
            scoreHero

            // The stack renders at its *natural* height, pinned to the bottom of
            // this flexible region; any overflow (the oldest links) is clipped off
            // the top — the "rising" effect. Without `fixedSize`, a full stack
            // would instead be compressed to fit, which shrinks the tile text.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    ChainStack(chain: engine.chain, maxVisible: visibleLinks)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .clipped()

            nextHint
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { answerDock }
        .task {
            // Warm the feedback paths before the first link so the haptic, chime,
            // and tile drop land on the same frame instead of the first hit lagging
            // on a cold taptic/audio engine (Apple fluid-interface: kill latency).
            Haptics.prepare()
            if soundEnabled { SoundPlayer.shared.warm() }

            // Defer the focus request a beat. On a cold launch the field isn't in
            // the responder chain yet when `task` first runs, so a synchronous
            // focus set is silently dropped and the keyboard never appears until
            // relaunch. One runloop hop lets the field become first responder.
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

    // MARK: Header (sound · seconds · quit)

    private var header: some View {
        HStack {
            Button {
                soundEnabled.toggle()
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(String(format: "0:%02d", max(0, engine.secondsRemaining)))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(lowTime ? Color.red : .secondary)
                .contentTransition(.numericText())

            Spacer()

            Button("Quit") { engine.quit() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
    }

    // MARK: Score hero (the emphasized chain number + points)

    private var scoreHero: some View {
        VStack(spacing: 2) {
            Text("\(engine.score)")
                .font(.system(size: 60, weight: .bold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Theme.Color.ink)
                .overlay(alignment: .trailing) {
                    if gainToken > 0 {
                        FloatingGain(value: engine.lastGain)
                            .id(gainToken)
                            .offset(x: 30)
                    }
                }

            Text("\(engine.points) pts")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
        .animation(.snappy, value: engine.score)
    }

    // MARK: Next-up hint

    private var nextHint: some View {
        HStack(spacing: Theme.Spacing.sm) {
            NodeDot(kind: engine.expectedKind)
            Text(hintText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xs)
    }

    private var hintText: String {
        guard let current = engine.current else { return engine.expectedKind.prompt }
        switch engine.expectedKind {
        case .actor: return "Name an actor from \(current.matchText)"
        case .movie: return "Name a movie \(current.matchText) was in"
        }
    }

    // MARK: Answer dock (pinned above the keyboard)

    private var answerDock: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let feedback = engine.feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack(spacing: Theme.Spacing.sm) {
                TextField(engine.expectedKind.placeholder, text: $answer)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm + 4)
                    .background(Theme.Color.tile, in: Capsule())

                Button(action: submit) {
                    Text("Go")
                        .font(.headline)
                        .foregroundStyle(Theme.Color.onInk)
                        .padding(.horizontal, Theme.Spacing.md + 2)
                        .padding(.vertical, Theme.Spacing.sm + 4)
                        .background(Theme.Color.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.4)
            }
            .shake(shakeToken)
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
        .background(Theme.Color.canvas)
        .animation(.snappy, value: engine.feedback)
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
