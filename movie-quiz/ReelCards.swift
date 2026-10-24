//
//  ReelCards.swift
//  movie-quiz
//
//  Your Reel as a collection. An actor is a playing card earned through the
//  films you've linked *through them*; a movie is a poster in a frame, hung like
//  one at home. Either one lifts out and flips over to what's behind it: an
//  actor's films, or a movie's actors — a reverse reference with no progress,
//  since a cast runs to extras and could never be completed.
//
//  An actor card's front carries only its collector number — the order you
//  first linked them in, a set number rather than a score — and five dots of
//  progress toward holo; no counts. Its photo is printed in the actor's own
//  duotone (`Duotone`), and its face is paper, then that pastel, then holo foil:
//  the finish is the reward. Cards and frames are drawn once, at their grid size, and scaled to whatever size
//  they're shown at (`ReelCanvas`) — so lifting one is a pure zoom, the same
//  picture brought closer, with nothing re-flowing on the way.
//

import SwiftUI

// MARK: - Tiers (pure)

/// The finish a card is printed in, lowest first.
enum ReelFinish: Comparable {
    case paper, pastel, holo

    var label: String {
        switch self {
        case .paper: "Paper"
        case .pastel: "Pastel"
        case .holo: "Holo"
        }
    }
}

enum ReelTier {
    /// Films linked through an actor before their card turns pastel, then holo.
    static let pastelAt = 5
    static let holoAt = 11
    /// The progress dots on a card's name plate.
    static let dots = 5

    static func finish(links: Int) -> ReelFinish {
        if links >= holoAt { return .holo }
        return links >= pastelAt ? .pastel : .paper
    }

    /// Dots filled on the way to holo: one as soon as a film is linked, all five
    /// only at holo, so a full row always means the top finish.
    static func filledDots(links: Int) -> Int {
        guard links > 0 else { return 0 }
        return min(dots, max(1, links * dots / holoAt))
    }
}

/// Collector numbers: an actor's place in the order you first linked them, from
/// No. 1. Ties (one chain logging several at once) break by TMDB id, so the
/// numbering is stable. Computed from the whole Reel, never a filtered view.
enum ReelNumber {
    static func numbers(for actors: [CollectedEntity]) -> [CollectedEntity.ID: Int] {
        let ordered = actors.sorted {
            ($0.firstSeen, $0.tmdbID) < ($1.firstSeen, $1.tmdbID)
        }
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0 + 1) })
    }

    /// "No. 027" — three digits, as a set number reads.
    static func label(_ number: Int) -> String {
        "No. " + String(repeating: "0", count: max(0, 3 - String(number).count)) + String(number)
    }
}

// MARK: - Genres

/// TMDB's movie genre names, by id. The list is fixed on TMDB's side
/// (`genre/movie/list`), so it lives here rather than costing a request.
enum ReelGenre {
    static func name(_ id: Int) -> String? { names[id] }

    private static let names: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
    ]
}

// MARK: - Sizes

enum ReelLayout {
    /// The width cards and frames are drawn at — about a grid slot at three
    /// across on a phone — before `ReelCanvas` scales them.
    static let designWidth: CGFloat = 110
    /// How wide a lifted card or frame is shown.
    static let liftedWidth: CGFloat = 300
    /// Art size for grid slots — and the one warmed at launch.
    static let artSize = "w342"
    /// The sharper art a lifted card swaps to once it has loaded.
    static let liftedArtSize = "w780"
}

/// Lays `content` out once at `ReelLayout.designWidth` and scales it to the
/// width it's offered, so a card is the same picture at every size: in its grid
/// slot, mid-lift, and lifted. Borders and shadows scale with it, like a card
/// held closer.
struct ReelCanvas<Content: View>: View {
    let aspect: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { g in
            let width = ReelLayout.designWidth
            content
                .frame(width: width, height: width / aspect)
                .scaleEffect(g.size.width / width, anchor: .topLeading)
        }
        .aspectRatio(aspect, contentMode: .fit)
    }
}

// MARK: - Actor card (playing card)

struct ReelActorCard: View {
    let entity: CollectedEntity
    /// Its collector number (`ReelNumber`); `nil` leaves the header blank.
    var number: Int? = nil
    var isNew = false
    /// Lifted: swap the art for a sharper image once it has loaded.
    var sharpArt = false
    /// Lifted: the laminate glare that catches the light. Grid cards are matte.
    /// Tilt itself arrives through `\.cardTilt`, read only by the leaf views
    /// below, so a tilt frame never re-runs this body.
    var lifted = false
    /// Sitting on the table, with its hard shadow. A lifted card is off the
    /// table while it's out — a shadow under a card tipping in 3D never looked
    /// attached — so the shadow slides in under it as it rises and back out as it
    /// lands, riding the flight's own animation instead of blinking.
    var grounded = true

    /// A poker card's proportions.
    static let aspect: CGFloat = 5.0 / 7.0

    private var links: Int { entity.links.count }
    private var finish: ReelFinish { ReelTier.finish(links: links) }
    private var duotone: Duotone { Duotone.forActor(tmdbID: entity.tmdbID) }
    /// Print on the face: ink on paper, the pastel-legible ink on pastel and foil.
    private var faceInk: Color { finish == .paper ? Theme.Color.ink : Theme.Color.onAccent }

    var body: some View {
        VStack(spacing: 5) {
            header
            ReelParallax {
                ReelArt(path: entity.imagePath, kind: .actor, name: entity.name,
                        sharpSize: sharpArt ? ReelLayout.liftedArtSize : nil, duotone: duotone)
            }
                // The photo takes whatever the header and plate leave, so the
                // card stays 5:7.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.Color.border, lineWidth: 1.5))
                .overlay(alignment: .topTrailing) {
                    // On the photo's corner, clear of the logo mark above it.
                    if isNew { NewBadge().rotationEffect(.degrees(8)).offset(x: 4, y: 4) }
                }
            namePlate
        }
        .padding(7)
        .background { face }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay {
            if lifted { ReelGlare().clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm)) }
        }
        .neoSurface(radius: Theme.Radius.sm, fill: .clear, shadow: grounded ? Theme.Shadow.small : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The set number on the left, the logo mark on the right.
    private var header: some View {
        HStack(spacing: 4) {
            if let number {
                // Just the number: a holo card shows it's holo, never says so.
                Text(ReelNumber.label(number))
                    .font(Theme.Font.cardStamp)
                    .textCase(.uppercase)
                    .tracking(Theme.Font.labelSmallTracking)
                    .foregroundStyle(faceInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(height: 8)
                .accessibilityHidden(true)
        }
    }

    /// The name on a paper plate, with the progress dots under it.
    private var namePlate: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entity.name)
                .font(Theme.Font.heading(.caption))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            dots
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Color.tile))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.Color.border, lineWidth: 1.5))
    }

    @ViewBuilder private var face: some View {
        switch finish {
        case .paper: Theme.Color.tile
        // The face in the photo's own pastel, as if printed in the same ink.
        case .pastel: duotone.lightColor
        case .holo: ReelFoil()
        }
    }

    /// Progress toward holo (`ReelTier.filledDots`).
    private var dots: some View {
        let filled = ReelTier.filledDots(links: links)
        return HStack(spacing: 2) {
            ForEach(0..<ReelTier.dots, id: \.self) { i in
                Circle()
                    .strokeBorder(Theme.Color.ink, lineWidth: 0.75)
                    .background(Circle().fill(i < filled ? Theme.Color.ink : .clear))
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        let films = "\(links) \(links == 1 ? "film" : "films") linked, \(finish.label)"
        guard let number else { return "\(entity.name), \(films)" }
        return "\(entity.name), number \(number), \(films)"
    }
}

// MARK: - Movie frame

/// A poster hung in a picture frame: an ink moulding, a white mat, the poster
/// behind it. The caption sits under the frame in the grid, like a wall label.
struct ReelFrame: View {
    let entity: CollectedEntity
    var isNew = false
    /// Lifted: swap the poster for a sharper image once it has loaded.
    var sharpArt = false
    /// Lifted: glass over the poster that catches the light.
    var lifted = false
    /// Sitting on the wall, with its hard shadow (see `ReelActorCard.grounded`).
    var grounded = true

    private static let mat: CGFloat = 7
    private static let moulding: CGFloat = 4

    /// Width ÷ height: a 2:3 poster inside a fixed border of mat and moulding,
    /// at the design width.
    static let aspect: CGFloat = {
        let border = (mat + moulding) * 2
        let width = ReelLayout.designWidth
        return width / ((width - border) * 1.5 + border)
    }()

    var body: some View {
        ReelParallax {
            ReelArt(path: entity.imagePath, kind: .movie, name: entity.name,
                    sharpSize: sharpArt ? ReelLayout.liftedArtSize : nil)
        }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            // Trims the parallax's overscan to the mat's window.
            .clipped()
            .overlay { if lifted { ReelGlare() } }
            .overlay(Rectangle().strokeBorder(Theme.Color.border, lineWidth: 0.75))
            .padding(Self.mat)
            .background(Theme.Color.tile)
            // The moulding, with a hairline inner edge where it meets the mat.
            .overlay(Rectangle().strokeBorder(Theme.Color.hairline, lineWidth: 0.75).padding(0.75))
            .padding(Self.moulding)
            .background(Theme.Color.ink)
            .background {
                let depth = grounded ? Theme.Shadow.small : 0
                Rectangle().fill(Theme.Color.shadow).offset(y: depth)
            }
            .overlay(alignment: .topTrailing) { if isNew { NewBadge().offset(x: 3, y: -5) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entity.displayName)
    }
}

/// The wall label under a framed poster: title, then the year in the flourish.
struct ReelFrameCaption: View {
    let entity: CollectedEntity

    var body: some View {
        VStack(spacing: 0) {
            Text(entity.name)
                .font(Theme.Font.heading(.footnote))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let year = entity.year {
                Text(String(year))
                    .font(Theme.Font.sentence(.caption))
                    .foregroundStyle(Theme.Color.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Expanded card (flips to what's behind it)

/// An actor card or framed poster lifted out of the grid, with its dimmed
/// backdrop and Flip/Close controls. It turns over on a tap: an actor's back
/// lists the films linked through them, a movie's the actors. Either one tips
/// with the phone (or a finger) here, and only here: glare catches the card's
/// laminate or the frame's glass, a holo card's foil shimmers, and the photo or
/// poster shifts behind the face (see `CardTilt`).
///
/// The card makes the whole journey itself, drawn above everything: it starts
/// exactly over its grid slot (`slot`), scaled down to it, grows to the centre,
/// and on close shrinks back onto the slot — turning to its front on the way if
/// it was flipped. Only once it has landed does `CollectionView` remove it and
/// show the grid card again, identical and in place. (Matched geometry flew the
/// *grid's* card instead, which travelled under the backdrop and under its
/// neighbours, and was rebuilt at every hand-off.)
struct ReelCardDetail: View {
    let entity: CollectedEntity
    /// An actor's collector number, printed on the front.
    let number: Int?
    let linked: [CollectedEntity]
    /// The grid slot this card came from, in global coordinates. `nil` (never
    /// measured) or Reduce Motion: the card fades in place instead of travelling.
    let slot: CGRect?
    /// Set by `CollectionView` (inside the flight-home animation) when the card
    /// should go back.
    let closing: Bool
    @Binding var flipped: Bool
    let close: () -> Void

    /// Where the card sits when it's out, measured once laid out — the far end
    /// of the flight.
    @State private var rest: CGRect?
    /// The card is out (the open animation drives this to true).
    @State private var arrived = false
    @State private var settled = false
    /// The card's live tilt — never under Reduce Motion.
    @State private var tilt: CardTilt?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.telemetry) private var telemetry

    /// Turning over: quick enough to flip back and forth, a touch of settle.
    static let flip: Animation = .spring(duration: 0.42, bounce: 0.1)
    /// Coming out: the deliberate moment, with the faintest settle.
    static let open: Animation = .spring(duration: 0.4, bounce: 0.08)

    private var links: Int { entity.links.count }
    private var isActor: Bool { entity.kind == .actor }
    private var aspect: CGFloat { isActor ? ReelActorCard.aspect : ReelFrame.aspect }
    /// Travel needs a slot to travel from; otherwise the card fades.
    private var travels: Bool { !reduceMotion && slot != nil }
    private var out: Bool { arrived && !closing }

    var body: some View {
        ZStack {
            // A dark room around the lifted card, in both modes: the card is the
            // one lit object.
            Theme.Color.night.opacity(0.62)
                .ignoresSafeArea()
                .opacity(out ? 1 : 0)
                // A plain fade in (a dim mustn't bounce with the card); cleared
                // quickly on close, while the card is still on its way home.
                .animation(.easeOut(duration: 0.2), value: arrived)
                .animation(.easeOut(duration: 0.15), value: closing)
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.lg) {
                card
                controls
                    .opacity(settled && !closing ? 1 : 0)
                    .animation(.easeOut(duration: 0.1), value: closing)
            }
        }
        .environment(\.cardTilt, tilt)
        .accessibilityAction(.escape, close)
        .onAppear {
            guard !reduceMotion else { return }
            let t = CardTilt()
            t.start()
            tilt = t
        }
        .onDisappear { tilt?.stop() }
        // Flat for the flight out; alive once it has settled; flat again the
        // moment it heads home, so it lands on its slot exactly.
        .onChange(of: settled) { _, on in if on { tilt?.setActive(true) } }
        .onChange(of: closing) { _, on in if on { tilt?.setActive(false) } }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button(flipped ? "Front" : "Flip", action: toggle).buttonStyle(.ghost)
            Button("Close", action: close).buttonStyle(.ghost)
        }
        .frame(width: ReelLayout.liftedWidth)
    }

    /// The front is the grid's own drawing, scaled up (`ReelCanvas`); the back
    /// is laid out at full size over it.
    private var card: some View {
        let width = ReelLayout.liftedWidth
        // The resting place is measured on an empty stand-in the flight never
        // moves: measured on the card itself, each reading included the flight
        // transform, so "rest" chased wherever the card had just been drawn.
        return Color.clear
            .frame(width: width, height: width / aspect)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                let first = rest == nil
                rest = frame
                if first { takeOff() }
            }
            .overlay {
                faces
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggle)
                    // A drag tips the card (no gyro needed); a tap still flips.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                tilt?.dragChanged(value.translation)
                                telemetry?.cardDragged()
                            }
                            .onEnded { value in tilt?.dragEnded(velocity: value.velocity) }
                    )
                    .modifier(CardTiltRotation())
                    .modifier(LiftFlight(progress: travels ? (out ? 1 : 0) : 1, from: slot, to: rest))
                // Hidden until measured, so its first frame is over the slot
                // rather than flashing at the centre; without travel, it fades.
                .opacity(rest == nil ? 0 : travels ? 1 : (out ? 1 : 0))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(flipped ? "Shows the front"
                               : isActor ? "Shows the films linked through them"
                               : "Shows the actors linked through it")
    }

    /// Start the open once the card has been drawn over its slot. The wait is
    /// one frame: started in the same pass that measured it, the card was never
    /// drawn at the slot, so there was nothing to animate from and it appeared
    /// at the centre at once.
    private func takeOff() {
        Task {
            try? await Task.sleep(for: .milliseconds(17))
            guard !closing else { return }
            withAnimation(travels ? Self.open : Theme.Motion.reducedFade) { arrived = true }
            withAnimation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.standard.delay(0.12)) {
                settled = true
            }
        }
    }

    @ViewBuilder private var faces: some View {
        if reduceMotion {
            // No turning over: the faces cross-fade.
            front.opacity(flipped ? 0 : 1)
                .overlay { back.opacity(flipped ? 1 : 0) }
        } else {
            FlipView(angle: flipped ? 180 : 0, front: front, back: back)
        }
    }

    private func toggle() {
        guard !closing else { return }
        Haptics.selection()
        withAnimation(reduceMotion ? Theme.Motion.reducedFade : Self.flip) {
            flipped.toggle()
        }
    }

    private var front: some View {
        ReelCanvas(aspect: aspect) {
            if isActor {
                ReelActorCard(entity: entity, number: number, sharpArt: true, lifted: true,
                              grounded: !out)
            } else {
                ReelFrame(entity: entity, sharpArt: true, lifted: true, grounded: !out)
            }
        }
    }

    /// Sized by the front (it's laid over it), so both faces match.
    private var back: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Linked through").metaLabel(size: .small)
            Text(entity.displayName)
                .font(Theme.Font.heading(.title3))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Rectangle().fill(Theme.Color.border).frame(height: Theme.Border.width)

            if linked.isEmpty {
                Text("Links are counted from your next chain with \(isActor ? "them" : "it").")
                    .font(Theme.Font.sentence(.footnote))
                    .foregroundStyle(Theme.Color.muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(linked) { row($0) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Color.tile)
        .clipShape(RoundedRectangle(cornerRadius: isActor ? Theme.Radius.md : 0))
        // Only shown while out, when the card is off the table (`ReelActorCard.grounded`).
        .neoSurface(radius: isActor ? Theme.Radius.md : 0, fill: .clear, shadow: 0)
    }

    @ViewBuilder private func row(_ other: CollectedEntity) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            if other.kind == .actor {
                ReelArt(path: other.imagePath, kind: .actor, name: other.name, monogramSize: 10)
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.Color.border, lineWidth: 1.5))
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Color.movie)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.Color.border, lineWidth: 1))
                    .frame(width: 8, height: 8)
            }
            Text(other.name)
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let year = other.year {
                Text(String(year))
                    .font(Theme.Font.sentence(.footnote))
                    .foregroundStyle(Theme.Color.muted)
            }
        }
    }

    /// Missing titles are never listed: that would turn the Reel into a study
    /// sheet for the next run.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(links) \(isActor ? (links == 1 ? "film" : "films") : (links == 1 ? "actor" : "actors")) linked")
                .font(Theme.Font.numeral(.subheadline))
                .foregroundStyle(Theme.Color.ink)
            Text("In \(entity.timesLogged) \(entity.timesLogged == 1 ? "chain" : "chains")")
                .font(Theme.Font.sentence(.footnote))
                .foregroundStyle(Theme.Color.muted)
        }
    }
}

/// A card that turns over on its vertical axis. The face swaps at 90°, when
/// it's edge-on, so neither face is ever seen mirrored. The back is laid over
/// the front, so the front's size is the card's size.
private struct FlipView<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        front
            .opacity(angle < 90 ? 1 : 0)
            .overlay {
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(angle < 90 ? 0 : 1)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

/// Carries the lifted card between its grid slot and its resting place:
/// scaled to the slot's size and moved onto it at `progress` 0, untouched at 1.
/// The card is the grid's own drawing at a larger scale (`ReelCanvas`), so the
/// shrink lands it pixel-for-pixel on the slot.
nonisolated private struct LiftFlight: GeometryEffect {
    var progress: CGFloat
    let from: CGRect?
    let to: CGRect?

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard let from, let to, to.width > 0 else { return ProjectionTransform() }
        let away = 1 - progress
        let scale = 1 + (from.width / to.width - 1) * away
        let centre = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
        let transform = centre.inverted()
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(centre)
            .concatenating(CGAffineTransform(translationX: (from.midX - to.midX) * away,
                                             y: (from.midY - to.midY) * away))
        return ProjectionTransform(transform)
    }
}

// MARK: - Pieces

/// Press feedback for a Reel card or frame: the card sinks a touch (0.97), and
/// that's all. The app's `.pressScale` also dims to 85%, which on a photo card
/// read as a pop when the lift then started from the undimmed card. Under
/// Reduce Motion the scale is motion, so the dim stands in for it instead.
struct ReelPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.85 : 1)
                .animation(Theme.Motion.press, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == ReelPressStyle {
    /// Usage: `.buttonStyle(.reelPress)`
    static var reelPress: ReelPressStyle { .init() }
}

/// The holo face, lit by the lifted card's tilt. Its own view so a tilt frame
/// redraws only the foil, not the card.
private struct ReelFoil: View {
    @Environment(\.cardTilt) private var tilt

    var body: some View { HoloFoil(tilt: tilt?.value ?? .zero) }
}

/// The photo sitting a little behind the card's face: it slides against the
/// tilt inside its window, scaled up just enough that the slide never shows an
/// edge. The overscan grows with the tilt's intensity, so a grid card — and a
/// lifted one while it flies — is the photo exactly as cropped, never zoomed.
private struct ReelParallax<Content: View>: View {
    @Environment(\.cardTilt) private var tilt
    @ViewBuilder let content: Content

    /// Design points the photo slides at full tilt.
    private static var travel: CGFloat { 2.5 }
    /// Overscan at full tilt: covers `travel` each side of the smallest window
    /// (a poster, ~88pt), with a little to spare.
    private static var overscan: CGFloat { 0.07 }

    var body: some View {
        let t = tilt?.value ?? .zero
        content
            .scaleEffect(1 + Self.overscan * (tilt?.intensity ?? 0))
            .offset(x: -t.width * Self.travel, y: -t.height * Self.travel)
    }
}

/// Light catching the laminate on a lifted card: a soft diagonal band that
/// brightens and slides as the card tips. Still (and faint) without tilt.
private struct ReelGlare: View {
    @Environment(\.cardTilt) private var tilt

    var body: some View {
        let t = tilt?.value ?? .zero
        let magnitude = min(1, (abs(t.width) + abs(t.height)) / 1.4)
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            // 2.6× the card so 0.8 of a width/height of travel each way
            // never shows an edge; the band sits across the middle at rest.
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0.42),
                .init(color: .white, location: 0.5),
                .init(color: .white.opacity(0), location: 0.58),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: w * 2.6, height: h * 2.6)
                .offset(x: t.width * w * 0.8, y: t.height * h * 0.8)
                .frame(width: w, height: h)
        }
        // Plain white over the face, no blend mode: a compositing filter here
        // could push the whole card offscreen on every tilt frame.
        .opacity(0.10 + 0.25 * magnitude)
        .allowsHitTesting(false)
    }
}

private struct NewBadge: View {
    var body: some View {
        Text("New")
            .font(Theme.Font.cardStamp)
            .textCase(.uppercase)
            .tracking(Theme.Font.labelSmallTracking)
            .foregroundStyle(Theme.Color.onAccent)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Theme.Color.good))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1))
    }
}

/// A headshot or poster, read through `ArtCache`: drawn at once when it's in
/// memory, otherwise faded in over the kind's accent when it lands. A monogram
/// stands in only when there's no art at all — never as a loading state, so a
/// card goes straight from colour to photo, one step.
///
/// The regular image and the sharper one (a lifted card) are separate layers,
/// and only their opacity animates — no views swapped in and out. Swapping one
/// image view for another left a frame or two where neither was fully drawn and
/// the accent flashed through; layered, the base photo is always underneath.
private struct ReelArt: View {
    let path: String?
    let kind: NodeKind
    let name: String
    /// A sharper size to fade in over the base image once it lands (a lifted card).
    var sharpSize: String? = nil
    var monogramSize: CGFloat = 28
    /// Print the photo in these two inks (an actor card). Baked into the cached
    /// image when it loads, so it costs nothing to draw.
    var duotone: Duotone? = nil

    @State private var base: Image?
    @State private var sharp: Image?
    /// Art already in memory when this view is made starts shown — no fade.
    @State private var baseShown: Bool
    @State private var sharpShown: Bool
    @State private var failed = false

    init(path: String?, kind: NodeKind, name: String, sharpSize: String? = nil,
         monogramSize: CGFloat = 28, duotone: Duotone? = nil) {
        self.path = path
        self.kind = kind
        self.name = name
        self.sharpSize = sharpSize
        self.monogramSize = monogramSize
        self.duotone = duotone
        let cache = ArtCache.shared
        let cached = { (url: URL) in cache.image(for: cache.key(url, duotone: duotone)) }
        let base = Config.imageURL(path: path, size: ReelLayout.artSize).flatMap(cached)
        let sharp = sharpSize.flatMap { Config.imageURL(path: path, size: $0) }.flatMap(cached)
        _base = State(initialValue: base)
        _sharp = State(initialValue: sharp)
        _baseShown = State(initialValue: base != nil)
        _sharpShown = State(initialValue: sharp != nil)
    }

    var body: some View {
        // While loading (or with no art): the duotone's shadow ink, so the photo
        // arrives out of its own colour; otherwise the kind's accent.
        (duotone?.darkColor ?? kind.accent)
            .overlay {
                if base == nil, sharp == nil, path == nil || failed { monogram }
            }
            .overlay {
                if let base { fill(base).opacity(baseShown ? 1 : 0) }
            }
            .overlay {
                if let sharp { fill(sharp).opacity(sharpShown ? 1 : 0) }
            }
            .clipped()
            .task(id: path) { await load() }
    }

    private func fill(_ image: Image) -> some View {
        image.resizable().aspectRatio(contentMode: .fill)
    }

    private func load() async {
        if base == nil, sharp == nil {
            guard let url = Config.imageURL(path: path, size: ReelLayout.artSize) else { return }
            guard let loaded = await ArtCache.shared.load(url, duotone: duotone) else {
                if !Task.isCancelled { failed = true }
                return
            }
            guard !Task.isCancelled else { return }
            base = loaded                       // in place, transparent…
            withAnimation(.easeOut(duration: 0.2)) { baseShown = true }   // …then faded up
        }
        // The same picture, sharper, faded in on top — or the moment it sharpens
        // shows as a pop on a large lifted card.
        guard sharp == nil, let sharpSize,
              let url = Config.imageURL(path: path, size: sharpSize),
              let loaded = await ArtCache.shared.load(url, duotone: duotone), !Task.isCancelled
        else { return }
        sharp = loaded
        withAnimation(.easeOut(duration: 0.15)) { sharpShown = true }
    }

    private var monogram: some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(Theme.Font.display(monogramSize))
            .foregroundStyle(duotone?.lightColor ?? kind.onAccent.opacity(0.7))
    }
}

// MARK: - Demo deck

#if DEBUG
extension CollectionStore {
    /// An in-memory Reel of real actors and films, for previews and the
    /// `-uiDemoReel` launch argument. Never touches the player's saved Reel.
    /// The genres are real (TMDB, 2026-10-22).
    static func demo() -> CollectionStore {
        func actor(_ id: Int, _ name: String, _ path: String?) -> Person {
            Person(id: id, name: name, imagePath: path)
        }
        func film(_ id: Int, _ title: String, _ year: Int, _ path: String?, _ genres: [Int]) -> Movie {
            Movie(id: id, title: title, year: year, imagePath: path, genreIDs: genres)
        }
        let deck: [(Person, [Movie])] = [
        (actor(6384, "Keanu Reeves", "/8RZLOyYGsoRe9p44q3xin9QkMHv.jpg"), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", [28, 878]),
                    film(245891, "John Wick", 2014, "/wXqWR7dHncNRbxoEGybEy7QTe9h.jpg", [28, 53]),
                    film(1637, "Speed", 1994, "/82PkCE4R95KhHICUDF7G4Ly2z3l.jpg", [28, 53]),
                    film(1089, "Point Break", 1991, "/tlbERIghrQ4oofqlbF7H0K0EYnx.jpg", [28, 53, 80]),
                    film(1813, "The Devil's Advocate", 1997, "/5ZzBGpxy55OQzHxKVY11IpY6a0o.jpg", [27, 18, 9648]),
                    film(561, "Constantine", 2005, "/vPYgvd2MwHlxTamAOjwVQp4qs1W.jpg", [14, 28, 27]),
                    film(1648, "Bill & Ted's Excellent Adventure", 1989, "/tV25lGWGWGEqUe3U0xjQTBgilSx.jpg", [12, 35, 878]),
                    film(604, "The Matrix Reloaded", 2003, "/8xEVAe84zlL9rkfYT6dZXero4KK.jpg", [28, 53, 878]),
                    film(324552, "John Wick: Chapter 2", 2017, "/hXWBc0ioZP3cN4zCu6SN3YHXZVO.jpg", [28, 53, 80]),
                    film(301528, "Toy Story 4", 2019, "/w9kR8qbmQ01HwnvK4alvnQ2ca0L.jpg", [10751, 35, 16, 12]),
                    film(513576, "Always Be My Maybe", 2019, "/3BO6pPa7qDcpPYct061Luh9fvst.jpg", [10749, 35])]),
        (actor(31, "Tom Hanks", "/oFvZoKI6lvU03n4YoNGAll9rkas.jpg"), [
                    film(13, "Forrest Gump", 1994, "/saHP97rTPS5eLmrLQEcANmKrsFl.jpg", [35, 18, 10749]),
                    film(8358, "Cast Away", 2000, "/7lLJgKnAicAcR5UEuo8xhSMj18w.jpg", [12, 18]),
                    film(862, "Toy Story", 1995, "/uXDfjJbdP4ijW5hWSBrPrlKpxab.jpg", [10751, 35, 16, 12]),
                    film(857, "Saving Private Ryan", 1998, "/uqx37cS8cpHg8U35f9U5IBlrCV3.jpg", [10752, 18, 36]),
                    film(2280, "Big", 1988, "/eWhCDJiwxvx3YXkAFRiHjimnF0j.jpg", [14, 18, 35]),
                    film(640, "Catch Me If You Can", 2002, "/ctjEj2xM32OvBXCq8zAdK3ZrsAj.jpg", [18, 80])]),
        (actor(1373737, "Florence Pugh", "/1QfiLnofJFlOJOLCWaxyDpIN03v.jpg"), [
                    film(872585, "Oppenheimer", 2023, "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", [18, 36, 10752]),
                    film(331482, "Little Women", 2019, "/yn5ihODtZ7ofn8pDYfxCmxh8AXI.jpg", [18, 10749]),
                    film(530385, "Midsommar", 2019, "/7LEI8ulZzO5gy9Ww2NVCrKmHeDZ.jpg", [27, 18, 9648]),
                    film(693134, "Dune: Part Two", 2024, "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", [878, 12])]),
        (actor(234352, "Margot Robbie", "/euDPyqLnuwaWMHajcU3oZ9uZezR.jpg"), [
                    film(346698, "Barbie", 2023, "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg", [35, 12, 14]),
                    film(106646, "The Wolf of Wall Street", 2013, "/kW9LmvYHAaS9iA0tHmZVq8hQYoq.jpg", [80, 18, 35]),
                    film(615777, "Babylon", 2022, "/wjOHjWCUE0YzDiEzKv8AfqHj3ir.jpg", [18, 35]),
                    film(466272, "Once Upon a Time in Hollywood", 2019, "/8j58iEBw9pOXFD2L0nt0ZXeHviB.jpg", [35, 18, 53])]),
        (actor(139, "Uma Thurman", "/sBgAZWi3o4FsnaTvnTNtK6jpQcF.jpg"), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", [53, 80, 35]),
                    film(24, "Kill Bill: Vol. 1", 2003, "/v7TaX8kXMXs5yFFGR41guUDNcnB.jpg", [28, 80]),
                    film(782, "Gattaca", 1997, "/eSKr5Fl1MEC7zpAXaLWBWSBjgJq.jpg", [878, 18])]),
        (actor(884, "Steve Buscemi", "/n0pZumkrcZrAPMoPq684RhYnjPV.jpg"), [
                    film(275, "Fargo", 1996, "/rt7cpEr1uP6RTZykBFhBTcRaKvG.jpg", [80, 18, 53])]),
        (actor(2231, "Samuel L. Jackson", "/AiAYAqwpM5xmiFrAIeQvUXDCVvo.jpg"), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", [53, 80, 35])]),
        (actor(8891, "John Travolta", "/ap8eEYfBKTLixmVVpRlq4NslDD5.jpg"), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", [53, 80, 35])]),
        (actor(2975, "Laurence Fishburne", "/2GbXERENPpl5MmlqOLlPVaVtifD.jpg"), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", [28, 878])]),
        (actor(530, "Carrie-Anne Moss", "/9zya72vRZYBQILfetACsnmCBgdj.jpg"), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", [28, 878])]),
        (actor(2037, "Cillian Murphy", "/2lKs67r7FI4bPu0AXxMUJZxmUXn.jpg"), [
                    film(872585, "Oppenheimer", 2023, "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", [18, 36, 10752])]),
        (actor(32, "Robin Wright", "/d3rIv0y2p0jMsQ7ViR7O1606NZa.jpg"), [
                    film(13, "Forrest Gump", 1994, "/saHP97rTPS5eLmrLQEcANmKrsFl.jpg", [35, 18, 10749])]),
        (actor(30614, "Ryan Gosling", "/lyUyVARQKhGxaxy0FbPJCQRpiaW.jpg"), [
                    film(346698, "Barbie", 2023, "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg", [35, 12, 14])]),
        ]
        let store = CollectionStore(fileURL: nil)
        for (person, films) in deck {
            for film in films {
                store.record(chain: [.actor(person), .movie(film)])
            }
        }
        return store
    }
}

#Preview("Deck") {
    CollectionView(store: .demo(), bestChain: 11)
}

#Preview("Card and frame") {
    let store = CollectionStore.demo()
    let numbers = ReelNumber.numbers(for: store.sortedActors)
    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
        ForEach(store.sortedActors.prefix(2)) { actor in
            ReelCanvas(aspect: ReelActorCard.aspect) {
                ReelActorCard(entity: actor, number: numbers[actor.id])
            }
        }
        if let movie = store.sortedMovies.first {
            VStack(spacing: Theme.Spacing.xs) {
                ReelCanvas(aspect: ReelFrame.aspect) { ReelFrame(entity: movie) }
                ReelFrameCaption(entity: movie)
            }
        }
    }
    .padding(Theme.Spacing.gutter)
    .background(Theme.Color.canvas)
}
#endif
