//
//  GameOverView.swift
//  movie-quiz
//
//  End-of-run summary: final score, a quiet "new best" mark, the near-miss that
//  ended the run, the full chain revealed (as compact cards, or as category
//  tiles under the Tiles chain style), a share card, and a play-again.
//

import SwiftUI

struct GameOverView: View {
    @Bindable var engine: GameEngine
    var collection: CollectionStore
    let summary: GameEngine.Summary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.telemetry) private var telemetry
    @State private var showReel = false
    /// Bumped once to fire the one-shot score bounce on a new best. The score's
    /// resting scale is always 1, so nothing here can leave it stuck oversized.
    @State private var scorePop = 0
    /// The new-best sticker, in two beats: `stickerPlaced` lands it on the card
    /// (fast), `stickerPressed` smooths it down from a big peel to a slight one.
    @State private var stickerPlaced = false
    @State private var stickerPressed = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            summaryCard

            if let missed = summary.missedAnswer {
                oneAway(missed)
                    // First beat of the deal-in, ahead of the chain cards, so
                    // nothing on this screen arrives unannounced.
                    .appear(0, animation: Theme.Motion.cascade, offset: 14,
                            after: Theme.Motion.screenSettle)
            }

            recapSection

            actions
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.canvas.ignoresSafeArea())
        // The play screen lowers its keyboard before handing over; should one
        // still be on its way down, it slides off over this screen instead of
        // re-laying it out as it goes.
        .ignoresSafeArea(.keyboard)
        .task {
            guard summary.isNewBest else { return }
            // Reduce Motion: the celebratory haptic still fires, but no visual pop.
            if reduceMotion {
                stickerPlaced = true
                stickerPressed = true
                Haptics.celebrate()
                return
            }
            // Wait out the screen-push carousel (Theme.Motion.screen, ~0.45s)
            // so the bounce reads as a landing beat rather than overlapping the
            // horizontal push. Haptic + pop fire together, after the settle.
            // `.task` is cancelled if the screen leaves first (a fast "Play
            // again"); `try?` swallows that, so check before firing.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            Haptics.celebrate()
            scorePop += 1
            // Slapped on, then pressed flat from the stuck edge outward — the
            // big peel springs down to a slight lift at the corner.
            withAnimation(.easeOut(duration: 0.16)) { stickerPlaced = true }
            withAnimation(.spring(duration: 0.55, bounce: 0.3).delay(0.06)) { stickerPressed = true }
        }
        .sheet(isPresented: $showReel) {
            CollectionView(store: collection, bestChain: engine.bestChain, openedFrom: .gameOver)
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
                // A little headroom so the sticker in the corner clears the score.
                .padding(.top, summary.isNewBest ? Theme.Spacing.sm : 0)
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
        // Stuck flat in the card's top-trailing corner, inside its edges (hanging
        // off the border read as floating). It sits in the empty corner above
        // "links", clear of the centred score.
        .overlay(alignment: .topTrailing) {
            if summary.isNewBest {
                newBestSticker
                    .padding(.top, Theme.Spacing.sm + 2)
                    .padding(.trailing, Theme.Spacing.sm + 2)
            }
        }
    }

    /// The chain cards deal in after the "one away" card when there is one.
    private var recapStaggerStart: Int { summary.missedAnswer == nil ? 0 : 1 }

    // MARK: New-best sticker

    private var newBestSticker: some View {
        HoloSticker(rotation: .degrees(-8),
                    peel: stickerPressed ? 0.22 : 0.7,
                    // Casts a shadow only while it's still in the air; pressed
                    // flat, the shadow is gone and it's part of the card.
                    shadow: stickerPressed ? 0 : Theme.Shadow.large * 2,
                    wearSeed: 21,
                    // The Reel sheet covers it without making it disappear.
                    active: !showReel) {
            VStack(spacing: 0) {
                Text("New best!")
                    .font(Theme.Font.heading(.title3))
                // The record it beat means more than the label alone.
                if summary.previousBest > 0 {
                    Text("was \(summary.previousBest)")
                        .font(Theme.Font.flourish(.footnote))
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .scaleEffect(stickerPlaced ? 1 : 1.25)
        .opacity(stickerPlaced ? 1 : 0)
        .accessibilityHidden(true)   // the hero's label already says "a new best"
    }

    private var showsBest: Bool { !summary.isNewBest && engine.bestChain > 0 }
    private var showsReel: Bool { collection.total > 0 }

    private var linkWord: String { summary.links == 1 ? "link" : "links" }

    private var runHero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // The unit sits on the numeral's baseline so "2 links" reads as one
            // figure; points get their own line beneath it.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("\(summary.links)")
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

            Text("\(summary.points) pts")
                .font(Theme.Font.numeral(.title3))
                .foregroundStyle(Theme.Color.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.links) \(linkWord), \(summary.points) points\(summary.isNewBest ? ", a new best" : "")")
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
                VStack(spacing: Theme.Spacing.xs + 2) {
                    ForEach(Array(summary.chain.enumerated()), id: \.element.id) { i, node in
                        // The start isn't a link: it gets a flag, and the
                        // links count from 1, so the last number matches
                        // the score above.
                        CompactChainCard(node: node, position: i == 0 ? nil : i,
                                         isStart: i == 0)
                            // Starts as the push settles, so the cascade
                            // isn't spent underneath the slide.
                            .appear(i + recapStaggerStart, animation: Theme.Motion.cascade,
                                    offset: 14, after: Theme.Motion.screenSettle)
                    }
                }
                // Room for the hard shadows, which draw outside each card.
                .padding(.trailing, Theme.Shadow.small)
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

            ShareLink(item: summary.shareText) {
                Text("Share").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ghost)
            // ShareLink has no action of its own; a tap opening the sheet is the
            // signal (whether they then sent it isn't knowable).
            .simultaneousGesture(TapGesture().onEnded {
                telemetry?.shared(from: .gameOver)
            })
        }
    }
}

#Preview {
    let engine = GameEngine()
    engine.loadDemoGameOver()
    return GameOverView(engine: engine, collection: CollectionStore(fileURL: nil),
                        summary: engine.summary ?? .init())
}
