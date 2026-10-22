//
//  GameOverView.swift
//  movie-quiz
//
//  End-of-run summary: final score, a quiet "new best" mark, the near-miss that
//  ended the run, the full chain revealed (as compact cards, or as category
//  tiles under the prototype's tile style), a share card, and a play-again.
//

import SwiftUI

struct GameOverView: View {
    @Bindable var engine: GameEngine
    var collection: CollectionStore
    let summary: GameEngine.Summary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showReel = false
    /// Bumped once to fire the one-shot score bounce on a new best. The score's
    /// resting scale is always 1, so nothing here can leave it stuck oversized.
    @State private var scorePop = 0
    /// Prototype switch: the recap follows the play screen's chain treatment.
    @AppStorage("chainStyle") private var chainStyle: ChainStyle = .cards

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            summaryCard

            if let missed = summary.missedAnswer {
                oneAway(missed)
            }

            recapSection

            actions
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.canvas.ignoresSafeArea())
        .task {
            guard summary.isNewBest else { return }
            // Reduce Motion: the celebratory haptic still fires, but no visual pop.
            if reduceMotion { Haptics.celebrate(); return }
            // Wait out the screen-push carousel (Theme.Motion.screen, ~0.45s)
            // so the bounce reads as a landing beat rather than overlapping the
            // horizontal push. Haptic + pop fire together, after the settle.
            // `.task` is cancelled if the screen leaves first (a fast "Play
            // again"); `try?` swallows that, so check before firing.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            Haptics.celebrate()
            scorePop += 1
        }
        .sheet(isPresented: $showReel) {
            CollectionView(store: collection, bestChain: engine.bestChain)
        }
    }

    // MARK: Summary card — this run first, then best and Reel, quieter
    //
    // One card answers "how did I do?". The top half is this run, emphasised:
    // the link count as the hero numeral and the points beside its unit. Below a
    // rule sit two quiet cells: the personal best (hidden on a new best, where
    // it would just repeat this run) and the Reel, tappable. Terminology is
    // fixed app-wide: a *chain* is a whole run, a *link* is one correct answer
    // (the score counts links), and the dealt start is not a link.

    private var summaryCard: some View {
        VStack(spacing: 0) {
            runHero
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.md)

            if showsBest || showsReel {
                Rectangle().fill(Theme.Color.border).frame(height: Theme.Border.width)
                HStack(spacing: 0) {
                    if showsBest { bestCell }
                    if showsBest && showsReel {
                        Rectangle().fill(Theme.Color.border).frame(width: Theme.Border.width)
                    }
                    if showsReel { reelCell }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .neoSurface(radius: Theme.Radius.card)
    }

    private var showsBest: Bool { !summary.isNewBest && engine.bestChain > 0 }
    private var showsReel: Bool { collection.total > 0 }

    private var linkWord: String { engine.score == 1 ? "link" : "links" }

    private var runHero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if summary.isNewBest {
                Text("a new best")
                    .font(Theme.Font.flourish(.subheadline))
                    .foregroundStyle(Theme.Color.onAccent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .neoSurface(radius: Theme.Radius.pill, fill: Theme.Color.good,
                                shadow: Theme.Shadow.small)
                    .transition(.scale.combined(with: .opacity))
            }

            // The unit sits on the numeral's baseline so "2 links" reads as one
            // figure; points get their own line beneath it.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("\(engine.score)")
                    .font(Theme.Font.display(72))
                    .foregroundStyle(Theme.Color.ink)
                    .contentTransition(.numericText())
                Text(linkWord)
                    .font(Theme.Font.flourish(.title2))
                    .foregroundStyle(Theme.Color.muted)
            }
            // One-shot bounce (up then settle) fired by `scorePop` on a new best.
            // Resting scale is 1, so it can never get stuck oversized.
            .keyframeAnimator(initialValue: 1.0, trigger: scorePop) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.12, duration: 0.18)
                    SpringKeyframe(1.0, duration: 0.42, spring: .bouncy)
                }
            }

            Text("\(engine.points) pts")
                .font(Theme.Font.numeral(.title3))
                .foregroundStyle(Theme.Color.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(engine.score) \(linkWord), \(engine.points) points\(summary.isNewBest ? ", a new best" : "")")
    }

    // The personal best, deliberately quiet: small label, small muted figures.
    private var bestCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Best").metaLabel(size: .small)
            Text("\(engine.bestChain) links · \(engine.bestPoints) pts")
                .font(Theme.Font.numeral(.footnote))
                .foregroundStyle(Theme.Color.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .accessibilityElement(children: .combine)
    }

    // What this run added to the Reel, one line, tappable into the sheet.
    private var reelCell: some View {
        Button { showReel = true } label: {
            HStack(spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Reel").metaLabel(size: .small)
                    Text(reelMessage)
                        .font(Theme.Font.numeral(.footnote))
                        .foregroundStyle(Theme.Color.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Theme.Font.labelSmall)
                    .foregroundStyle(Theme.Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
    }

    private var reelMessage: String {
        if summary.reelAdditions > 0 {
            return "+\(summary.reelAdditions) new · \(collection.total) total"
        }
        return "\(collection.total) logged"
    }

    // MARK: One-away near-miss

    private func oneAway(_ node: ChainNode) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("You were one away").metaLabel()
            HStack(spacing: Theme.Spacing.sm) {
                NodeDot(kind: node.kind)
                NodeName(node: node,
                         font: Theme.Font.heading(.title3),
                         yearFont: Theme.Font.flourish(.title3))
                    .multilineTextAlignment(.center)
            }
            Text(node.kind == .actor ? "was in the cast" : "was in the filmography")
                .font(Theme.Font.flourish(.footnote))
                .foregroundStyle(Theme.Color.muted)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: Chain recap

    private var recapSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Your chain").metaLabel()
            ScrollView {
                switch chainStyle {
                case .cards:
                    VStack(spacing: Theme.Spacing.xs + 2) {
                        ForEach(Array(engine.chain.enumerated()), id: \.element.id) { i, node in
                            // The start isn't a link: it gets a flag, and the
                            // links count from 1, so the last number matches
                            // the score above.
                            CompactChainCard(node: node, position: i == 0 ? nil : i,
                                             isStart: i == 0)
                                .appear(i, animation: Theme.Motion.cascade, offset: 14)
                        }
                    }
                    // Room for the hard shadows, which draw outside each card.
                    .padding(.trailing, Theme.Shadow.small)
                    .padding(.bottom, Theme.Spacing.sm)
                case .tiles:
                    ChainStack(chain: engine.chain, numbered: true, showKind: false, staggered: true)
                        .padding(.bottom, Theme.Spacing.sm)
                }
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
    return GameOverView(engine: engine, collection: CollectionStore(fileURL: nil),
                        summary: engine.summary ?? .init())
}
