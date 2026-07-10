//
//  Theme.swift
//  movie-quiz
//
//  The design-token layer: the single source of truth for spacing, corner
//  radii, and typography. Think of `Theme` as the app's design system — views
//  reference these tokens instead of hardcoding magic numbers, so the whole app
//  can be re-tuned from one place and stays visually consistent.
//
//  Why a token layer at all? Hardcoded values (`.padding(13)`, `.font(.system(
//  size: 22))`) are the #1 tell of an ad-hoc UI: they drift, they don't scale
//  with Dynamic Type, and they break in dark mode. Everything here is built on
//  Apple's *semantic* primitives (system fonts, semantic colors, the 8-pt grid)
//  so accessibility and light/dark adaptation come for free.
//

import SwiftUI

enum Theme {

    // MARK: Spacing — an 8-pt rhythm (Apple's implicit grid)
    //
    // Reference these instead of literal numbers so vertical/horizontal rhythm
    // stays consistent. `md` (16) is the workhorse; it matches SwiftUI's own
    // default padding.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Corner radii
    //
    // A small, deliberate set. `card` is the standard container; `pill` is the
    // fully-rounded capsule look used for chain links and tags.
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let card: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: Motion
    //
    // Centralizing animation curves keeps transitions feeling like one system.
    // `.snappy` is Apple's spring for most UI; `bouncy` is for celebratory
    // moments (a correct answer, a new high score).
    enum Motion {
        static let standard: Animation = .snappy
        static let emphasized: Animation = .bouncy(duration: 0.4)
    }
}

// MARK: - Node visual identity
//
// Actors and movies each get a consistent icon + accent everywhere they appear
// (seed list, current-node hero, chain trail, game-over recap). This extension
// is the single definition — previously the `person.fill` / `film` mapping was
// duplicated as an inline closure in three different views. Change it once here
// and every screen updates.

extension NodeKind {
    /// SF Symbol representing this kind of node.
    var symbol: String {
        switch self {
        case .actor: "person.fill"
        case .movie: "film.fill"
        }
    }

    /// A distinct accent per node kind, so the eye can tell actor-links from
    /// movie-links at a glance. Uses system-provided colors that adapt to
    /// light/dark and accessibility contrast automatically.
    var accent: Color {
        switch self {
        case .actor: .orange
        case .movie: .indigo
        }
    }
}

extension ChainNode {
    /// The kind of *this* node (as opposed to `nextKind`, which is what must
    /// come next). Lets any view ask a node for its own icon/color.
    var kind: NodeKind {
        switch self {
        case .actor: .actor
        case .movie: .movie
        }
    }

    var symbol: String { kind.symbol }
    var accent: Color { kind.accent }
}
