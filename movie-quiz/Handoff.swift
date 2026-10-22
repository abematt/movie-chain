//
//  Handoff.swift
//  movie-quiz
//
//  The home → play handoff. The home screen is a sentence with a blank —
//  "Chris Hemsworth was in ___" — and tapping the blank turns it into the play
//  screen in place: the name, its chip and its avatar fly into the start card at
//  the bottom of the deck, the card's surface assembles around them, and the
//  blank flies down into the answer dock as the keyboard comes up.
//
//  It is a flight, not `matchedGeometryEffect` (which, in the Reel, flew the
//  wrong copy of a view underneath other layers): both screens report where
//  their pieces sit into a `HandoffStage` owned by `ContentView`, and
//  `HandoffFlight` draws copies of the pieces above both screens, moving from one
//  set of frames to the other, then hands back to the real views in one frame.
//  The play screen keeps its start card and dock hidden until then.
//
//  The destination is read live, every frame: the keyboard rising moves the
//  deck and the dock mid-flight, and the flight follows them there.
//

import SwiftUI
import UIKit

/// The pieces that fly. The home reports `chip`, `art`, `name`, `verb` and
/// `blank`; the play screen reports `card`, `chip`, `art`, `name` and `dock`.
enum HandoffPart: Hashable {
    case card, chip, art, name, verb, blank, dock
}

@MainActor @Observable
final class HandoffStage {
    /// The coordinate space every reported frame is in (the root view's).
    nonisolated static let space = "handoff"

    /// The flight in progress: the start being played and where its pieces were
    /// on the home screen when the blank was tapped. `nil` when nothing is flying.
    private(set) var flight: Flight?

    struct Flight: Equatable {
        let node: ChainNode
        let from: [HandoffPart: CGRect]
    }

    /// Where the home's pieces sit right now, by the start they belong to — so a
    /// start dealing *out* can't overwrite where the one on screen is. The blank
    /// belongs to no start (`""`).
    @ObservationIgnored private var homeFrames: [String: [HandoffPart: CGRect]] = [:]
    /// Where the play screen's pieces sit right now. Observed: the flight follows
    /// them as the keyboard moves them.
    private(set) var playFrames: [HandoffPart: CGRect] = [:]

    var isFlying: Bool { flight != nil }

    /// The play screen's answer field has taken focus. Focusing it the first time
    /// loads the keyboard and blocks the main thread for a beat; the flight waits
    /// for that to pass (held still, so the stall can't show) instead of losing
    /// its opening frames to it.
    var inputFocused = false

    /// Every destination the flight needs has been laid out.
    var destinationReady: Bool {
        [HandoffPart.card, .chip, .art, .name, .dock].allSatisfy { playFrames[$0].map { !$0.isEmpty } ?? false }
    }

    func reportHome(_ part: HandoffPart, _ frame: CGRect, for nodeID: String = "") {
        homeFrames[nodeID, default: [:]][part] = frame
    }

    func reportPlay(_ part: HandoffPart, _ frame: CGRect) {
        guard playFrames[part] != frame else { return }
        playFrames[part] = frame
    }

    /// The blank was tapped: freeze where the home's pieces are and start flying.
    func begin(with node: ChainNode) {
        playFrames = [:]
        inputFocused = false
        let from = (homeFrames[node.id] ?? [:]).merging(homeFrames[""] ?? [:]) { own, _ in own }
        flight = Flight(node: node, from: from)
        homeFrames = [:]
    }

    /// The flight landed (or gave up): the real views take over.
    func finish() {
        flight = nil
    }
}

extension View {
    /// Report this view's frame to the handoff stage as one of the home's pieces
    /// — the dealt start `nodeID`'s, or the blank's (no start).
    func handoffSource(_ part: HandoffPart, _ stage: HandoffStage?, for nodeID: String = "") -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(HandoffStage.space)) } action: {
            stage?.reportHome(part, $0, for: nodeID)
        }
    }

    /// Report this view's frame to the handoff stage as one of play's pieces.
    func handoffTarget(_ part: HandoffPart, _ stage: HandoffStage?) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(HandoffStage.space)) } action: {
            stage?.reportPlay(part, $0)
        }
    }
}

// MARK: - The flight

/// Drawn by `ContentView` above both screens while a handoff is flying. Starts
/// once the play screen has laid out its destinations, and gives up (handing
/// straight to the real views) if they never arrive.
struct HandoffFlight: View {
    @Environment(HandoffStage.self) private var stage
    /// When the pieces left the home; `nil` while held (or not flying).
    @State private var launchedAt: Date?

    var body: some View {
        // Its own clock rather than an animated value: each frame works out the
        // flight's progress from the time since launch, against wherever the
        // destinations are *that frame* — the keyboard moves them mid-flight.
        TimelineView(.animation(paused: launchedAt == nil)) { context in
            GeometryReader { proxy in
                // Frames are reported in the root's space; this overlay may not
                // start at its origin (safe areas), so draw relative to it.
                let origin = proxy.frame(in: .named(HandoffStage.space)).origin
                // Drawn from the tap on — held at the home's frames until play
                // has laid out — so there's never a frame with the pieces gone
                // from both.
                if let flight = stage.flight {
                    FlightLayers(progress: progress(at: context.date), node: flight.node,
                                 from: flight.from, to: stage.playFrames)
                        .offset(x: -origin.x, y: -origin.y)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: stage.destinationReady && stage.inputFocused, initial: true) { _, ready in
            if ready { launch() }
        }
        .task(id: launchedAt) {
            // Land: the real views take over in the same frame the copies go.
            guard launchedAt != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.Motion.handoffDuration))
            guard !Task.isCancelled else { return }
            stage.finish()
            launchedAt = nil
            // The tap opened the loop; the card landing closes it, and the clock
            // starts on this beat.
            Haptics.selection()
        }
        .task(id: stage.flight?.node.id) {
            guard stage.isFlying else { return }
            // Don't hold forever for the focus (it may never come, e.g. a
            // hardware keyboard); fly once the destinations are there.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            if stage.destinationReady { launch() }
            // A destination that never lays out mustn't leave play hidden.
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, stage.isFlying, launchedAt == nil else { return }
            stage.finish()
        }
    }

    private func launch() {
        guard stage.isFlying, launchedAt == nil else { return }
        launchedAt = .now
    }

    private func progress(at date: Date) -> CGFloat {
        guard let launchedAt else { return 0 }
        let elapsed = date.timeIntervalSince(launchedAt)
        return elapsed >= Theme.Motion.handoffDuration
            ? 1 : CGFloat(Theme.Motion.handoffSpring.value(target: 1.0, time: elapsed))
    }
}

/// The pieces in flight at `progress` (0 = on the home, 1 = in play), each
/// drawn between where it started and where its destination is now.
private struct FlightLayers: View {
    let progress: CGFloat
    let node: ChainNode
    let from: [HandoffPart: CGRect]
    let to: [HandoffPart: CGRect]

    var body: some View {
        let p = progress
        ZStack(alignment: .topLeading) {
            card(p)
            art(p)
            chip(p)
            name(p)
            verb(p)
            blank(p)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // The card's surface assembles around the pieces as they land: it fades and
    // grows into place, rather than travelling.
    @ViewBuilder private func card(_ p: CGFloat) -> some View {
        if let target = to[.card] {
            let shown = ramp(p, 0.25, 0.8)
            Color.clear
                .neoSurface(radius: Theme.Radius.card)
                // The start card's sticker, placed as `DeckCard` places it.
                .overlay(alignment: .topTrailing) {
                    StartSticker()
                        .padding(.top, Theme.Spacing.sm)
                        .padding(.trailing, Theme.Spacing.sm + 2)
                }
                .frame(width: target.width, height: target.height)
                // One layer, so the shadow doesn't show through the fill mid-fade.
                .compositingGroup()
                .scaleEffect(0.94 + 0.06 * shown)
                .opacity(shown)
                .position(x: target.midX, y: target.midY)
        }
    }

    // The avatar becomes the card's art: it moves and reshapes from a circle to
    // the art's rounded rectangle.
    @ViewBuilder private func art(_ p: CGFloat) -> some View {
        if let a = from[.art] {
            let b = to[.art] ?? a
            let rect = lerp(a, b, p)
            let radius = lerp(a.width / 2, Theme.Radius.sm, p)
            HandoffArt(node: node, radius: radius)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    @ViewBuilder private func chip(_ p: CGFloat) -> some View {
        if let a = from[.chip] {
            let b = to[.chip] ?? a
            let rect = lerp(a, b, p)
            KindChip(kind: node.kind)
                .fixedSize()
                .scaleEffect(rect.height / max(b.height, 1))
                .position(x: rect.midX, y: rect.midY)
        }
    }

    // The name can't reflow mid-flight (two lines of display type become one line
    // of a heading), so two copies fly the same path at the same letter size —
    // the home's set, fading out, and the card's, fading in.
    @ViewBuilder private func name(_ p: CGFloat) -> some View {
        if let a = from[.name] {
            let b = to[.name] ?? a
            let origin = lerp(a.origin, b.origin, p)
            let size = lerp(SentenceType.nameSize, DeckType.nameSize, p)
            SentenceName(text: node.matchText)
                .frame(width: a.width, height: a.height, alignment: .topLeading)
                .scaleEffect(size / SentenceType.nameSize, anchor: .topLeading)
                .opacity(1 - ramp(p, 0.05, 0.35))
                .blur(radius: bridge(p, 0.05, 0.45))
                .offset(x: origin.x, y: origin.y)
            DeckName(text: node.matchText)
                .frame(width: b.width, height: b.height, alignment: .topLeading)
                .scaleEffect(size / DeckType.nameSize, anchor: .topLeading)
                .opacity(ramp(p, 0.15, 0.45))
                .blur(radius: bridge(p, 0.05, 0.45))
                .offset(x: origin.x, y: origin.y)
        }
    }

    // "was in" / "starred" has no place in play: it goes with the name, fading.
    @ViewBuilder private func verb(_ p: CGFloat) -> some View {
        if let a = from[.verb], let nameA = from[.name] {
            let nameB = to[.name] ?? nameA
            let drift = lerp(nameA.origin, nameB.origin, p)
            SentenceVerb(node: node)
                .frame(width: a.width, height: a.height, alignment: .topLeading)
                .opacity(1 - ramp(p, 0, 0.35))
                .offset(x: a.minX + (drift.x - nameA.minX), y: a.minY + (drift.y - nameA.minY))
        }
    }

    // The blank flies down into the dock: the sentence's blank fading out, the
    // dock's field and Go fading in over the same path.
    @ViewBuilder private func blank(_ p: CGFloat) -> some View {
        if let a = from[.blank] {
            let b = to[.dock] ?? a
            let rect = lerp(a, b, p)
            SentenceBlank(kind: node.nextKind)
                .frame(width: a.width, height: a.height)
                .scaleEffect(x: rect.width / max(a.width, 1), y: 1, anchor: .topLeading)
                .opacity(1 - ramp(p, 0.2, 0.6))
                .blur(radius: bridge(p, 0.2, 0.9))
                .offset(x: rect.minX, y: rect.minY)
            DockLook(kind: node.nextKind)
                .frame(width: b.width, height: b.height)
                .compositingGroup()
                .opacity(ramp(p, 0.4, 0.9))
                .blur(radius: bridge(p, 0.2, 0.9))
                .offset(x: rect.minX, y: rect.minY + (rect.height - b.height) / 2)
        }
    }
}

/// A node's w185 art clipped to `radius`: the home's round avatar, and the
/// avatar in flight as it reshapes into the card's art. Drawn at once when it's
/// in memory (warmed on deal, so in flight it always is), else loaded and faded in.
struct HandoffArt: View {
    let node: ChainNode
    let radius: CGFloat
    @State private var loaded: Image?

    private var url: URL? { Config.imageURL(path: node.imagePath) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let image = loaded ?? url.flatMap(ArtCache.shared.image(for:))
        node.accent
            .overlay {
                if let image {
                    image.resizable().scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: node.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(node.kind.onAccent.opacity(0.75))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            .task(id: url) {
                guard loaded == nil, let url, ArtCache.shared.image(for: url) == nil else { return }
                let image = await ArtCache.shared.load(url)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) { loaded = image }
            }
    }
}

/// A still of the answer dock (field + disabled Go), so the dock can fade in
/// over the flight path before the real one, with its focused field, takes over.
private struct DockLook: View {
    let kind: NodeKind

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(kind.placeholder)
                .foregroundStyle(Color(uiColor: .placeholderText))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 44)
                .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
            Button("Go") {}
                .buttonStyle(.primary)
                .fixedSize()
                .disabled(true)
        }
    }
}

// MARK: - Shared type
//
// The flight's copies must be the same type the two screens draw, so the sizes
// they hand between live here, used by both.

/// The home sentence's type.
enum SentenceType {
    static let nameSize: CGFloat = 44
    static let verbSize: CGFloat = 34
    static let blankSize: CGFloat = 34
}

/// The deck card's name type, at the reader's text size.
enum DeckType {
    static var nameSize: CGFloat { UIFontMetrics(forTextStyle: .title2).scaledValue(for: 22) }
}

/// The dealt start's name in the home sentence.
struct SentenceName: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.display(SentenceType.nameSize))
            .foregroundStyle(Theme.Color.ink)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
    }
}

/// The deck card's name (`DeckCard` draws it too).
struct DeckName: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.heading(.title2))
            .foregroundStyle(Theme.Color.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}

/// "was in" after an actor, "starred" after a movie.
struct SentenceVerb: View {
    let node: ChainNode

    var body: some View {
        Text(node.kind == .actor ? "was in" : "starred")
            .font(Theme.Font.flourish(size: SentenceType.verbSize))
            .foregroundStyle(Theme.Color.muted)
    }
}

/// The blank: the next link's placeholder over an ink rule, with the coral arrow.
/// Presses through `\.blankPressed` (set by the home's button style). `nudge`
/// bumps to play the first-run hint once: the arrow nudges toward the play
/// screen and the placeholder brightens (only the brightening under Reduce
/// Motion).
struct SentenceBlank: View {
    let kind: NodeKind
    var nudge = 0
    @Environment(\.blankPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                Text(kind == .movie ? "a movie…" : "an actor…")
                    .font(Theme.Font.flourish(size: SentenceType.blankSize))
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .keyframeAnimator(initialValue: 0.6, trigger: nudge) { view, opacity in
                        view.opacity(opacity)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.0, duration: 0.3)
                            CubicKeyframe(0.6, duration: 0.3)
                        }
                    }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.Color.ink)
                    .keyframeAnimator(initialValue: 0.0, trigger: nudge) { [reduceMotion] view, x in
                        view.offset(x: reduceMotion ? 0 : x)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(3, duration: 0.3)
                            CubicKeyframe(0, duration: 0.3)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .neoSurface(radius: Theme.Radius.md,
                                fill: pressed ? Theme.Color.primaryPressed : Theme.Color.primary,
                                shadow: Theme.Shadow.small,
                                pressed: pressed && !reduceMotion)
                    .animation(Theme.Motion.press, value: pressed)
            }
            Rectangle()
                .fill(Theme.Color.ink)
                .frame(height: 3)
        }
    }
}

extension EnvironmentValues {
    /// The home's blank is held down.
    @Entry var blankPressed = false
}

// MARK: - Interpolation

private func ramp(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
    min(1, max(0, (p - start) / (end - start)))
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a + (b - a) * p }

/// The blur that bridges a crossfade between two copies: none at either end,
/// peaking at 2pt mid-window, so the two read as one shape changing rather than
/// two shapes overlapping.
private func bridge(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
    2 * sin(.pi * ramp(p, start, end))
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ p: CGFloat) -> CGPoint {
    CGPoint(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p))
}

private func lerp(_ a: CGRect, _ b: CGRect, _ p: CGFloat) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, p), y: lerp(a.minY, b.minY, p),
           width: lerp(a.width, b.width, p), height: lerp(a.height, b.height, p))
}
