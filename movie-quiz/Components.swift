//
//  Components.swift
//  movie-quiz
//
//  Reusable view primitives built on the `Theme` tokens. These are the app's
//  equivalent of a component library (shadcn/ui, in React terms): small, owned,
//  composable pieces that encapsulate the puzzle-page look so screens stay
//  declarative and consistent.
//

import SwiftUI

// MARK: - Primary button (ink-filled pill)
//
// The one prominent call-to-action ("Play again"). A solid near-black (ink)
// capsule with inverted text — the Connections "Submit" affordance. Fills width
// and gives tactile press feedback.

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .foregroundStyle(Theme.Color.onInk)
            .background(Theme.Color.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
    }
}

// MARK: - Ghost button (outlined pill)
//
// The quieter secondary action ("Share"): a hairline-outlined capsule with
// muted text. Sits under the primary CTA without competing with it.

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .foregroundStyle(.secondary)
            .background(
                Capsule().strokeBorder(Theme.Color.hairline, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
    }
}

// MARK: - Press-scale style
//
// The lightest touch of press feedback: a subtle squish + dim, no chrome of its
// own. For buttons that already carry their own background/label (the in-game
// "Go") but were missing an `isPressed` state — deliberately near-imperceptible,
// since it sits on a frequently-tapped control.

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    // A nested view so the style can read the environment: under Reduce Motion we
    // drop the scale (that's the motion) and keep only the opacity dim, which
    // still confirms the press without animating position/size.
    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(Theme.Motion.standard, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// Usage: `.buttonStyle(.primary)`
    static var primary: PrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == PressScaleStyle {
    /// Usage: `.buttonStyle(.pressScale)`
    static var pressScale: PressScaleStyle { .init() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    /// Usage: `.buttonStyle(.ghost)`
    static var ghost: GhostButtonStyle { .init() }
}

// MARK: - Card container
//
// Wraps content in a padded warm-tile surface — the standard way to visually
// cluster related content (the game-over near-miss uses it).

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

extension View {
    /// Usage: `someView.card()`
    func card() -> some View { modifier(CardModifier()) }
}

// MARK: - Node dot
//
// A small category chip (blue = actor, purple = movie) used where a full tile
// would be too heavy — seed results, the "what comes next" hint.

struct NodeDot: View {
    let kind: NodeKind
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(kind.accent)
            .frame(width: size, height: size)
    }
}

// MARK: - Node tile
//
// One link rendered as a Connections group-tile: a solid category-colored bar
// carrying the node's name (optionally its kind label and its position in the
// chain). This is the atom of both the play-screen stack and the game-over
// recap — the app's most identity-defining component.

struct NodeTile: View {
    let node: ChainNode
    /// Show the "ACTOR" / "MOVIE" kind stamp (play screen). Off in the recap,
    /// where the color already encodes kind and a number takes the slot.
    var showKind = true
    /// 1-based position, shown on the trailing edge (recap only).
    var index: Int? = nil
    /// Dim earlier links that are scrolling off the top of the stack.
    var dimmed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if showKind {
                Text(node.kind.tileLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Color.onAccent.opacity(0.5))
            }
            Text(node.displayName)
                .font(.system(.subheadline, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(Theme.Color.onAccent)
            Spacer(minLength: 0)
            if let index {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.onAccent.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(node.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
        .opacity(dimmed ? 0.32 : 1)
    }
}

// MARK: - Shake effect
//
// A horizontal wobble used to reject a wrong answer — the input physically
// shakes "no". Driven by a `GeometryEffect` so it animates the offset without
// disturbing layout. Bump `trigger` (an incrementing counter) to fire one shake.

struct Shake: GeometryEffect {
    var animatableData: CGFloat
    var amplitude: CGFloat = 8
    var shakes: CGFloat = 3

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amplitude * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

extension View {
    /// Shakes the view once whenever `trigger` changes.
    func shake(_ trigger: Int) -> some View {
        modifier(ShakeOnChange(trigger: trigger))
    }
}

private struct ShakeOnChange: ViewModifier {
    let trigger: Int
    @State private var amount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(Shake(animatableData: amount))
            .onChange(of: trigger) {
                amount = 0
                withAnimation(.linear(duration: 0.4)) { amount = 1 }
            }
    }
}

// MARK: - Floating gain
//
// The "+N" that pops off the score and drifts upward on a correct link. Re-run
// by giving it a fresh `.id` each time (so `onAppear` fires again).

struct FloatingGain: View {
    let value: Int
    @State private var rise = false

    var body: some View {
        Text("+\(value)")
            .font(.system(.subheadline, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Theme.Color.good)
            .opacity(rise ? 0 : 1)
            .offset(y: rise ? -34 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { rise = true }
            }
    }
}

// MARK: - Staggered appear
//
// Fades + lifts a view in on its first appearance, delayed by its position, so a
// group of siblings assembles one-after-another instead of all at once. Drives
// the seed intro's control reveal and the Reel grid tiles from one place, so the
// stagger feel is identical everywhere. Honors Reduce Motion (shows instantly).
// Because it fires on `onAppear`, lazy containers stagger their rows in as they
// scroll into view for free.

struct StaggeredAppear: ViewModifier {
    let index: Int
    var step: Double = 0.03
    var cap: Int = 16
    var animation: Animation = Theme.Motion.standard
    /// How far below its resting spot the view starts (the lift distance).
    var offset: CGFloat = 10
    /// Scale the view starts at before settling to 1 — a subtle grow-into-place
    /// that reads springier than a pure fade+lift. `1` = no scale (the default,
    /// so existing callers are unchanged).
    var scaleFrom: CGFloat = 1
    /// When false, the view is shown at once with no stagger. Lets a caller keep
    /// the effect for a first-run reveal but skip it on ordinary re-insertions —
    /// e.g. the seed controls stagger during the cold-launch intro, but arrive
    /// solid on a "Play again" re-entry so they don't fight the carousel push.
    var enabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let visible = shown || !enabled
        return content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : scaleFrom, anchor: .bottom)
            .offset(y: visible ? 0 : offset)
            .onAppear {
                guard enabled, !shown else { return }
                if reduceMotion { shown = true; return }
                withAnimation(animation.delay(Double(min(index, cap)) * step)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Fade + lift this view in on appear, delayed by `index` (its position in a
    /// group) so siblings assemble in sequence. `index: 0` = no delay. Set
    /// `enabled: false` to skip the effect and show it immediately.
    func appear(_ index: Int = 0,
                animation: Animation = Theme.Motion.standard,
                step: Double = 0.03,
                offset: CGFloat = 10,
                scaleFrom: CGFloat = 1,
                enabled: Bool = true) -> some View {
        modifier(StaggeredAppear(index: index, step: step, animation: animation, offset: offset, scaleFrom: scaleFrom, enabled: enabled))
    }
}

// MARK: - Previews

#Preview("Components") {
    VStack(spacing: Theme.Spacing.md) {
        NodeTile(node: .actor(Person(id: 1, name: "Robin Wright")))
        NodeTile(node: .movie(Movie(id: 2, title: "Wonder Woman", year: 2017)))
        NodeTile(node: .movie(Movie(id: 3, title: "Forrest Gump", year: 1994)),
                 showKind: false, index: 2)

        Button("Play again") {}.buttonStyle(.primary)
        Button("Share") {}.buttonStyle(.ghost)
    }
    .padding()
    .background(Theme.Color.canvas)
}
