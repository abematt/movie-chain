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
import CoreText

enum Theme {

    // MARK: Color — the warm-paper palette (defined in Assets.xcassets)
    //
    // Every colour is a spec token with a light and a dark value. Secondary
    // text uses `muted` (the spec's on-surface-variant), not Apple's translucent
    // `.secondary`, so it is the same solid grey everywhere.
    enum Color {
        static let canvas = SwiftUI.Color("Canvas")     // page background
        static let ink = SwiftUI.Color("Ink")           // primary text / filled controls
        static let tile = SwiftUI.Color("Tile")         // warm unselected surface
        static let hairline = SwiftUI.Color("Hairline") // thin rules
        static let actor = SwiftUI.Color("ActorBlue")   // actor category accent
        static let movie = SwiftUI.Color("MovieYellow") // movie category accent
        static let primary = SwiftUI.Color("Coral")   // the coral call-to-action
        static let primaryPressed = SwiftUI.Color("CoralPressed") // coral while held
        /// Secondary text: metadata, hints, years (the spec's on-surface-variant).
        static let muted = SwiftUI.Color("Muted")
        /// Errors and the low-time warning (the spec's error red).
        static let danger = SwiftUI.Color("Danger")
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
        /// The spec's screen gutter: horizontal padding at every screen edge.
        static let gutter: CGFloat = 24
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
    // Three voices, nothing else:
    //   • Serif — **Fraunces**, bundled in `Fonts/` as four static cuts: bold and
    //     italic at a 72pt optical size (`FrauncesDisplay-*`, for the big fixed
    //     display type) and at a 24pt optical size (`FrauncesText-*`, for
    //     headings, names and numerals). Fraunces reshapes its letters by size,
    //     so each size gets the cut drawn for it. Bold carries display, headings
    //     and every figure (`numeral` — the spec's card-numeral role); the italic
    //     is the **flourish** word (years, "pts", "Chain" in the wordmark).
    //   • Sans — the system font (SF) for body, buttons and labels. The spec says
    //     Inter; on iOS, SF is the native equivalent and handles Dynamic Type and
    //     Bold Text natively, so it stands in deliberately.
    //   • Labels — tiny bold uppercase tracked metadata, in the spec's two sizes
    //     (`label` = label-md, `labelSmall` = label-sm). Always apply them with
    //     `.metaLabel()` so case and tracking can't drift.
    // Deliberate deviation from the spec: everything except the big fixed-size
    // numerals and the wordmark rides a Dynamic Type text style (`relativeTo:`),
    // so the app still scales with the reader's text size.
    enum Font {
        /// Big serif numerals and the wordmark (fixed size: they are the hero).
        /// Large sizes use the display cut; smaller fixed sizes the text cut.
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            serif(size >= 40 ? "FrauncesDisplay-Bold" : "FrauncesText-Bold", fixed: size)
        }
        /// Fixed-size flourish, for the italic word beside a fixed display size.
        static func flourish(size: CGFloat) -> SwiftUI.Font {
            serif(size >= 40 ? "FrauncesDisplay-Italic" : "FrauncesText-Italic", fixed: size)
        }
        /// Serif heading that scales: node names, card titles, sheet heroes.
        static func heading(_ style: SwiftUI.Font.TextStyle = .title3) -> SwiftUI.Font {
            serif("FrauncesText-Bold", style: style)
        }
        /// Bold serif figures at a text-style size: counts, stats, the timer.
        static func numeral(_ style: SwiftUI.Font.TextStyle = .headline) -> SwiftUI.Font {
            serif("FrauncesText-Bold", style: style)
        }
        /// The italic flourish paired with display/heading type.
        static func flourish(_ style: SwiftUI.Font.TextStyle = .subheadline) -> SwiftUI.Font {
            serif("FrauncesText-Italic", style: style)
        }
        static let body: SwiftUI.Font = .system(.subheadline, weight: .medium)
        static let bodyStrong: SwiftUI.Font = .system(.subheadline, weight: .semibold)
        static let small: SwiftUI.Font = .system(.footnote)
        /// label-md: section titles and metadata ("TIME'S UP", "YOUR CHAIN").
        static let label: SwiftUI.Font = .system(.caption, weight: .bold)
        static let labelTracking: CGFloat = 0.75      // ≈ 0.06em at 12pt
        /// label-sm: in-card stamps ("ACTOR", "NEW", "+2 EARLIER").
        static let labelSmall: SwiftUI.Font = .system(.caption2, weight: .bold)
        static let labelSmallTracking: CGFloat = 0.9  // ≈ 0.08em at 11pt
        /// Button labels: uppercase and tracked like labels, at body size.
        static let button: SwiftUI.Font = .system(.subheadline, weight: .bold)
        static let buttonTracking: CGFloat = 0.8

        // MARK: Fraunces plumbing

        private static func serif(_ name: String, fixed size: CGFloat) -> SwiftUI.Font {
            _ = FontRegistry.registered
            return .custom(name, fixedSize: size)
        }

        private static func serif(_ name: String, style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
            _ = FontRegistry.registered
            return .custom(name, size: baseSize(style), relativeTo: style)
        }

        /// The default (Large) point size of each text style, so a custom font
        /// starts at the same size the system font would and scales from there.
        private static func baseSize(_ style: SwiftUI.Font.TextStyle) -> CGFloat {
            switch style {
            case .largeTitle: 34
            case .title: 28
            case .title2: 22
            case .title3: 20
            case .headline, .body: 17
            case .callout: 16
            case .subheadline: 15
            case .footnote: 13
            case .caption: 12
            case .caption2: 11
            default: 17
            }
        }
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

// MARK: - Font registration
//
// Registers the bundled Fraunces cuts with Core Text once per process, the first
// time any serif token is asked for. Done in code (not `UIAppFonts`) because the
// target generates its Info.plist, and so SwiftUI previews get the fonts too.

enum FontRegistry {
    static let registered: Void = {
        let names = ["FrauncesDisplay-Bold", "FrauncesDisplay-Italic",
                     "FrauncesText-Bold", "FrauncesText-Italic"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
