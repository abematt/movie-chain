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

// MARK: - Neo surface (the neobrutalist atom)
//
// White (or tinted) fill, a 2pt ink edge, and a hard ink side straight below
// it: thickness, not a shadow, so it never blurs and never leans. Everything
// bordered in the app — cards, buttons, inputs — is drawn by this one modifier,
// so the edge weight and side depth stay one system. `pressed` pushes the object
// down onto its side: the side collapses as the face sinks by the same amount.

struct NeoSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var fill: Color = Theme.Color.tile
    var shadow: CGFloat = Theme.Shadow.large
    var pressed = false

    func body(content: Content) -> some View {
        let depth = pressed ? 0 : shadow
        let sink: CGFloat = pressed ? shadow : 0
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            .background(shape.fill(Theme.Color.shadow).offset(y: depth))
            .offset(y: sink)
    }
}

extension View {
    /// Usage: `content.neoSurface(fill: Theme.Color.primary, shadow: Theme.Shadow.small)`
    func neoSurface(radius: CGFloat = Theme.Radius.md,
                    fill: Color = Theme.Color.tile,
                    shadow: CGFloat = Theme.Shadow.large,
                    pressed: Bool = false) -> some View {
        modifier(NeoSurface(shape: RoundedRectangle(cornerRadius: radius),
                            fill: fill, shadow: shadow, pressed: pressed))
    }
}

// MARK: - Primary button (an ink slab)
//
// The one prominent call-to-action per screen ("Play again", "Retry"). Ink
// fill with a hard side; pressing collapses the side and sinks it into the
// page. Under Reduce Motion nothing moves; the press still registers through
// the system's own highlight.

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NeoButtonBody(configuration: configuration,
                      fill: Theme.Color.primary,
                      foreground: Theme.Color.onInk,
                      shadow: Theme.Shadow.large)
    }
}

// MARK: - Slab button (in the dock)
//
// A square-shouldered slab for the dock, where the colour around it is the
// kind's: "Go" and the home's start arrow are night slabs lettered in the dock's
// colour; Retry is a white one. The same in both modes, because the dock is.

struct SlabButtonStyle: ButtonStyle {
    var fill: Color = Theme.Color.night
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        SlabBody(configuration: configuration, fill: fill, foreground: foreground)
    }

    private struct SlabBody: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let foreground: Color
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Font.button)
                .textCase(.uppercase)
                .tracking(Theme.Font.buttonTracking)
                .foregroundStyle(isEnabled ? foreground : Color(white: 0.55))
                .padding(.horizontal, Theme.Spacing.lg - 4)
                .frame(minWidth: 52, minHeight: 52)
                .neoSurface(radius: Theme.Radius.field, fill: fill,
                            shadow: Theme.Shadow.large,
                            pressed: configuration.isPressed && !reduceMotion)
                .animation(Theme.Motion.press, value: configuration.isPressed)
        }
    }
}

// MARK: - Ghost button (secondary)
//
// The quieter secondary action ("Share", "Shuffle"): white surface, ink text,
// a small 2pt shadow so it sits visibly below the primary.

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NeoButtonBody(configuration: configuration,
                      fill: Theme.Color.tile,
                      foreground: Theme.Color.ink,
                      shadow: Theme.Shadow.small)
    }
}

/// Shared body for the bordered buttons, so both read the environment (Reduce
/// Motion) and press the same way.
private struct NeoButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let foreground: Color
    let shadow: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Theme.Font.button)
            .textCase(.uppercase)
            .tracking(Theme.Font.buttonTracking)
            .padding(.horizontal, Theme.Spacing.lg - 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            // Disabled reads as "flat and empty", not as a faded copy: muted
            // fill, secondary text, no shadow — the border stays solid.
            .foregroundStyle(isEnabled ? foreground : Theme.Color.muted)
            .modifier(NeoSurface(shape: RoundedRectangle(cornerRadius: Theme.Radius.md),
                                 fill: isEnabled ? fill : Theme.Color.socket,
                                 shadow: isEnabled ? shadow : 0,
                                 pressed: configuration.isPressed && !reduceMotion))
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Dock ground
//
// The panel the colour lives in: a slab across the bottom of the screen, its top
// corners rounded and edged in ink, filled with the kind you name next (yellow for
// a movie, blue for an actor). It runs under the home indicator.

struct DockGround: View {
    var color: Color

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.dock,
                                           topTrailingRadius: Theme.Radius.dock)
        shape.fill(color)
            .overlay(shape.stroke(Theme.Color.border, lineWidth: Theme.Border.width))
            // Only the top edge shows: the sides and bottom sit just off screen.
            .padding(.horizontal, -Theme.Border.width)
            .padding(.bottom, -Theme.Border.width)
            .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Meta label
//
// The one uppercase-label recipe. Every "ACTOR", "TIME'S UP", "YOUR CHAIN" and
// section title goes through this, so size, case and tracking stay identical.

/// The spec's two label sizes: `.medium` (label-md) for section titles and
/// metadata, `.small` (label-sm) for stamps inside cards and chips.
enum MetaLabelSize { case medium, small }

extension View {
    /// Usage: `Text("Your chain").metaLabel()` · `Text("Actor").metaLabel(size: .small)`
    func metaLabel(_ color: Color = Theme.Color.muted, size: MetaLabelSize = .medium) -> some View {
        self.font(size == .medium ? Theme.Font.label : Theme.Font.labelSmall)
            .textCase(.uppercase)
            .tracking(size == .medium ? Theme.Font.labelTracking : Theme.Font.labelSmallTracking)
            .foregroundStyle(color)
    }
}

// MARK: - Node name
//
// A node's name with the movie year as a quiet sentence-weight figure
// ("Les Misérables 2012") instead of a parenthetical. One definition so every row, card and
// recap shows years the same way.

struct NodeName: View {
    let node: ChainNode
    var font: Font = Theme.Font.bodyStrong
    var yearFont: Font = Theme.Font.sentence(.subheadline)

    var body: some View {
        if case .movie(let m) = node, let year = m.year {
            Text("\(Text(m.title).font(font).foregroundStyle(Theme.Color.ink)) \(Text(String(year)).font(yearFont).foregroundStyle(Theme.Color.muted))")
        } else {
            Text(node.matchText).font(font).foregroundStyle(Theme.Color.ink)
        }
    }
}

// MARK: - Heading
//
// A title in one voice: Archivo semibold, ink. Emphasis is size, never a
// second face.

struct Heading: View {
    let text: String
    var style: Font.TextStyle = .title3

    init(_ text: String, style: Font.TextStyle = .title3) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text).font(Theme.Font.heading(style)).foregroundStyle(Theme.Color.ink)
    }
}

// MARK: - Neo segmented control
//
// The bordered segmented picker: a white neo surface holding the options, the
// selected one filled ink. Replaces the stock `Picker(.segmented)`, which
// can't take the border, shadow or label type.

struct NeoSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(Theme.Motion.standard) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(Theme.Font.button)
                        .textCase(.uppercase)
                        .tracking(Theme.Font.buttonTracking)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .foregroundStyle(selected ? Theme.Color.onInk : Theme.Color.muted)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(selected ? Theme.Color.ink : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
    }
}

// MARK: - Sheet chrome (the spec's top app bar)
//
// Cream bar, serif title, a 2pt ink rule under it. Applied to a sheet's
// NavigationStack content so the Reel and Settings sheets match the app
// instead of showing the stock translucent bar.

extension View {
    func neoNavigationBar<Title: View>(@ViewBuilder title: () -> Title) -> some View {
        self
            .toolbarBackground(Theme.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .principal) { title() } }
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle().fill(Theme.Color.border).frame(height: Theme.Border.width)
            }
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
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(Theme.Motion.press, value: configuration.isPressed)
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
// Wraps content in a padded neo surface — the standard way to visually cluster
// related content (the game-over near-miss uses it).

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .neoSurface(radius: Theme.Radius.card)
    }
}

extension View {
    /// Usage: `someView.card()`
    func card() -> some View { modifier(CardModifier()) }
}

// MARK: - Node dot
//
// A small category chip (blue = actor, yellow = movie) used where a full tile
// would be too heavy — seed results, the "what comes next" hint.

struct NodeDot: View {
    let kind: NodeKind
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(kind.accent)
            .overlay(Circle().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
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
                    .metaLabel(node.kind.onAccent.opacity(0.7), size: .small)
            }
            Text(node.displayName)
                .font(Theme.Font.bodyStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(node.kind.onAccent)
            Spacer(minLength: 0)
            if let index {
                Text("\(index)")
                    .monospacedDigit()
                    .metaLabel(node.kind.onAccent.opacity(0.6), size: .small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoSurface(radius: Theme.Radius.tile, fill: node.accent, shadow: Theme.Shadow.small)
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
    /// Half-swings across the shake; an even count ends back at rest.
    var shakes: CGFloat = 4

    func effectValue(size: CGSize) -> ProjectionTransform {
        // The swing decays to nothing, so the shake settles instead of stopping
        // dead mid-swing like a constant-amplitude wobble does.
        let t = animatableData
        let translation = amplitude * (1 - t) * sin(t * .pi * shakes)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(Shake(animatableData: amount))
            .onChange(of: trigger) {
                // Reduce Motion: no shake. The caller carries the rejection with a
                // non-moving cue instead (GameView flashes the field's border).
                guard !reduceMotion else { return }
                amount = 0
                // Linear on purpose: the decay lives in `Shake`, so time must be even.
                withAnimation(.linear(duration: 0.35)) { amount = 1 }
            }
    }
}

// MARK: - Floating gain
//
// The "+N" that pops off the score and drifts upward on a correct link. Re-run
// by giving it a fresh `.id` each time (so `onAppear` fires again).

struct FloatingGain: View {
    let value: Int
    @State private var shown = false
    @State private var rise = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("+\(value)")
            .font(Theme.Font.numeral(.subheadline))
            .monospacedDigit()
            .foregroundStyle(Theme.Color.good)
            .opacity(shown && !rise ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.85, anchor: .bottom)
            .offset(y: rise && !reduceMotion ? -34 : 0)
            // Two beats: pop in fast, hold long enough to be read, then drift off.
            // Under Reduce Motion it only fades in and out, in place.
            .task {
                withAnimation(.easeOut(duration: 0.12)) { shown = true }
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.55)) { rise = true }
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
    /// Extra delay before the whole group starts, in seconds — e.g.
    /// `Theme.Motion.screenSettle`, so a recap on a screen that is still pushing
    /// in starts as the push lands rather than underneath it.
    var after: Double = 0

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
                withAnimation(animation.delay(after + Double(min(index, cap)) * step)) {
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
                enabled: Bool = true,
                after: Double = 0) -> some View {
        modifier(StaggeredAppear(index: index, step: step, animation: animation, offset: offset, scaleFrom: scaleFrom, enabled: enabled, after: after))
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
