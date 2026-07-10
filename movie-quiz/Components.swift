//
//  Components.swift
//  movie-quiz
//
//  Reusable view primitives built on the `Theme` tokens. These are the app's
//  equivalent of a component library (shadcn/ui, in React terms): small, owned,
//  composable pieces that encapsulate a look so screens stay declarative and
//  consistent.
//
//  The idiomatic SwiftUI building blocks used here:
//    • `ButtonStyle`   — reusable button appearance + press feedback
//    • `ViewModifier`  — reusable "wrap this content in a styled container"
//    • small `View`s   — reusable widgets (a chain pill, a node glyph)
//

import SwiftUI

// MARK: - Primary button
//
// One prominent call-to-action style ("Play again", "Start"). Fills its width,
// uses the app tint, and gives tactile press feedback (scale + dim) — the small
// details that make a control feel native and responsive.

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(.tint, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// Usage: `.buttonStyle(.primary)`
    static var primary: PrimaryButtonStyle { .init() }
}

// MARK: - Card container
//
// Wraps content in a padded, grouped-background surface with a soft rounded
// edge — the standard way to visually cluster related content. Uses
// `.background(...)` semantic material so it adapts to light/dark.

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .background(
                .background.secondary,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card)
            )
    }
}

extension View {
    /// Usage: `someView.card()`
    func card() -> some View { modifier(CardModifier()) }
}

// MARK: - Node glyph
//
// The circular, tinted icon that represents an actor or a movie. Centralizes
// the "colored circle + symbol" look so it's identical everywhere a node shows
// up. `size` scales the whole thing proportionally.

struct NodeGlyph: View {
    let kind: NodeKind
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(kind.accent)
            .frame(width: size, height: size)
            .background(kind.accent.opacity(0.15), in: Circle())
    }
}

// MARK: - Chain pill
//
// One link in the chain trail: a capsule tag carrying the node's icon + name,
// tinted by node kind. Reused in the play screen's horizontal trail.

struct ChainPill: View {
    let node: ChainNode

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: node.symbol)
                .font(.caption2)
            Text(node.displayName)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(node.accent)
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(node.accent.opacity(0.12), in: Capsule())
    }
}

// MARK: - Shake effect
//
// A horizontal wobble used to reject a wrong answer — the input physically
// shakes "no". Driven by a `GeometryEffect` so it animates the offset without
// disturbing layout. Bump `animatableData` (an incrementing counter, animated)
// to fire one shake.

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
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(.green)
            .opacity(rise ? 0 : 1)
            .offset(y: rise ? -52 : -6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.85)) { rise = true }
            }
    }
}

// MARK: - Confetti
//
// A lightweight celebratory burst for a new best chain. A handful of emoji fall
// and scatter once on appear — no assets, no dependency, self-contained.

struct ConfettiView: View {
    var pieces = 28
    private let emojis = ["🎬", "🍿", "⭐️", "🔥", "🎉", "🏆"]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<pieces, id: \.self) { i in
                    ConfettiPiece(
                        emoji: emojis[i % emojis.count],
                        startX: CGFloat.random(in: 0...geo.size.width),
                        endX: CGFloat.random(in: 0...geo.size.width),
                        fall: geo.size.height,
                        delay: Double.random(in: 0...0.5),
                        spin: Double.random(in: -220...220)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ConfettiPiece: View {
    let emoji: String
    let startX: CGFloat
    let endX: CGFloat
    let fall: CGFloat
    let delay: Double
    let spin: Double

    @State private var animate = false

    var body: some View {
        Text(emoji)
            .font(.system(size: 26))
            .position(x: animate ? endX : startX, y: animate ? fall + 40 : -40)
            .rotationEffect(.degrees(animate ? spin : 0))
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: 1.6).delay(delay)) { animate = true }
            }
    }
}

// MARK: - Previews

#Preview("Components") {
    VStack(spacing: Theme.Spacing.lg) {
        HStack(spacing: Theme.Spacing.md) {
            NodeGlyph(kind: .actor)
            NodeGlyph(kind: .movie)
            NodeGlyph(kind: .movie, size: 64)
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Card container").font(.headline)
            Text("Groups related content on an adaptive surface.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        Button("Play again") {}
            .buttonStyle(.primary)
    }
    .padding()
    .tint(.indigo)
}
