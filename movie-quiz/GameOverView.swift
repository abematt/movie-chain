//
//  GameOverView.swift
//  movie-quiz
//
//  End-of-run summary: final score, a quiet "new best" mark, the near-miss that
//  ended the run, the full chain revealed as category tiles, a share card, and a
//  play-again.
//

import SwiftUI

struct GameOverView: View {
    @Bindable var engine: GameEngine
    var collection: CollectionStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showReel = false
    /// Bumped once to fire the one-shot score bounce on a new best. The score's
    /// resting scale is always 1, so nothing here can leave it stuck oversized.
    @State private var scorePop = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            scoreHeader

            bestLine

            reelLine

            if let missed = engine.missedAnswer {
                oneAway(missed)
            }

            recapSection

            actions
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.canvas.ignoresSafeArea())
        .onAppear {
            guard engine.isNewBest else { return }
            // Reduce Motion: the celebratory haptic still fires, but no visual pop.
            if reduceMotion { Haptics.celebrate(); return }
            Task {
                // Wait out the screen-push carousel (Theme.Motion.screen, ~0.45s)
                // so the bounce reads as a landing beat rather than overlapping the
                // horizontal push. Haptic + pop fire together, after the settle.
                try? await Task.sleep(for: .milliseconds(450))
                Haptics.celebrate()
                scorePop += 1
            }
        }
        .sheet(isPresented: $showReel) {
            CollectionView(store: collection, bestChain: engine.bestChain)
        }
    }

    // MARK: Reel — what this run added to the collection

    @ViewBuilder private var reelLine: some View {
        if collection.total > 0 {
            Button { showReel = true } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "film.stack")
                        .font(.footnote)
                        .foregroundStyle(engine.reelAdditions > 0 ? Theme.Color.good : .secondary)
                    Text(reelMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Color.ink)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var reelMessage: String {
        if engine.reelAdditions > 0 {
            let n = engine.reelAdditions
            return "\(n) new to your Reel · \(collection.total) total"
        }
        return "View your Reel · \(collection.total)"
    }

    // MARK: Score header

    private var scoreHeader: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(engine.endedByQuit ? "Chain ended" : "Time's up")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            if engine.isNewBest {
                Text("a new best")
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.Color.onAccent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background(Theme.Color.good, in: Capsule())
                    .padding(.top, 2)
                    .transition(.scale.combined(with: .opacity))
            }

            Text("\(engine.score)")
                .font(.system(size: 72, weight: .bold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
                // One-shot bounce (up then settle) fired by `scorePop` on a new
                // best. Resting scale is 1, so it can never get stuck oversized.
                .keyframeAnimator(initialValue: 1.0, trigger: scorePop) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1.12, duration: 0.18)
                        SpringKeyframe(1.0, duration: 0.42, spring: .bouncy)
                    }
                }

            Text("\(engine.points) pts")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Personal best — fenced off so it never reads as this run

    private var bestLine: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Personal best")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Theme.Color.ink)
                Text("\(engine.bestChain) links · \(engine.bestPoints) pts")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Theme.Spacing.sm + 2)
            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
        }
    }

    // MARK: One-away near-miss

    private func oneAway(_ node: ChainNode) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("You were one away")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.sm) {
                NodeDot(kind: node.kind)
                Text(node.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Color.ink)
            }
            Text(node.kind == .actor ? "was in the cast" : "was in the filmography")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: Chain recap

    private var recapSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Your chain")
                .font(.caption.weight(.heavy))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.tertiary)
            ScrollView {
                ChainStack(chain: engine.chain, numbered: true, showKind: false, staggered: true)
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                engine.reset()
            } label: {
                Text("Play again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)

            ShareLink(item: engine.shareSummary) {
                Text("Share").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ghost)
        }
    }
}

#Preview {
    let engine = GameEngine()
    engine.loadDemoGameOver()
    return GameOverView(engine: engine, collection: CollectionStore(fileURL: nil))
}
