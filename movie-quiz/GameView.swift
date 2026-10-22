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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Prototype switch between chain treatments (Settings → Chain style).
    @AppStorage("chainStyle") private var chainStyle: ChainStyle = .cards

    @State private var answer = ""
    @FocusState private var fieldFocused: Bool
    @State private var gainToken = 0     // bumps to replay the "+N" pop
    @State private var shakeToken = 0    // bumps to shake the field on reject
    @State private var showRecordCue = false  // the transient in-play "a new best" pill

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
                .zIndex(1)   // the record cue floats over the chain band

            // The stack renders at its *natural* height, pinned to the bottom of
            // this flexible region; any overflow (the oldest links) is clipped off
            // the top — the "rising" effect. Without `fixedSize`, a full stack
            // would instead be compressed to fit, which shrinks the tile text.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    switch chainStyle {
                    case .cards:
                        ChainCardStack(chain: engine.chain)
                            .fixedSize(horizontal: false, vertical: true)
                    case .tiles:
                        ChainStack(chain: engine.chain, maxVisible: visibleLinks)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .clipped()

            nextHint
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { answerDock }
        .task {
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
        #if DEBUG
        .onAppear {
            // Screenshot hook: show the record cue without having to beat a best.
            if ProcessInfo.processInfo.arguments.contains("-uiDemoRecordCue") { showRecordCue = true }
        }
        #endif
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
                    .foregroundStyle(Theme.Color.muted)
                    .contentTransition(.symbolEffect(.replace))
                    // Fixed slot: the two speaker glyphs differ in width, so let the
                    // symbol swap inside a stable box rather than nudging the header.
                    .frame(width: 24)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(String(format: "0:%02d", max(0, engine.secondsRemaining)))
                .font(Theme.Font.numeral(.subheadline))
                .monospacedDigit()
                .foregroundStyle(lowTime ? Theme.Color.danger : Theme.Color.muted)
                .contentTransition(.numericText())

            Spacer()

            Button { engine.quit() } label: {
                Text("Quit").metaLabel()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Score hero (the emphasized chain number + points)

    private var scoreHero: some View {
        VStack(spacing: 2) {
            // Same as the game-over card: the unit on the numeral's baseline so
            // "4 links" reads as one figure, points on their own line. A chain is
            // the whole run; a link is one correct answer.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs + 2) {
                Text("\(engine.score)")
                    .font(Theme.Font.display(60))
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.Color.ink)
                Text(engine.score == 1 ? "link" : "links")
                    .font(Theme.Font.flourish(.title3))
                    .foregroundStyle(Theme.Color.muted)
            }
            // The "+N" rises off the end of the whole figure, clear of the unit.
            .overlay(alignment: .trailing) {
                if gainToken > 0 {
                    FloatingGain(value: engine.lastGain)
                        .id(gainToken)
                        .offset(x: 34)
                }
            }

            Text("\(engine.points) pts")
                .font(Theme.Font.numeral(.body))
                .foregroundStyle(Theme.Color.muted)
                .contentTransition(.numericText())
                // The record cue floats in the open space under the score, so it
                // costs the chain no vertical room.
                .overlay(alignment: .bottom) {
                    if showRecordCue {
                        RecordCue()
                            .offset(y: 40)
                            .transition(reduceMotion
                                        ? .opacity
                                        : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
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
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.muted)
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
                    .font(Theme.Font.small)
                    .foregroundStyle(Theme.Color.danger)
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
                        .frame(minHeight: 44)
                        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)

                    Button("Go", action: submit)
                        .buttonStyle(.primary)
                        .fixedSize()
                        .disabled(!canSubmit)
                }
                .shake(shakeToken)
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Color.canvas)
        .animation(.snappy, value: engine.feedback)
    }

    // Shown in place of the input when a candidate load failed — typing would be
    // futile with no candidate set to validate against. Retrying reloads and
    // restarts the turn clock fresh (the failure wasn't the player's fault).
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

    // MARK: Feedback reactions

    private func onCorrect() {
        gainToken += 1
        guard engine.justPassedBest else {
            Haptics.correct(streak: engine.score)
            if soundEnabled { SoundPlayer.shared.correct(streak: engine.score) }
            return
        }
        // The link that passed the record: a bigger beat than a normal link.
        Haptics.celebrate()
        if soundEnabled { SoundPlayer.shared.record() }
        withAnimation(Theme.Motion.emphasized) { showRecordCue = true }
        AccessibilityNotification.Announcement("A new best").post()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Theme.Motion.standard) { showRecordCue = false }
        }
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

// MARK: - Record cue

/// The transient "a new best" pill shown the moment a run passes the record —
/// the same green pill the game-over card uses, so the two moments read as one.
private struct RecordCue: View {
    var body: some View {
        Text("a new best")
            .font(Theme.Font.flourish(.subheadline))
            .foregroundStyle(Theme.Color.onAccent)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .neoSurface(radius: Theme.Radius.pill, fill: Theme.Color.good,
                        shadow: Theme.Shadow.small)
            .fixedSize()
            .accessibilityLabel("A new best")
    }
}

#Preview {
    let engine = GameEngine()
    engine.loadDemoChain()
    return GameView(engine: engine)
}
