//
//  GameOverView.swift
//  movie-quiz
//
//  End-of-run summary, on Night — or, when the run beat the record, on the holo
//  sky: a new best isn't a screen of its own, it's this one with the foil laid
//  flat as the ground. The first screenful is the result: how it ended, the link
//  count huge, and the chain as a coin stack. Scrolling down gives the recap:
//  the answer you were one away from, and every link by name. Play again stays
//  pinned at the foot.
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

    private var best: Bool { summary.isNewBest }
    /// Type on the ground: white on Night, ink on the holo sky.
    private var fg: Color { best ? Theme.Color.night : .white }
    private var sub: Color { best ? Theme.Color.night.opacity(0.72) : Color(white: 0.74) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    result
                        // The first screenful is the result alone; the recap waits below.
                        .frame(height: max(420, geo.size.height - Theme.Spacing.md))
                    recap
                }
                .padding(.horizontal, Theme.Spacing.gutter)
            }
            .scrollIndicators(.hidden)
        }
        // The ground stops where the actions begin, so the sky's last colour
        // meets their solid band without a seam.
        .background(ground.ignoresSafeArea(edges: .top))
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        // The play screen lowers its keyboard before handing over; should one
        // still be on its way down, it slides off over this screen instead of
        // re-laying it out as it goes.
        .ignoresSafeArea(.keyboard)
        .task {
            guard best else { return }
            // Reduce Motion: the celebratory haptic still fires, but no visual pop.
            if reduceMotion { Haptics.celebrate(); return }
            // Wait out the screen push so the bounce reads as a landing beat.
            // `.task` is cancelled if the screen leaves first (a fast "Play
            // again"); `try?` swallows that, so check before firing.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            Haptics.celebrate()
            scorePop += 1
        }
        .sheet(isPresented: $showReel) {
            CollectionView(store: collection, bestChain: engine.bestChain, openedFrom: .gameOver)
        }
    }

    @ViewBuilder private var ground: some View {
        if best {
            LinearGradient(colors: Theme.Holo.sky, startPoint: .top, endPoint: .bottom)
        } else {
            Theme.Color.night
        }
    }

    // MARK: Result — how it ended, the count, the stack
    //
    // Terminology is fixed app-wide: a *chain* is a whole run, a *link* is one
    // correct answer (the score counts links), and the dealt start is not a link.

    private var linkWord: String { summary.links == 1 ? "link" : "links" }

    private var result: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(summary.endedByQuit ? "You stopped" : "Time’s up")
                    .metaLabel(sub)
                Spacer()
                if best { newBestTag }
            }
            .padding(.top, Theme.Spacing.md)

            HStack(alignment: .bottom, spacing: Theme.Spacing.md - 4) {
                Text("\(summary.links)")
                    .font(Theme.Font.display(150))
                    .foregroundStyle(fg)
                    .contentTransition(.numericText())
                    .padding(.bottom, -24)
                    // One-shot bounce fired by `scorePop` on a new best.
                    .keyframeAnimator(initialValue: 1.0, trigger: scorePop) { view, scale in
                        view.scaleEffect(scale, anchor: .bottomLeading)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.08, duration: 0.18)
                            SpringKeyframe(1.0, duration: 0.42, spring: .bouncy)
                        }
                    }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
                    Text(linkWord)
                        .font(Theme.Font.display(30))
                        .textCase(.uppercase)
                        .tracking(Theme.Font.buttonTracking)
                        .foregroundStyle(fg)
                    Text(pointsLine)
                        .font(Theme.Font.body)
                        .foregroundStyle(sub)
                }
                .padding(.bottom, Theme.Spacing.sm)
            }
            .padding(.top, Theme.Spacing.sm)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.links) \(linkWord), \(summary.points) points\(best ? ", a new best" : "")")

            CoinStack(chain: summary.chain, labelColor: fg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
                .appear(0, animation: Theme.Motion.cascade, offset: 14, after: Theme.Motion.screenSettle)
        }
    }

    private var pointsLine: String {
        var line = "\(summary.points) pts"
        if best, summary.previousBest > 0 { line += " · was \(summary.previousBest)" }
        return line
    }

    private var newBestTag: some View {
        Text("New best")
            .font(Theme.Font.button)
            .textCase(.uppercase)
            .tracking(Theme.Font.buttonTracking)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, Theme.Spacing.xs)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.Color.night))
            .accessibilityHidden(true)   // the count's label already says "a new best"
    }

    // MARK: Recap — one away, then every link

    private var recap: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if let missed = summary.missedAnswer { oneAway(missed) }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Your chain · \(summary.links) \(linkWord) · \(summary.points) pts").metaLabel(sub)
                ForEach(Array(summary.chain.enumerated()), id: \.element.id) { i, node in
                    recapRow(node, index: i)
                }
            }
            if showsBest || showsReel { footnotes }
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
    }

    // The answer that would have kept the run going: a paper card, the one
    // object on this ground.
    private func oneAway(_ node: ChainNode) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
            Text("You were one away").metaLabel()
            HStack(spacing: Theme.Spacing.sm) {
                NodeDot(kind: node.kind)
                NodeName(node: node, font: Theme.Font.heading(.title2), yearFont: Theme.Font.sentence(.title3))
            }
            Text(node.kind == .actor ? "was in the cast" : "was in the filmography")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md + 2)
        .neoSurface(radius: Theme.Radius.card, fill: .white, shadow: Theme.Shadow.large, side: .black)
        .environment(\.colorScheme, .light)
    }

    private func recapRow(_ node: ChainNode, index: Int) -> some View {
        HStack(spacing: Theme.Spacing.md - 4) {
            Text(index == 0 ? "ST" : String(format: "%02d", index))
                .font(Theme.Font.labelSmall)
                .foregroundStyle(sub)
                .frame(width: 22, alignment: .leading)
            NodeDot(kind: node.kind)
            Text(node.matchText)
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(fg)
                .lineLimit(1)
            Spacer(minLength: 0)
            if case .movie(let m) = node, let year = m.year {
                Text(String(year)).font(Theme.Font.small).foregroundStyle(sub)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(fg.opacity(0.14)).frame(height: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var showsBest: Bool { !best && engine.bestChain > 0 }
    private var showsReel: Bool { collection.total > 0 }

    // Best and the Reel, quiet, under the recap.
    private var footnotes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if showsBest {
                Text("Best · \(engine.bestChain) links · \(engine.bestPoints) pts")
                    .font(Theme.Font.body)
                    .foregroundStyle(sub)
            }
            if showsReel {
                Text(reelMessage).font(Theme.Font.body).foregroundStyle(sub)
            }
        }
    }

    private var reelMessage: String {
        if summary.reelAdditions > 0 {
            return "Your Reel · +\(summary.reelAdditions) new · \(collection.total) total"
        }
        return "Your Reel · \(collection.total) logged"
    }

    // MARK: Actions

    /// This run as a chain link, once `Config.shareBaseURL` is set.
    private var shareLink: URL? {
        guard let base = Config.shareBaseURL,
              let shared = SharedChain(chain: summary.chain, points: summary.points,
                                       sharer: SharerID.current(in: .standard))
        else { return nil }
        return shared.url(base: base)
    }

    // Play again is the one slab: Go lime with a white side on Night, a night
    // slab on the holo sky. Share and the Reel are quiet words beneath it.
    private var actions: some View {
        VStack(spacing: Theme.Spacing.md + 2) {
            Button {
                engine.reset()
            } label: {
                Text("Play again").frame(maxWidth: .infinity)
            }
            .buttonStyle(best
                ? SlabButtonStyle(fill: Theme.Color.night, foreground: .white, side: .black)
                : SlabButtonStyle(fill: Theme.Color.go, foreground: Theme.Color.night, side: .white))

            HStack {
                ShareLink(item: summary.shareText(link: shareLink)) {
                    Text("Share").frame(maxWidth: .infinity)
                }
                // ShareLink has no action of its own; a tap opening the sheet is
                // the signal (whether they then sent it isn't knowable).
                .simultaneousGesture(TapGesture().onEnded {
                    telemetry?.shared(from: .gameOver)
                })
                Button { showReel = true } label: {
                    Text("Your Reel").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.pressScale)
            .font(Theme.Font.button)
            .textCase(.uppercase)
            .tracking(Theme.Font.buttonTracking)
            .foregroundStyle(fg)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
        .background {
            // Solid behind the actions so the recap scrolls under them, not through.
            Group {
                if best { Theme.Holo.sky.last ?? .clear } else { Theme.Color.night }
            }
            .ignoresSafeArea()
        }
    }
}

#Preview {
    let engine = GameEngine()
    engine.loadDemoGameOver()
    return GameOverView(engine: engine, collection: CollectionStore(fileURL: nil),
                        summary: engine.summary ?? .init())
}
