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
    /// The home → play handoff, when this screen was reached by tapping the
    /// home's blank: the start card and the dock wait hidden for it to land.
    @Environment(HandoffStage.self) private var stage: HandoffStage?
    @Environment(\.analytics) private var analytics

    @State private var answer = ""
    @FocusState private var fieldFocused: Bool
    @State private var gainToken = 0     // bumps to replay the "+N" pop
    @State private var shakeToken = 0    // bumps to shake the field on reject
    /// Set once the player starts typing again after a reject, so the error
    /// hands its line back to the next-up hint.
    @State private var feedbackDismissed = false
    /// Height of the band between the score and the hint, for the deck's pile.
    @State private var chainBandHeight: CGFloat = 0
    /// Bumps to fire the one-shot score bounce when a run passes the record.
    @State private var recordPop = 0
    /// DEBUG screenshot hook: act as if this run had passed the record.
    @State private var forceBeating = false
    /// Set by Quit while the keyboard goes down, before the run actually ends.
    @State private var quitting = false

    /// This run is past the previous best: the score shows green with "new best"
    /// for the rest of the run.
    private var beatingBest: Bool { engine.isBeatingBest || forceBeating }

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
                    ChainDeck(chain: engine.chain, availableHeight: chainBandHeight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The deck sizes its pile to this (it shrinks as the keyboard rises).
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chainBandHeight = $0 }
                // Time's up: the pile sags 4pt and settles — the chain dropped,
                // not just the screen changing. Reduce Motion: no sag.
                .keyframeAnimator(initialValue: 0.0, trigger: engine.timeUp) { [reduceMotion] view, sag in
                    view.offset(y: reduceMotion ? 0 : sag)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(4, duration: 0.12)
                        SpringKeyframe(0, duration: 0.3, spring: .snappy)
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
            // Feedback warm-up (haptics + audio) happens on the seed screen, off
            // this transition — `AVAudioEngine.start()` briefly blocks the main
            // actor. Here we only raise the keyboard. Arriving by the handoff, it
            // comes up at once, so the flight rides it into place (one frame's
            // wait still lets the field enter the responder chain — a synchronous
            // focus set on a cold launch is dropped). Arriving from search, the
            // screen cross-fades in first: focusing mid-fade relays the safe area
            // under it.
            let handoff = stage?.isFlying == true
            try? await Task.sleep(for: .milliseconds(handoff ? 16 : 350))
            // Bail if the view went away during the wait (e.g. a fast Quit) —
            // `try?` swallows the sleep's cancellation, so without this the focus
            // set would fire on whatever screen replaced us and jump the keyboard.
            guard !Task.isCancelled else { return }
            fieldFocused = true
            // The first turn's clock starts once the player can see the turn:
            // after the handoff lands (below), or now.
            guard handoff else { engine.playerReady(); return }
            // Resumes once focusing (and its first-time keyboard load) has passed:
            // the flight's cue to go.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            stage?.inputFocused = true
        }
        .onChange(of: stage?.isFlying ?? false) { _, flying in
            if !flying { engine.playerReady() }
        }
        #if DEBUG
        .onAppear {
            // Screenshot hook: show the record state without having to beat a best.
            if ProcessInfo.processInfo.arguments.contains("-uiDemoRecordCue") {
                forceBeating = true
                recordPop += 1
            }
        }
        #endif
        .onChange(of: engine.score) { old, new in
            guard new > old else { return }
            onCorrect()
            if let kind = engine.chain.last?.kind {
                analytics.capture(.linkLanded(link: new, kind: kind, fast: engine.lastAnswerFast))
            }
        }
        .onChange(of: engine.awaitingRetry) { _, failed in
            if failed { analytics.capture(.turnLoadFailed(links: engine.score)) }
        }
        // `rejections`, not `feedback`: two identical misses in a row leave
        // `feedback` unchanged, and the second must still shake and buzz.
        .onChange(of: engine.rejections) {
            feedbackDismissed = false
            onReject()
        }
        .onChange(of: engine.feedback) { feedbackDismissed = false }
        .onChange(of: engine.timeUp) { _, up in
            if up { onTimeUp() }
        }
        .onChange(of: answer) { _, new in
            if !new.isEmpty, !feedbackDismissed {
                withAnimation(Theme.Motion.reducedFade) { feedbackDismissed = true }
            }
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
                .contentTransition(.numericText(countsDown: true))
                // A content transition only plays inside an animation.
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: engine.secondsRemaining)

            Spacer()

            Button(action: quit) {
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
                    .foregroundStyle(beatingBest ? Theme.Color.good : Theme.Color.ink)
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
            // The record bounce: on the link that passes the best, the figure
            // swells, dips just under its size, and settles — fired once by
            // `recordPop`. Resting scale is 1, so it can never get stuck large.
            // Reduce Motion keeps the colour change and drops the bounce.
            // `[reduceMotion]`: the content closure is `@Sendable` (SwiftUI may
            // run it off the main actor), so copy the flag rather than read `self`.
            .keyframeAnimator(initialValue: 1.0, trigger: recordPop) { [reduceMotion] view, scale in
                view.scaleEffect(reduceMotion ? 1 : scale, anchor: .center)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.15, duration: 0.16)
                    CubicKeyframe(0.97, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.36, spring: .snappy)
                }
            }

            pointsLine
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
        .animation(.snappy, value: engine.score)
        .animation(Theme.Motion.emphasized, value: beatingBest)
    }

    // Past the record, the points line adds "new best" for the rest of the run.
    @ViewBuilder private var pointsLine: some View {
        if beatingBest {
            Text("\(Text("\(engine.points) pts").font(Theme.Font.numeral(.body)).foregroundStyle(Theme.Color.muted)) \(Text("·").foregroundStyle(Theme.Color.muted)) \(Text("new best").font(Theme.Font.flourish(.body)).foregroundStyle(Theme.Color.good))")
                .contentTransition(.numericText())
        } else {
            Text("\(engine.points) pts")
                .font(Theme.Font.numeral(.body))
                .foregroundStyle(Theme.Color.muted)
                .contentTransition(.numericText())
        }
    }

    // MARK: Next-up hint (and, after a miss, the error)

    /// The error to show, if any: a reject's message until the player starts
    /// typing the next try. A load failure stays until Retry clears it.
    private var visibleFeedback: String? {
        guard let feedback = engine.feedback else { return nil }
        return feedbackDismissed && !engine.awaitingRetry ? nil : feedback
    }

    // One fixed line that carries either the next-up hint or the error, cross-
    // fading between them. The error used to be an extra row in the answer dock,
    // which grew the bottom inset on every miss and squeezed the chain band.
    private var nextHint: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: Theme.Spacing.sm) {
                NodeDot(kind: engine.expectedKind)
                Text(hintText)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.opacity)
            }
            .opacity(visibleFeedback == nil ? 1 : 0)

            if let feedback = visibleFeedback {
                Text(feedback)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.danger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xs)
        // The hint changes as the new link lands, so it arrives on the same beat.
        .animation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.drop, value: engine.chain.count)
        .animation(Theme.Motion.reducedFade, value: visibleFeedback)
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
            if engine.awaitingRetry {
                retryButton
                    .transition(dockSwap)
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
                        // Reduce Motion's stand-in for the shake: the field's
                        // border flashes red and fades — a rejection you can see
                        // without anything moving.
                        // (The content closure is `@Sendable`, so the theme
                        // values are captured here rather than read inside.)
                        .keyframeAnimator(initialValue: 0.0, trigger: shakeToken) { [reduceMotion,
                                                                                     radius = Theme.Radius.md,
                                                                                     danger = Theme.Color.danger,
                                                                                     width = Theme.Border.width] view, flash in
                            view.overlay {
                                RoundedRectangle(cornerRadius: radius)
                                    .strokeBorder(danger, lineWidth: width)
                                    .opacity(reduceMotion ? flash : 0)
                            }
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(1.0, duration: 0.05)
                                CubicKeyframe(1.0, duration: 0.25)
                                CubicKeyframe(0.0, duration: 0.4)
                            }
                        }

                    Button("Go", action: submit)
                        .buttonStyle(.primary)
                        .fixedSize()
                        .disabled(!canSubmit)
                }
                .shake(shakeToken)
                .handoffTarget(.dock, stage)
                .opacity(stage?.isFlying == true ? 0 : 1)
                .transition(dockSwap)
            }
        }
        // Time's up: the input greys out as the keyboard takes it down (see
        // `onTimeUp`); the engine already ignores answers once `timeUp` is set.
        .opacity(engine.timeUp ? 0.5 : 1)
        .animation(.easeOut(duration: 0.2), value: engine.timeUp)
        .animation(.easeOut(duration: 0.2), value: engine.awaitingRetry)
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Color.canvas)
    }

    /// The input row ⇄ Retry swap after a failed load: a quick cross-fade with a
    /// slight scale, instead of one teleporting into the other's place.
    private var dockSwap: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
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
        // The link that passed the record: the score turns green and bounces,
        // with the celebrate haptic and the record chime on the same beat.
        Haptics.celebrate()
        if soundEnabled { SoundPlayer.shared.record() }
        recordPop += 1
        AccessibilityNotification.Announcement("A new best").post()
    }

    /// The clock ran out: the "time's up" beat. The wrong-answer buzz marks the
    /// moment the run ends; the dock dims and the pile sags (above) on the same
    /// beat, then the engine moves on to game over.
    /// The run is over, so the keyboard goes now — during the beat before game
    /// over, which outlasts its ~250ms exit. Left up, it would close only once
    /// this screen was pushed away, sliding down over the game-over screen.
    private func onTimeUp() {
        Haptics.wrong()
        if soundEnabled { SoundPlayer.shared.wrong() }
        fieldFocused = false
    }

    /// Lower the keyboard first, then end the run once it's down, so it isn't
    /// still sliding away as the game-over screen comes in. The keyboard moving
    /// is the immediate answer to the tap, so the wait doesn't read as lag.
    private func quit() {
        guard !quitting else { return }
        quitting = true
        fieldFocused = false
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            engine.quit()
        }
    }

    private func onReject() {
        Haptics.wrong()
        if soundEnabled { SoundPlayer.shared.wrong() }
        shakeToken += 1
    }

    private func submit() {
        // Once the run is ending, a Go mustn't raise the keyboard back up.
        guard !engine.timeUp, !quitting else { return }
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
