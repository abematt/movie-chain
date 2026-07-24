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

    private var isAssisted: Bool { engine.difficulty.isAssisted }

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Hardcore types (docked above the keyboard); Assisted taps one of
            // three options (no keyboard).
            if isAssisted { optionsPanel } else { answerDock }
        }
        .task {
            // Assisted mode has no text field to raise — skip the keyboard focus
            // entirely (otherwise the docked options would sit above an unwanted
            // keyboard).
            guard !isAssisted else { return }
            // Feedback warm-up (haptics + audio) now happens on the seed screen,
            // OFF this transition — `AVAudioEngine.start()` briefly blocks the main
            // actor and was hitching the seed->play push. Here we only raise the
            // keyboard, and only *after* the push has settled: focusing mid-push
            // triggers keyboard-driven safe-area relayout that fights the spring.
            // ~550ms clears `Theme.Motion.screen` and also lets the field enter the
            // responder chain (a synchronous focus set on a cold launch is dropped).
            try? await Task.sleep(for: .milliseconds(550))
            // Bail if the view went away during the wait (e.g. a fast Quit) —
            // `try?` swallows the sleep's cancellation, so without this the focus
            // set would fire on whatever screen replaced us and jump the keyboard.
            guard !Task.isCancelled else { return }
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
                withAnimation(Theme.Motion.standard) { soundEnabled.toggle() }
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    // Fixed slot: the two speaker glyphs differ in width, so let the
                    // symbol swap inside a stable box rather than nudging the header.
                    .frame(width: 24)
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
        case .actor:
            return isAssisted ? "Who was in \(current.matchText)?"
                              : "Name an actor from \(current.matchText)"
        case .movie:
            return isAssisted ? "Which was \(current.matchText) in?"
                              : "Name a movie \(current.matchText) was in"
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

            if engine.awaitingRetry {
                retryButton
            } else {
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
                    .buttonStyle(.pressScale)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
                }
                .shake(shakeToken)
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
        .background(Theme.Color.canvas)
        .animation(.snappy, value: engine.feedback)
    }

    // MARK: Options panel (Assisted mode — tap one of three)

    private var optionsPanel: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let feedback = engine.feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if engine.awaitingRetry {
                retryButton
            } else {
                // All options share the turn's category color (they're all the same
                // kind), so nothing leaks which is correct. A wrong tap shakes the
                // whole panel.
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(engine.currentOptions) { node in
                        optionButton(node)
                    }
                }
                .shake(shakeToken)
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
        .background(Theme.Color.canvas)
        .animation(.snappy, value: engine.feedback)
        .animation(Theme.Motion.drop, value: engine.currentOptions)
    }

    private func optionButton(_ node: ChainNode) -> some View {
        Button { select(node) } label: {
            HStack(spacing: Theme.Spacing.md) {
                NodeThumbnail(node: node, size: 46)
                Text(node.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .strokeBorder(Theme.Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.pressScale)
        .disabled(engine.isChecking)
    }

    // Shown in place of options when a candidate load failed (both modes surface
    // this; the panel just hosts it in Assisted). Retrying reloads and restarts
    // the turn clock fresh.
    private var retryButton: some View {
        Button { Task { await engine.retryTurn() } } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.clockwise")
                Text("Retry").frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
    }

    private func select(_ node: ChainNode) {
        Task { await engine.select(node) }
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

#Preview("Hardcore") {
    let engine = GameEngine()
    engine.loadDemoChain()
    return GameView(engine: engine)
}

#Preview("Assisted") {
    let engine = GameEngine()
    engine.loadDemoChain(assisted: true)
    return GameView(engine: engine)
}
