//
//  ReelCards.swift
//  movie-quiz
//
//  Your Reel as a deck of collectibles. An actor is a playing card whose number
//  is the films you've linked *through them*; a movie is a stamp carrying the
//  actors you linked through it — a reverse reference with no progress, since a
//  cast runs to extras and could never be completed.
//
//  `ReelTier` is the pure part (which finish a card earns, what its corner
//  reads) and is unit-tested; the views only draw what it decides. The tier
//  model is a setting for now — Rank, Share or Plain — so the three can be
//  compared in real play before one is kept.
//

import SwiftUI

// MARK: - Tiers (pure)

/// How an actor card earns its finish. A player setting while the three are
/// compared (Settings → Reel cards).
enum ReelTierModel: String, CaseIterable, Identifiable {
    /// The count is the card's rank: 1 = A … 11 = J, 12 = Q, 13+ = K. Same
    /// thresholds for everyone.
    case rank
    /// Thresholds scale with the actor's well-known films, clamped so a huge
    /// filmography never puts holo out of reach and a small one never gives it away.
    case share
    /// No tiers: every card is paper and the corner is just the count.
    case plain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rank: "Rank"
        case .share: "Share"
        case .plain: "Plain"
        }
    }

    /// One line for the setting, saying what the model does.
    var rule: String {
        switch self {
        case .rank: "Links are the card's rank, A to K. Inked at 5, holo for the face cards (11+)."
        case .share: "Scaled to each actor: inked at a quarter of their well-known films, holo at half."
        case .plain: "No tiers. The corner is the count."
        }
    }
}

/// The finish a card is printed in, lowest first.
enum ReelFinish: Comparable {
    case paper, inked, holo
}

enum ReelTier {
    /// Rank's thresholds: inked from 5 links, holo from the Jack.
    static let rankThresholds = (inked: 5, holo: 11)

    /// The links an actor needs for inked and holo; `nil` for Plain, which has
    /// no tiers. Share falls back to Rank's thresholds until the actor's
    /// filmography has loaded in play (Reels saved before the snapshot existed).
    static func thresholds(wellKnown: Int?, model: ReelTierModel) -> (inked: Int, holo: Int)? {
        switch model {
        case .plain:
            return nil
        case .rank:
            return rankThresholds
        case .share:
            guard let wellKnown else { return rankThresholds }
            return (scaled(wellKnown, share: 0.25, within: 2...5),
                    scaled(wellKnown, share: 0.5, within: 4...10))
        }
    }

    static func finish(links: Int, wellKnown: Int?, model: ReelTierModel) -> ReelFinish {
        guard let t = thresholds(wellKnown: wellKnown, model: model) else { return .paper }
        if links >= t.holo { return .holo }
        return links >= t.inked ? .inked : .paper
    }

    /// The next finish up and the links it needs; `nil` at the top or in Plain.
    static func next(links: Int, wellKnown: Int?, model: ReelTierModel) -> (finish: ReelFinish, at: Int)? {
        guard let t = thresholds(wellKnown: wellKnown, model: model) else { return nil }
        if links < t.inked { return (.inked, t.inked) }
        if links < t.holo { return (.holo, t.holo) }
        return nil
    }

    /// What the card's corner index reads. A card with no links yet (a Reel
    /// saved before links were recorded) shows a dot.
    static func corner(links: Int, model: ReelTierModel) -> String {
        guard links > 0 else { return "·" }
        guard model == .rank else { return "\(links)" }
        switch links {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13...: return "K"
        default: return "\(links)"
        }
    }

    private static func scaled(_ wellKnown: Int, share: Double, within range: ClosedRange<Int>) -> Int {
        let wanted = Int((Double(wellKnown) * share).rounded(.up))
        return min(range.upperBound, max(range.lowerBound, wanted))
    }
}

extension ReelFinish {
    var label: String {
        switch self {
        case .paper: "Paper"
        case .inked: "Inked"
        case .holo: "Holo"
        }
    }
}

// MARK: - Actor card (playing card)

struct ReelActorCard: View {
    let entity: CollectedEntity
    let model: ReelTierModel
    /// Live tilt for the expanded card. The grid passes `.zero`, so a deck full
    /// of holo never runs the gyro.
    var tilt: CGSize = .zero
    var large = false
    var isNew = false

    private var links: Int { entity.links.count }
    private var finish: ReelFinish {
        ReelTier.finish(links: links, wellKnown: entity.wellKnownFilms, model: model)
    }
    private var ink: Color { finish == .holo ? Theme.Color.onAccent : Theme.Color.ink }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ReelArt(path: entity.imagePath, kind: .actor, name: entity.name, size: large ? "w342" : "w185")
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            Text(entity.name)
                .font(Theme.Font.heading(large ? .title3 : .subheadline))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if model != .plain, links > 0 { pips }
        }
        // Wide enough that the corner indices clear the pips.
        .padding(.horizontal, large ? 36 : 27)
        .padding(.top, large ? 40 : 30)
        .padding(.bottom, large ? 36 : 28)
        .background { face }
        .overlay(alignment: .topLeading) { index.padding(large ? 10 : 7) }
        .overlay(alignment: .bottomTrailing) {
            index.rotationEffect(.degrees(180)).padding(large ? 10 : 7)
        }
        .overlay(alignment: .topTrailing) { if isNew { newBadge } }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .neoSurface(radius: Theme.Radius.md, fill: .clear,
                    shadow: large ? Theme.Shadow.large : Theme.Shadow.small)
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entity.name), \(links) \(links == 1 ? "film" : "films") linked, \(finish.label)")
    }

    @ViewBuilder private var face: some View {
        switch finish {
        case .paper:
            Theme.Color.tile
        case .inked:
            // A printed frame in the actor blue, inset like a card's border art.
            Theme.Color.tile.overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.Color.actor, lineWidth: large ? 5 : 4)
                    .padding(large ? 6 : 4)
            }
        case .holo:
            HoloFoil(tilt: tilt)
        }
    }

    private var index: some View {
        VStack(spacing: 0) {
            Text(ReelTier.corner(links: links, model: model))
                .font(Theme.Font.numeral(large ? .title2 : .headline))
                .monospacedDigit()
            Image(systemName: "film.fill")
                .font(.system(size: large ? 11 : 8))
        }
        .foregroundStyle(ink)
        .fixedSize()
    }

    /// Rank and Plain: one pip per linked film, up to ten. Share fills ten
    /// segments toward holo instead, so the pips read "how close", not "how many".
    private var pips: some View {
        let total = 10
        let holo = ReelTier.thresholds(wellKnown: entity.wellKnownFilms, model: model)?.holo ?? total
        let filled = model == .share
            ? min(total, Int((Double(links) / Double(holo) * Double(total)).rounded()))
            : min(total, links)
        return HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filled ? ink : ink.opacity(0.12))
                    .frame(height: large ? 6 : 4)
            }
        }
    }

    private var newBadge: some View {
        Text("New")
            .metaLabel(Theme.Color.onAccent, size: .small)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Color.good))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            .padding(6)
    }
}

// MARK: - Expanded card (flips to the ledger)

/// An actor card lifted out of the deck. Tap it (or Flip) to turn it over to
/// the films linked through them. Holo cards catch the light here, and only here.
struct ReelCardDetail: View {
    let entity: CollectedEntity
    let linked: [CollectedEntity]
    let model: ReelTierModel
    let dismiss: () -> Void

    @State private var flipped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var links: Int { entity.links.count }
    private var live: Bool {
        !reduceMotion && TiltMotion.shared.isAvailable
            && ReelTier.finish(links: links, wellKnown: entity.wellKnownFilms, model: model) == .holo
    }

    var body: some View {
        ZStack {
            Theme.Color.canvas.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.lg) {
                Group {
                    if reduceMotion {
                        // No turning over: the faces cross-fade.
                        ZStack {
                            front.opacity(flipped ? 0 : 1)
                            back.opacity(flipped ? 1 : 0)
                        }
                    } else {
                        FlipView(angle: flipped ? 180 : 0, front: front, back: back)
                    }
                }
                .frame(width: 270)
                .onTapGesture(perform: toggle)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(flipped ? "Shows the front" : "Shows the films linked through them")

                HStack(spacing: Theme.Spacing.sm) {
                    Button(flipped ? "Front" : "Flip", action: toggle).buttonStyle(.ghost)
                    Button("Close", action: dismiss).buttonStyle(.ghost)
                }
                .frame(width: 270)
            }
        }
        .onAppear { if live { TiltMotion.shared.start() } }
        .onDisappear { if live { TiltMotion.shared.stop() } }
    }

    private func toggle() {
        withAnimation(reduceMotion ? Theme.Motion.reducedFade : .spring(duration: 0.55, bounce: 0.15)) {
            flipped.toggle()
        }
    }

    private var front: some View {
        ReelActorCard(entity: entity, model: model,
                      tilt: live ? TiltMotion.shared.tilt : .zero, large: true)
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Linked through").metaLabel(size: .small)
            Text(entity.name)
                .font(Theme.Font.heading(.title3))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Rectangle().fill(Theme.Color.border).frame(height: Theme.Border.width)

            if linked.isEmpty {
                Text("Links are counted from your next chain with them.")
                    .font(Theme.Font.flourish(.footnote))
                    .foregroundStyle(Theme.Color.muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(linked) { film in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.Color.movie)
                                    .overlay(RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(Theme.Color.border, lineWidth: 1))
                                    .frame(width: 8, height: 8)
                                Text(film.name)
                                    .font(Theme.Font.bodyStrong)
                                    .foregroundStyle(Theme.Color.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if let year = film.year {
                                    Text(String(year))
                                        .font(Theme.Font.flourish(.footnote))
                                        .foregroundStyle(Theme.Color.muted)
                                }
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.tile)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .neoSurface(radius: Theme.Radius.md, fill: .clear, shadow: Theme.Shadow.large)
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
    }

    /// The only place a denominator appears, and only in Share. Missing titles
    /// are never listed: that would turn the Reel into a study sheet for the
    /// next run.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if model == .share, let known = entity.wellKnownFilms {
                    Text("\(links) of ~\(known) well-known films")
                } else {
                    Text("\(links) \(links == 1 ? "film" : "films") linked")
                }
            }
            .font(Theme.Font.numeral(.subheadline))
            .foregroundStyle(Theme.Color.ink)

            Group {
                if let next = ReelTier.next(links: links, wellKnown: entity.wellKnownFilms, model: model) {
                    Text("\(next.finish.label) at \(next.at) · in \(entity.timesLogged) \(entity.timesLogged == 1 ? "chain" : "chains")")
                } else {
                    Text("In \(entity.timesLogged) \(entity.timesLogged == 1 ? "chain" : "chains")")
                }
            }
            .font(Theme.Font.flourish(.footnote))
            .foregroundStyle(Theme.Color.muted)
        }
    }
}

/// A card that turns over on its vertical axis. The face swaps at 90°, when
/// the card is edge-on, so neither face is ever seen mirrored.
private struct FlipView<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            front.opacity(angle < 90 ? 1 : 0)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(angle < 90 ? 0 : 1)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

// MARK: - Movie stamp

struct ReelStamp: View {
    let entity: CollectedEntity
    /// The actors linked through this film, most-linked first.
    let actors: [CollectedEntity]
    var isNew = false

    private static let maxFaces = 4

    var body: some View {
        let edge = PerforatedEdge(radius: 4)
        VStack(alignment: .leading, spacing: 6) {
            ReelArt(path: entity.imagePath, kind: .movie, name: entity.name, size: "w342")
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipped()
                .overlay(Rectangle().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            Text(entity.name)
                .font(Theme.Font.heading(.subheadline))
                .foregroundStyle(Theme.Color.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            faces
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Color.movie)
        .overlay(Rectangle().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
        .padding(10)
        .background {
            ZStack {
                edge.fill(Theme.Color.shadow).offset(x: Theme.Shadow.small, y: Theme.Shadow.small)
                edge.fill(Theme.Color.tile)
                edge.stroke(Theme.Color.border, lineWidth: Theme.Border.width)
            }
        }
        .overlay(alignment: .topTrailing) { postmark }
        .overlay(alignment: .topLeading) { if isNew { newBadge } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The postmark: the release year, like a stamp's issue date.
    @ViewBuilder private var postmark: some View {
        if let year = entity.year {
            Text(String(year))
                .font(Theme.Font.flourish(.caption))
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.Color.tile))
                .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1.5))
                .rotationEffect(.degrees(8))
                .offset(x: -4, y: 4)
        }
    }

    /// Who you linked through this film: faces, no count. Reserves its height
    /// when empty so stamps in a row stay level.
    private var faces: some View {
        HStack(spacing: -6) {
            ForEach(actors.prefix(Self.maxFaces)) { actor in
                ReelArt(path: actor.imagePath, kind: .actor, name: actor.name, size: "w92", monogramSize: 9)
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.Color.border, lineWidth: 1.5))
            }
            if actors.count > Self.maxFaces {
                Text("+\(actors.count - Self.maxFaces)")
                    .font(Theme.Font.labelSmall)
                    .foregroundStyle(Theme.Color.onAccent)
                    .padding(.leading, 10)
            }
        }
        .frame(height: 22, alignment: .leading)
    }

    private var newBadge: some View {
        Text("New")
            .metaLabel(Theme.Color.onAccent, size: .small)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Color.good))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
            .offset(x: 2, y: 2)
    }

    private var accessibilityText: String {
        guard !actors.isEmpty else { return entity.displayName }
        return "\(entity.displayName), linked through \(actors.map(\.name).formatted(.list(type: .and)))"
    }
}

/// A rectangle whose edges are bitten by evenly spaced semicircles, like a
/// stamp torn from its sheet.
private struct PerforatedEdge: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var holes = Path()
        let pitch = radius * 2.8
        let across = max(1, Int(rect.width / pitch))
        let down = max(1, Int(rect.height / pitch))
        let dx = rect.width / CGFloat(across)
        let dy = rect.height / CGFloat(down)
        let d = radius * 2
        for i in 0..<across {
            let x = rect.minX + dx * (CGFloat(i) + 0.5) - radius
            holes.addEllipse(in: CGRect(x: x, y: rect.minY - radius, width: d, height: d))
            holes.addEllipse(in: CGRect(x: x, y: rect.maxY - radius, width: d, height: d))
        }
        for j in 0..<down {
            let y = rect.minY + dy * (CGFloat(j) + 0.5) - radius
            holes.addEllipse(in: CGRect(x: rect.minX - radius, y: y, width: d, height: d))
            holes.addEllipse(in: CGRect(x: rect.maxX - radius, y: y, width: d, height: d))
        }
        return Path(rect).subtracting(holes)
    }
}

// MARK: - Art

/// A headshot or poster, streamed through `AsyncImage` (system-cached, never
/// stored), over the kind's accent with a monogram until it arrives — or for
/// good, when TMDB has no art.
private struct ReelArt: View {
    let path: String?
    let kind: NodeKind
    let name: String
    let size: String
    var monogramSize: CGFloat = 28

    var body: some View {
        ZStack {
            kind.accent
            if let url = Config.imageURL(path: path, size: size) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
    }

    private var monogram: some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(Theme.Font.display(monogramSize))
            .foregroundStyle(kind.onAccent.opacity(0.7))
    }
}

// MARK: - Demo deck

#if DEBUG
extension CollectionStore {
    /// An in-memory Reel of real actors and films, for previews and the
    /// `-uiDemoReel` launch argument. Never touches the player's saved Reel.
    /// The well-known counts are real (TMDB, 2026-10-22).
    static func demo() -> CollectionStore {
        func actor(_ id: Int, _ name: String, _ path: String?, wellKnown: Int) -> (Person, Int) {
            (Person(id: id, name: name, imagePath: path), wellKnown)
        }
        func film(_ id: Int, _ title: String, _ year: Int, _ path: String?) -> Movie {
            Movie(id: id, title: title, year: year, imagePath: path)
        }
        let deck: [((Person, Int), [Movie])] = [
        (actor(6384, "Keanu Reeves", "/8RZLOyYGsoRe9p44q3xin9QkMHv.jpg", wellKnown: 48), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg"),
                    film(245891, "John Wick", 2014, "/wXqWR7dHncNRbxoEGybEy7QTe9h.jpg"),
                    film(1637, "Speed", 1994, "/82PkCE4R95KhHICUDF7G4Ly2z3l.jpg"),
                    film(1089, "Point Break", 1991, "/tlbERIghrQ4oofqlbF7H0K0EYnx.jpg"),
                    film(1813, "The Devil's Advocate", 1997, "/5ZzBGpxy55OQzHxKVY11IpY6a0o.jpg"),
                    film(561, "Constantine", 2005, "/vPYgvd2MwHlxTamAOjwVQp4qs1W.jpg"),
                    film(1648, "Bill & Ted's Excellent Adventure", 1989, "/tV25lGWGWGEqUe3U0xjQTBgilSx.jpg"),
                    film(604, "The Matrix Reloaded", 2003, "/8xEVAe84zlL9rkfYT6dZXero4KK.jpg"),
                    film(324552, "John Wick: Chapter 2", 2017, "/hXWBc0ioZP3cN4zCu6SN3YHXZVO.jpg"),
                    film(301528, "Toy Story 4", 2019, "/w9kR8qbmQ01HwnvK4alvnQ2ca0L.jpg"),
                    film(513576, "Always Be My Maybe", 2019, "/3BO6pPa7qDcpPYct061Luh9fvst.jpg")]),
        (actor(31, "Tom Hanks", "/oFvZoKI6lvU03n4YoNGAll9rkas.jpg", wellKnown: 52), [
                    film(13, "Forrest Gump", 1994, "/saHP97rTPS5eLmrLQEcANmKrsFl.jpg"),
                    film(8358, "Cast Away", 2000, "/7lLJgKnAicAcR5UEuo8xhSMj18w.jpg"),
                    film(862, "Toy Story", 1995, "/uXDfjJbdP4ijW5hWSBrPrlKpxab.jpg"),
                    film(857, "Saving Private Ryan", 1998, "/uqx37cS8cpHg8U35f9U5IBlrCV3.jpg"),
                    film(2280, "Big", 1988, "/eWhCDJiwxvx3YXkAFRiHjimnF0j.jpg"),
                    film(640, "Catch Me If You Can", 2002, "/ctjEj2xM32OvBXCq8zAdK3ZrsAj.jpg")]),
        (actor(1373737, "Florence Pugh", "/1QfiLnofJFlOJOLCWaxyDpIN03v.jpg", wellKnown: 14), [
                    film(872585, "Oppenheimer", 2023, "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg"),
                    film(331482, "Little Women", 2019, "/yn5ihODtZ7ofn8pDYfxCmxh8AXI.jpg"),
                    film(530385, "Midsommar", 2019, "/7LEI8ulZzO5gy9Ww2NVCrKmHeDZ.jpg"),
                    film(693134, "Dune: Part Two", 2024, "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg")]),
        (actor(234352, "Margot Robbie", "/euDPyqLnuwaWMHajcU3oZ9uZezR.jpg", wellKnown: 20), [
                    film(346698, "Barbie", 2023, "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg"),
                    film(106646, "The Wolf of Wall Street", 2013, "/kW9LmvYHAaS9iA0tHmZVq8hQYoq.jpg"),
                    film(615777, "Babylon", 2022, "/wjOHjWCUE0YzDiEzKv8AfqHj3ir.jpg"),
                    film(466272, "Once Upon a Time in Hollywood", 2019, "/8j58iEBw9pOXFD2L0nt0ZXeHviB.jpg")]),
        (actor(139, "Uma Thurman", "/sBgAZWi3o4FsnaTvnTNtK6jpQcF.jpg", wellKnown: 20), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg"),
                    film(24, "Kill Bill: Vol. 1", 2003, "/v7TaX8kXMXs5yFFGR41guUDNcnB.jpg"),
                    film(782, "Gattaca", 1997, "/eSKr5Fl1MEC7zpAXaLWBWSBjgJq.jpg")]),
        (actor(884, "Steve Buscemi", "/n0pZumkrcZrAPMoPq684RhYnjPV.jpg", wellKnown: 48), [
                    film(275, "Fargo", 1996, "/rt7cpEr1uP6RTZykBFhBTcRaKvG.jpg")]),
        (actor(2231, "Samuel L. Jackson", "/AiAYAqwpM5xmiFrAIeQvUXDCVvo.jpg", wellKnown: 77), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg")]),
        (actor(8891, "John Travolta", "/ap8eEYfBKTLixmVVpRlq4NslDD5.jpg", wellKnown: 26), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg")]),
        (actor(2975, "Laurence Fishburne", "/2GbXERENPpl5MmlqOLlPVaVtifD.jpg", wellKnown: 36), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg")]),
        (actor(530, "Carrie-Anne Moss", "/9zya72vRZYBQILfetACsnmCBgdj.jpg", wellKnown: 14), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg")]),
        (actor(2037, "Cillian Murphy", "/2lKs67r7FI4bPu0AXxMUJZxmUXn.jpg", wellKnown: 22), [
                    film(872585, "Oppenheimer", 2023, "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg")]),
        (actor(32, "Robin Wright", "/d3rIv0y2p0jMsQ7ViR7O1606NZa.jpg", wellKnown: 19), [
                    film(13, "Forrest Gump", 1994, "/saHP97rTPS5eLmrLQEcANmKrsFl.jpg")]),
        (actor(30614, "Ryan Gosling", "/lyUyVARQKhGxaxy0FbPJCQRpiaW.jpg", wellKnown: 24), [
                    film(346698, "Barbie", 2023, "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg")]),
        ]
        let store = CollectionStore(fileURL: nil)
        for ((person, wellKnown), films) in deck {
            for film in films {
                store.record(chain: [.actor(person), .movie(film)], wellKnownFilms: [person.id: wellKnown])
            }
        }
        return store
    }
}
#endif

#if DEBUG
#Preview("Deck") {
    CollectionView(store: .demo(), bestChain: 11)
}

#Preview("Finishes") {
    let store = CollectionStore.demo()
    HStack(spacing: Theme.Spacing.md) {
        ForEach(store.sortedActors.prefix(3)) { ReelActorCard(entity: $0, model: .rank) }
    }
    .padding(Theme.Spacing.gutter)
    .background(Theme.Color.canvas)
}
#endif
