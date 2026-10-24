//
//  Theme.swift
//  movie-quiz
//
//  The design-token layer: the single source of truth for color, spacing, corner
//  radii, and motion. Think of `Theme` as the app's design system — views
//  reference these tokens instead of hardcoding magic numbers, so the whole app
//  can be re-tuned from one place and stays visually consistent.
//
//  The look is **Ground & Object**: a paper ground, white objects with an ink
//  edge and a hard ink side (thickness, not a shadow), and two category
//  colours — blue for actors, yellow for movies (the most colour-blind-safe
//  pair) — that live on objects and in the answer dock, never on the ground.
//  One family, three widths: Archivo for names and sentences, condensed black
//  Archivo for numbers and actions, JetBrains Mono caps for chips and card
//  numbers. No serif, no italics. It replaced 0.5.0's Cream Neobrutalist; the
//  canvas that specs it is linked from `docs/ROADMAP.md`.
//  Color is defined in the asset catalog (light + dark variants) so light/dark
//  adaptation and Dynamic Type come for free; `Theme.Color` just names them.
//  Dark is a dim room, not a black one: the ground lifts, and black stays the
//  side and the edge, so objects keep their weight.
//

import SwiftUI
import UIKit
import CoreText

enum Theme {

    // MARK: Color — Ground & Object (defined in Assets.xcassets)
    //
    // Every colour is a token with a light and a dark value. Secondary text uses
    // `muted`, not Apple's translucent `.secondary`, so it is the same solid grey
    // everywhere.
    enum Color {
        static let canvas = SwiftUI.Color("Canvas")     // the paper ground
        static let ink = SwiftUI.Color("Ink")           // text, filled controls
        static let tile = SwiftUI.Color("Tile")         // objects: cards, pills, fields
        static let hairline = SwiftUI.Color("Hairline") // thin rules
        /// Empty places: an unlit disc, the timer's track, a loading placeholder.
        static let socket = SwiftUI.Color("Socket")
        /// Blue and yellow are objects, so they don't change with the mode.
        static let actor = SwiftUI.Color("ActorBlue")
        static let movie = SwiftUI.Color("MovieYellow")
        /// The call to action is an ink slab; the colour is saved for the dock.
        static let primary = ink
        /// Game over and the share card: always this dark, whatever the mode.
        static let night = SwiftUI.Color("Night")
        /// Play again, on Night only.
        static let go = SwiftUI.Color("Go")
        /// Secondary text: metadata, hints, years.
        static let muted = SwiftUI.Color("Muted")
        /// Errors and the low-time warning.
        static let danger = SwiftUI.Color("Danger")
        /// An object's side: a hard ink offset straight down, never a blur. Black
        /// in both modes' darkest sense — ink in light, true black in dark.
        static let shadow = SwiftUI.Color("Shadow")
        /// An object's edge. Same as the side, so edge and side read as one solid
        /// in dark mode too, where the ink (text) turns light but objects don't.
        static let border = shadow
        static let good = SwiftUI.Color("Good")         // correct-link green
        /// Text/glyphs on a light accent (movie yellow, good green) — near-black
        /// in both themes. Actor blue is dark enough to need white instead; ask
        /// `NodeKind.onAccent` rather than picking by hand.
        static let onAccent = SwiftUI.Color("OnAccent")
        /// Text/glyphs on an ink-filled control — inverts with the theme, which
        /// is exactly what `canvas` does (white on light, near-black on dark).
        static let onInk = canvas

        // Fixed greys for surfaces that don't change with the mode (Night, the
        // paper field in the dock), so they live here rather than in the catalog.
        /// Secondary text on Night: game over's quiet lines, the offline dock.
        static let quietOnNight = SwiftUI.Color(white: 0.74)
        /// A disabled slab's label (the dock's Go before anything is typed).
        static let disabledSlabText = SwiftUI.Color(white: 0.55)
        /// The placeholder in the dock's paper field, in both modes.
        static let fieldPlaceholder = SwiftUI.Color(white: 0.42)
        /// The share card's hairline rules on Night.
        static let ruleOnNight = SwiftUI.Color(white: 0.35)
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

    // MARK: Edges & sides
    //
    // Every object has one edge weight and a hard ink side straight below it —
    // thickness, never a blur or a lean. The deeper the side, the heavier the
    // object: `small` for pills, chips and inputs, `large` for buttons, `card`
    // for the cards that hold the game.
    enum Border {
        static let width: CGFloat = 2
    }

    enum Shadow {
        static let small: CGFloat = 4
        static let large: CGFloat = 6
        static let card: CGFloat = 10
    }

    // MARK: Type roles
    //
    // One family, three widths, plus mono caps — bundled in `Fonts/` as static
    // cuts of the Archivo and JetBrains Mono variable fonts:
    //   • Names and sentences — Archivo at its normal width. A name is semibold
    //     (`heading`), a sentence regular (`sentence`): "Gary Sinise / was in".
    //   • Numbers and actions — Archivo condensed: black for figures (`display`,
    //     `numeral`), extra-bold uppercase for buttons. Scale is the drama.
    //   • Labels — JetBrains Mono bold caps, for chips and card numbers only.
    //     Always through `.metaLabel()` so case and tracking can't drift.
    // No serif and no italics: emphasis is size and weight, one voice per line.
    // Everything except the big fixed-size numerals rides a Dynamic Type text
    // style (`relativeTo:`), so the app still scales with the reader's size.
    enum Font {
        /// Big condensed figures: the score, the game-over count (fixed size:
        /// they are the hero).
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            custom("ArchivoCondensed-Black", fixed: size)
        }
        /// A name at a fixed size: the home sentence's dealt start.
        static func name(size: CGFloat) -> SwiftUI.Font {
            custom("Archivo-SemiBold", fixed: size)
        }
        /// A sentence at a fixed size, beside a fixed display size.
        static func sentence(size: CGFloat) -> SwiftUI.Font {
            custom("Archivo-Regular", fixed: size)
        }
        /// A name or title that scales: node names, card titles, sheet heroes.
        static func heading(_ style: SwiftUI.Font.TextStyle = .title3) -> SwiftUI.Font {
            custom("Archivo-SemiBold", style: style)
        }
        /// Condensed black figures at a text-style size: counts, stats, the timer.
        static func numeral(_ style: SwiftUI.Font.TextStyle = .headline) -> SwiftUI.Font {
            custom("ArchivoCondensed-Black", style: style)
        }
        /// The quiet half of a sentence ("was in", a year, "pts"): regular weight,
        /// set apart by colour, never by slant.
        static func sentence(_ style: SwiftUI.Font.TextStyle = .subheadline) -> SwiftUI.Font {
            custom("Archivo-Regular", style: style)
        }
        static let body: SwiftUI.Font = custom("Archivo-Medium", style: .subheadline)
        static let bodyStrong: SwiftUI.Font = custom("Archivo-SemiBold", style: .subheadline)
        static let small: SwiftUI.Font = custom("Archivo-Regular", style: .footnote)
        /// Section titles and metadata ("TIME'S UP", "YOUR CHAIN").
        static let label: SwiftUI.Font = custom("JetBrainsMono-Bold", style: .caption)
        static let labelTracking: CGFloat = 1
        /// Stamps in chips and cards ("ACTOR", "NEW", "+2 EARLIER").
        static let labelSmall: SwiftUI.Font = custom("JetBrainsMono-Bold", style: .caption2)
        static let labelSmallTracking: CGFloat = 1
        /// Stamps printed on a Reel card ("NO. 027", "NEW"). Fixed, not Dynamic
        /// Type: cards are drawn at one design size and scaled as a picture.
        static let cardStamp: SwiftUI.Font = custom("JetBrainsMono-Bold", fixed: 7)
        /// Button labels: condensed extra-bold caps.
        static let button: SwiftUI.Font = custom("ArchivoCondensed-ExtraBold", style: .title3)
        static let buttonTracking: CGFloat = 1
        /// The deck card's name tracking: a touch tight at title2, as the home
        /// sentence's name is at its 50pt (−1.5).
        static let deckNameTracking: CGFloat = -0.3
        /// The coin stack's labels. Fixed: the stack is a picture with its own
        /// accessibility label, and scaled labels truncated to "Le…" at large sizes.
        static let coinLabel: SwiftUI.Font = custom("Archivo-Regular", fixed: 13)

        /// The largest text size the game screens (home, play, game over) follow.
        /// Their geometry is fixed — the deck's cards and peeks, the dock, the hero
        /// numerals — and at accessibility sizes the play screen clipped the name
        /// you were naming from. The Reel and Settings sheets aren't capped.
        static let gameTypeCap: DynamicTypeSize = .xxxLarge
        /// `gameTypeCap` in UIKit terms, for type sized with `UIFontMetrics`.
        static let gameTypeCapCategory: UIContentSizeCategory = .extraExtraExtraLarge

        // MARK: Plumbing

        private static func custom(_ name: String, fixed size: CGFloat) -> SwiftUI.Font {
            _ = FontRegistry.registered
            return .custom(name, fixedSize: size)
        }

        private static func custom(_ name: String, style: SwiftUI.Font.TextStyle) -> SwiftUI.Font {
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
        /// Fields and the slab buttons beside them.
        static let field: CGFloat = 14
        /// The answer dock's top corners.
        static let dock: CGFloat = 26
        static let pill: CGFloat = 999
    }

    // MARK: Holographic foil
    //
    // The iridescent stops a `HoloSticker` sweeps through as the phone tilts.
    // Deliberately the same in light and dark: foil is a material, not a surface
    // colour, so it doesn't invert — text on it uses `Color.onAccent`, which is
    // legible on pastels in both themes.
    enum Holo {
        /// The new-best sky: the foil laid flat as a ground, lilac at the top to
        /// lemon at the foot. Used once, on the game over that beats a record.
        static let sky: [SwiftUI.Color] = [
            SwiftUI.Color(red: 0.73, green: 0.66, blue: 1.00),
            SwiftUI.Color(red: 0.89, green: 0.71, blue: 1.00),
            SwiftUI.Color(red: 1.00, green: 0.71, blue: 0.90),
            SwiftUI.Color(red: 1.00, green: 0.89, blue: 0.72),
            SwiftUI.Color(red: 1.00, green: 0.95, blue: 0.66),
        ]
        static let colors: [SwiftUI.Color] = [
            SwiftUI.Color(red: 1.00, green: 0.71, blue: 0.90),  // pink
            SwiftUI.Color(red: 0.79, green: 0.72, blue: 1.00),  // lilac
            SwiftUI.Color(red: 0.66, green: 0.91, blue: 1.00),  // cyan
            SwiftUI.Color(red: 0.73, green: 0.96, blue: 0.82),  // mint
            SwiftUI.Color(red: 1.00, green: 0.95, blue: 0.66),  // lemon
            SwiftUI.Color(red: 1.00, green: 0.71, blue: 0.90),  // pink again, so the sweep wraps
        ]
    }

    // MARK: Motion
    //
    // Centralizing animation curves keeps transitions feeling like one system.
    // `drop` is the spring a new chain tile falls in on — the Tetris "landing"
    // that replaced the old flame leap.
    enum Motion {
        /// The default UI change. Explicitly short: the bare `.snappy` is a 0.5s
        /// spring, past the 300ms a UI change should take.
        static let standard: Animation = .snappy(duration: 0.25)
        /// Movement with a little life in it. Never for a colour or a selection
        /// fill — a colour can't bounce; use `colorChange`.
        static let emphasized: Animation = .bouncy(duration: 0.4)
        /// A colour or fill changing in place.
        static let colorChange: Animation = .easeOut(duration: 0.2)
        /// How far a pressed control shrinks — one value, so presses agree.
        static let pressScale: CGFloat = 0.97
        /// Seen on every correct link, so the overshoot stays small: enough to
        /// read as a landing, not so much that the whole stack wobbles each turn.
        static let drop: Animation = .spring(duration: 0.35, bounce: 0.2)
        /// Press feedback on every tappable surface — fast enough to feel like the
        /// control heard the finger (100–160ms), one value so presses all agree.
        static let press: Animation = .snappy(duration: 0.14)
        /// What a movement animation becomes under Reduce Motion: a short
        /// cross-fade, so state changes still read without anything travelling.
        static let reducedFade: Animation = .easeOut(duration: 0.2)
        /// How long the screen push takes to visually settle; content that
        /// cascades in on a new screen waits this long so it isn't lost under the
        /// push.
        static let screenSettle: Double = 0.3
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
        /// The home → play handoff: the sentence's pieces flying into the start
        /// card and the dock. A spring sampled by the flight's own clock (see
        /// `HandoffFlight`), with no bounce — an overshoot would carry the copies
        /// past the real views they hand to. It plays at the start of every run,
        /// so it stays short: the movement is done by ~0.4s, and by
        /// `handoffDuration` it is within a point of landing, when the real views
        /// take over (and the first turn's clock starts).
        static let handoffSpring = Spring(duration: 0.45, bounce: 0)
        static let handoffDuration: Double = 0.55
        /// A lifted Reel card's tilt coming alive once it has settled — gentle,
        /// unbouncy. Like the handoff, sampled on its own clock (`CardTilt`), so
        /// the gyro's per-frame writes can't cancel it.
        static let tiltIn = Spring(duration: 0.35, bounce: 0)
        /// The tilt flattening as the card goes home; done inside the 0.28s
        /// flight so the card lands flat on its slot.
        static let tiltOut = Spring(duration: 0.18, bounce: 0)
        /// A dragged card swinging back level when let go — carries the flick,
        /// with a small settle (a playful object, so a touch of bounce).
        static let tiltRelease = Spring(duration: 0.5, bounce: 0.15)
        /// One layout making way for another — home → play under the handoff,
        /// deal ⇄ search, the search's empty state ⇄ its results: the old content
        /// gone fast, the new arriving a beat later, so two full-height layouts
        /// never sit half-faded over each other. A strong ease-out (the built-in
        /// one starts too gently for an arrival).
        static let layoutOut: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.15)
        static let layoutIn: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.25).delay(0.1)
        /// How long the search flow takes to land, before its field takes focus:
        /// the keyboard rising mid-swap re-lays out whatever is still fading.
        static let swapSettle: Duration = .milliseconds(300)
        /// A start leaving on Deal again: quicker than the new one lands, so it is
        /// out of the way rather than competing with it.
        static let dealOut: Animation = .snappy(duration: 0.22)
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
// Registers the bundled Archivo and JetBrains Mono cuts with Core Text once per
// process, the first time any font token is asked for. Done in code (not
// `UIAppFonts`) because the target generates its Info.plist, and so SwiftUI
// previews get the fonts too.

enum FontRegistry {
    static let registered: Void = {
        let names = ["Archivo-Regular", "Archivo-Medium", "Archivo-SemiBold", "Archivo-Bold",
                     "ArchivoCondensed-ExtraBold", "ArchivoCondensed-Black", "JetBrainsMono-Bold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
