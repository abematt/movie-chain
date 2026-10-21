//
//  Theme.swift
//  movie-quiz
//
//  The design-token layer: the single source of truth for color, spacing, corner
//  radii, and motion. Think of `Theme` as the app's design system — views
//  reference these tokens instead of hardcoding magic numbers, so the whole app
//  can be re-tuned from one place and stays visually consistent.
//
//  The look is **Cream Neobrutalist** (0.6.0 prototype): a cream canvas, white
//  surfaces wrapped in a 2pt ink border with a hard, unblurred offset shadow,
//  one coral call-to-action, and two category accents — blue for actors,
//  yellow for movies (the most colour-blind-safe pair). See `docs/ROADMAP.md`
//  → 0.6.0; the direction is still being judged on device.
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
        static let movie = SwiftUI.Color("MovieYellow") // movie category accent
        static let primary = SwiftUI.Color("Coral")   // the coral call-to-action
        /// The hard offset shadow behind bordered surfaces. Ink in light mode; a
        /// near-black in dark mode, where the borders flip to cream.
        static let shadow = SwiftUI.Color("Shadow")
        /// Every border is ink — never tinted, never a hairline.
        static let border = ink
        static let good = SwiftUI.Color("Good")         // correct-link green
        /// Text/glyphs on a light accent (movie yellow, good green) — near-black
        /// in both themes. Actor blue is dark enough to need white instead; ask
        /// `NodeKind.onAccent` rather than picking by hand.
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

    // MARK: Borders & hard shadows (neobrutalist)
    //
    // Every bordered surface uses one border weight. Shadows are solid, unblurred
    // and offset down-right only: `small` for chrome (inputs, chips, compact
    // cards, secondary buttons), `large` for primary cards and the main CTA.
    enum Border {
        static let width: CGFloat = 2
    }

    enum Shadow {
        static let small: CGFloat = 2
        static let large: CGFloat = 4
    }

    // MARK: Type roles
    //
    // The whole type system. Three voices, nothing else:
    //   • Display — a bold serif for numerals, the wordmark and node names, with
    //     a regular italic **flourish** for the secondary word (years, "pts",
    //     "Chain" in the wordmark). The serif is the system's New York, standing
    //     in for the spec's Fraunces; swapping the font later is a change here.
    //   • Numerals — every figure in the app (scores, counts, "2 links · 89
    //     pts", the timer) is the bold serif, via `numeral`. This is the spec's
    //     card-numeral role: numbers never fall back to the sans, whatever size.
    //   • Body — the system sans at two sizes (`body`, `small`), medium weight,
    //     plus `bodyStrong` for names in rows.
    //   • Label — tiny bold uppercase tracked metadata ("ACTOR", "TIME'S UP").
    //     Always apply it with `.metaLabel()` so case and tracking can't drift.
    // Everything but the big fixed-size numerals rides a Dynamic Type text
    // style, so the app still scales with the reader's text size.
    enum Font {
        /// Big serif numerals and the wordmark (fixed size: they are the hero).
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .serif)
        }
        /// Serif heading that scales: node names, card titles, sheet heroes.
        static func heading(_ style: SwiftUI.Font.TextStyle = .title3) -> SwiftUI.Font {
            .system(style, design: .serif, weight: .bold)
        }
        /// Bold serif figures at a text-style size: counts, stats, the timer.
        static func numeral(_ style: SwiftUI.Font.TextStyle = .headline) -> SwiftUI.Font {
            .system(style, design: .serif, weight: .bold)
        }
        /// The italic flourish paired with display/heading type.
        static func flourish(_ style: SwiftUI.Font.TextStyle = .subheadline) -> SwiftUI.Font {
            .system(style, design: .serif).italic()
        }
        /// Fixed-size flourish, for the italic word beside a fixed display size.
        static func flourish(size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .serif).italic()
        }
        static let body: SwiftUI.Font = .system(.subheadline, weight: .medium)
        static let bodyStrong: SwiftUI.Font = .system(.subheadline, weight: .semibold)
        static let small: SwiftUI.Font = .system(.footnote)
        /// Uppercase tracked micro-label. Use via `.metaLabel()`.
        static let label: SwiftUI.Font = .system(.caption2, weight: .bold)
        static let labelTracking: CGFloat = 0.9
        /// Button labels: uppercase and tracked like labels, at body size.
        static let button: SwiftUI.Font = .system(.subheadline, weight: .bold)
        static let buttonTracking: CGFloat = 0.8
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
        /// The screen-to-screen carousel curve — a soft spring, damped high so a
        /// full-width directional push carries continuity without overshooting
        /// into a visible edge gap.
        static let screen: Animation = .spring(response: 0.45, dampingFraction: 0.86)
        /// The seed cold-launch reveal — the lockup rising to its header rest as
        /// the controls assemble beneath it. A shade slower than a UI spring so
        /// the entrance reads as deliberate rather than snappy.
        static let intro: Animation = .spring(response: 0.62, dampingFraction: 0.82)
        /// The staggered entrance a group of siblings rises in on (the seed
        /// controls, the Reel grid). Softer and longer-travelling than `drop`
        /// with a gentle overshoot, so — stepped tight enough that consecutive
        /// items overlap — it reads as one springy wave rather than discrete pops.
        static let cascade: Animation = .spring(response: 0.5, dampingFraction: 0.72)
    }
}

// MARK: - Screen transition
//
// The app is a one-way loop — seed → playing → gameOver → (play again) → seed —
// so every screen change is a *forward* push on a single horizontal axis: the
// new screen enters from the trailing edge while the old one leaves toward the
// leading edge. There is no "back": "Play again" is the next lap, not a retreat,
// so treating it like everything else is what keeps the motion legible. Under
// Reduce Motion the push degrades to a plain cross-fade.
extension AnyTransition {
    static func screenPush(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        )
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

    /// The category accent: blue = actor, yellow = movie.
    var accent: Color {
        switch self {
        case .actor: Theme.Color.actor
        case .movie: Theme.Color.movie
        }
    }

    /// Text/glyph colour that stays legible on this kind's accent fill.
    var onAccent: Color {
        switch self {
        case .actor: .white
        case .movie: Theme.Color.onAccent
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
