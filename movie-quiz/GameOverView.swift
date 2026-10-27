//
//  GameOverView.swift
//  movie-quiz
//
//  End-of-run summary, on Night — or, when the run beat the record, on the holo
//  sky: a new best isn't a screen of its own, it's this one with the foil laid
//  flat as the ground. The first screenful is the result: how it ended, the link
//  count huge, and the chain as a coin stack, which names every link. Scrolling
//  down gives the answer you were one away from, and the best and the Reel.
//  Play again stays pinned at the foot.
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
    /// The share card, drawn once the screen has settled.
    @State private var shareImage: Image?
    /// The first share asks your name before the share sheet opens.
    @AppStorage(PlayerName.askedKey) private var nameAsked = false
    @AppStorage(PlayerName.key) private var playerName = ""
    @State private var askingName = false
    @State private var nameDraft = ""
    @State private var sharingAfterName = false

    private var best: Bool { summary.isNewBest }
    /// How much of the recap shows above the actions on the first screen.
    private static let recapPeek: CGFloat = 52
    /// Type on the ground: white on Night, ink on the holo sky.
    private var fg: Color { best ? Theme.Color.night : .white }
    private var sub: Color { best ? Theme.Color.night.opacity(0.72) : Theme.Color.quietOnNight }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    result
                        // The first screenful is the result. The one-away card's top
                        // edge peeks above the actions, so it reads as more below;
                        // with no card, the quiet lines under it stay below the fold.
                        .frame(height: max(420, geo.size.height
                                            - (summary.missedAnswer == nil ? Theme.Spacing.md : Self.recapPeek)))
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
        // Applied before the Reel sheet, so the sheet still follows the reader's size.
        .dynamicTypeSize(...Theme.Font.gameTypeCap)
        .task {
            // Once the screen has settled — after the push, the coin stack's rise
            // and a new best's bounce — so drawing the card can't hitch any of them.
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            shareImage = ShareCard.image(chain: summary.chain, links: summary.links, daily: summary.daily)
        }
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
        #if DEBUG
        // Screenshot hook: the first share's name prompt, without tapping Share.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiAskName") else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            askingName = true
        }
        #endif
        .alert("What should friends call you?", isPresented: $askingName) {
            TextField("Your name", text: $nameDraft)
                .textInputAutocapitalization(.words)
            Button("Share") {
                playerName = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(PlayerName.maxLength))
                nameAsked = true
                sharingAfterName = true
            }
            Button("Skip", role: .cancel) {
                nameAsked = true
                sharingAfterName = true
            }
        } message: {
            Text("It goes on your challenges, so friends know who sent them. Change it in Settings.")
        }
        .sheet(isPresented: $sharingAfterName) {
            ActivityShareSheet(items: [summary.shareText(link: shareLink)])
                .presentationDetents([.medium, .large])
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
            // A daily names its day: it's the run friends compare.
            if let daily = summary.daily {
                Text("Daily #\(daily)")
                    .metaLabel(sub)
                    .padding(.top, Theme.Spacing.xl)
            }
            HStack(alignment: .firstTextBaseline) {
                // How it ended, as the sentence the number finishes.
                Text(summary.endedByQuit ? "You ended on" : "Time’s up at")
                    .font(Theme.Font.sentence(.title2))
                    .foregroundStyle(sub)
                Spacer()
                if best { newBestTag }
            }
            .padding(.top, summary.daily == nil ? Theme.Spacing.xl : Theme.Spacing.xs)

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.links) \(linkWord), \(summary.points) points\(best ? ", a new best" : "")")

            if let challenge = summary.challenge {
                HeadToHeadPanel(challenge: challenge,
                                mine: RunScore(links: summary.links, points: summary.points),
                                fg: fg, sub: sub)
                    .padding(.top, Theme.Spacing.lg)
            }

            CoinStack(chain: summary.chain, labelColor: fg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
                .appear(0, animation: Theme.Motion.cascade, offset: 14, after: Theme.Motion.screenSettle)
        }
    }

    private var pointsLine: String {
        var line = "\(summary.points.formatted()) pts"
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

    // MARK: Recap — one away, then the best and the Reel
    //
    // No list of the links: the coin stack already names each one in order.

    private var recap: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if let missed = summary.missedAnswer { oneAway(missed) }
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

    /// This run as a challenge link, once `Config.shareBaseURL` is set — or, on a
    /// challenge run, the reply carrying both runs back. A daily shares no link:
    /// dailies aren't challengeable, so the share stays the plain brag.
    private var shareLink: URL? {
        guard let base = Config.shareBaseURL, summary.daily == nil,
              let shared = SharedChain(chain: summary.chain, points: summary.points,
                                       sharer: SharerID.current(in: .standard),
                                       senderName: PlayerName.current(in: .standard),
                                       replyTo: summary.challenge?.asOriginal)
        else { return nil }
        return shared.url(base: base)
    }

    private var shareKind: Telemetry.ShareLinkKind {
        guard shareLink != nil else { return .none }
        return summary.challenge == nil ? .challenge : .reply
    }

    private var shareLabel: String { summary.challenge == nil ? "Share" : "Send it back" }

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

            HStack(spacing: Theme.Spacing.md - 4) {
                shareButton
                // ShareLink has no action of its own; a tap opening the sheet is
                // the signal (whether they then sent it isn't knowable).
                .simultaneousGesture(TapGesture().onEnded {
                    telemetry?.shared(from: .gameOver, link: shareKind)
                })
                Button { showReel = true } label: {
                    Text("Your Reel").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(OutlineButtonStyle(color: fg))
            // The pair stays one height when one label wraps and the other doesn't.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
        .animation(nil, value: shareImage == nil)
        .background {
            // Solid behind the actions so the recap scrolls under them, not through.
            Group {
                if best { Theme.Holo.sky.last ?? .clear } else { Theme.Color.night }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Share

private extension GameOverView {
    /// The card and the spoiler-free text together, once the card is drawn;
    /// the text alone until then.
    @ViewBuilder var shareButton: some View {
        let text = summary.shareText(link: shareLink)
        if shareLink != nil, !nameAsked {
            // The first challenge asks your name; the sheet opens after.
            Button {
                nameDraft = playerName
                askingName = true
            } label: {
                Text(shareLabel).frame(maxWidth: .infinity)
            }
        } else if let shareImage {
            ShareLink(item: shareImage, message: Text(text),
                      preview: SharePreview("Unspool · \(summary.links) \(linkWord)", image: shareImage)) {
                Text(shareLabel).frame(maxWidth: .infinity)
            }
        } else {
            ShareLink(item: text) {
                Text(shareLabel).frame(maxWidth: .infinity)
            }
        }
    }
}

/// The secondary actions on game over: outlined in the ground's ink, no fill and
/// no side, so they sit under Play again's slab without competing with it.
private struct OutlineButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.button)
            .textCase(.uppercase)
            .tracking(Theme.Font.buttonTracking)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.field)
                .fill(color.opacity(configuration.isPressed ? 0.12 : 0)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field)
                .strokeBorder(color, lineWidth: Theme.Border.width))
            .scaleEffect(configuration.isPressed && !reduceMotion ? Theme.Motion.pressScale : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

#if DEBUG   // the demo loader is DEBUG-only
#Preview {
    let engine = GameEngine()
    engine.loadDemoGameOver()
    return GameOverView(engine: engine, collection: CollectionStore(fileURL: nil),
                        summary: engine.summary ?? .init())
}
#endif
