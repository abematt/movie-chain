//
//  Theme.swift
//  movie-quiz
//
//  The design-token layer: the single source of truth for color, spacing, corner
//  radii, and motion. Think of `Theme` as the app's design system — views
//  reference these tokens instead of hardcoding magic numbers, so the whole app
//  can be re-tuned from one place and stays visually consistent.
//
//  The look is an editorial, puzzle-page treatment (NYT Games / Connections):
//  paper-warm neutrals, near-black ink, and two "category" accents — blue for
//  actors, purple for movies — used the way Connections uses its group colors.
//  Color is defined in the asset catalog (light + dark variants) so light/dark
//  adaptation and Dynamic Type come for free; `Theme.Color` just names them.
//

import SwiftUI

enum Theme {

    // MARK: Color — the warm-paper palette (defined in Assets.xcassets)
    //
    // Surfaces and accents are custom (the warm greys and the two category
    // hues are the identity). Muted text still uses Apple's semantic
    // `.secondary`/`.tertiary` so it tracks accessibility contrast.
    enum Color {
        static let canvas = SwiftUI.Color("Canvas")     // page background
        static let ink = SwiftUI.Color("Ink")           // primary text / filled controls
        static let tile = SwiftUI.Color("Tile")         // warm unselected surface
        static let hairline = SwiftUI.Color("Hairline") // thin rules
        static let actor = SwiftUI.Color("ActorBlue")   // actor category accent
        static let movie = SwiftUI.Color("MoviePurple") // movie category accent
        static let good = SwiftUI.Color("Good")         // correct-link green
        /// Text/glyphs that sit on a pastel accent tile — always near-black in
        /// both themes (the pastels are light in dark mode too).
        static let onAccent = SwiftUI.Color("OnAccent")
        /// Text/glyphs on an ink-filled control — inverts with the theme, which
        /// is exactly what `canvas` does (white on light, near-black on dark).
        static let onInk = canvas
    }

    // MARK: Spacing — an 8-pt rhythm (Apple's implicit grid)
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
    // `tile` is the squared-off Connections tile; `card`/`pill` remain for
    // grouped surfaces and capsules.
    enum Radius {
        static let tile: CGFloat = 8
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let card: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: Motion
    //
    // Centralizing animation curves keeps transitions feeling like one system.
    // `drop` is the spring a new chain tile falls in on — the Tetris "landing"
    // that replaced the old flame leap.
    enum Motion {
        static let standard: Animation = .snappy
        static let emphasized: Animation = .bouncy(duration: 0.4)
        static let drop: Animation = .spring(response: 0.34, dampingFraction: 0.62)
    }
}

// MARK: - Node visual identity
//
// Actors and movies each get a consistent accent + label everywhere they appear
// (seed results, the chain stack, the game-over recap). This extension is the
// single definition — change it once here and every screen updates.

extension NodeKind {
    /// SF Symbol representing this kind of node (used where an icon still reads
    /// better than a color chip).
    var symbol: String {
        switch self {
        case .actor: "person.fill"
        case .movie: "film.fill"
        }
    }

    /// The category accent: blue = actor, purple = movie (Connections-style).
    var accent: Color {
        switch self {
        case .actor: Theme.Color.actor
        case .movie: Theme.Color.movie
        }
    }

    /// Short uppercase label stamped on a chain tile ("ACTOR" / "MOVIE").
    var tileLabel: String {
        switch self {
        case .actor: "ACTOR"
        case .movie: "MOVIE"
        }
    }
}

extension ChainNode {
    /// The kind of *this* node (as opposed to `nextKind`, which is what must
    /// come next). Lets any view ask a node for its own accent/label.
    var kind: NodeKind {
        switch self {
        case .actor: .actor
        case .movie: .movie
        }
    }

    var symbol: String { kind.symbol }
    var accent: Color { kind.accent }
}
