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
