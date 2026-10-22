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
//  No numbers are printed on the front: the card's finish is the reward. `ReelTier`
//  is the pure part (which finish a card earns) and is unit-tested; the views
//  only draw what it decides. The tier model is a setting for now — Rank, Share
//  or Plain — so the three can be compared in real play before one is kept.
//

import SwiftUI

// MARK: - Tiers (pure)

/// How an actor card earns its finish. A player setting while the three are
/// compared (Settings → Reel cards).
enum ReelTierModel: String, CaseIterable, Identifiable {
    /// The same thresholds for everyone.
    case rank
    /// Thresholds scale with the actor's well-known films, clamped so a huge
    /// filmography never puts holo out of reach and a small one never gives it away.
    case share
    /// No tiers: every card is paper.
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
        case .rank: "The same for everyone: inked at 5 films linked, holo at 11."
        case .share: "Scaled to each actor: inked at a quarter of their well-known films, holo at half."
        case .plain: "No tiers. Every card is paper."
        }
    }
}

/// The finish a card is printed in, lowest first.
enum ReelFinish: Comparable {
    case paper, inked, holo
}

enum ReelTier {
    /// Rank's thresholds: inked from 5 links, holo from 11.
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
        .padding(large ? 22 : 14)
        .background { face }
        .overlay(alignment: .topTrailing) { if isNew { NewBadge().padding(6) } }
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
}

// MARK: - Movie frame

/// A poster hung in a picture frame: an ink moulding, a white mat, the poster
/// behind it. The caption sits under the frame in the grid, like a wall label.
struct ReelFrame: View {
    let entity: CollectedEntity
    var large = false
    var isNew = false

    var body: some View {
        ReelArt(path: entity.imagePath, kind: .movie, name: entity.name, size: large ? "w500" : "w342")
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipped()
            .overlay(Rectangle().strokeBorder(Theme.Color.border, lineWidth: 1))
            // The mat.
            .padding(large ? 18 : 10)
            .background(Theme.Color.tile)
            // The moulding, with a hairline inner edge where it meets the mat.
            .overlay(Rectangle().strokeBorder(Theme.Color.hairline, lineWidth: 1).padding(1))
            .padding(large ? 10 : 6)
            .background(Theme.Color.ink)
            .background(Rectangle().fill(Theme.Color.shadow)
                .offset(x: large ? Theme.Shadow.large : Theme.Shadow.small,
                        y: large ? Theme.Shadow.large : Theme.Shadow.small))
            .overlay(alignment: .topTrailing) { if isNew { NewBadge().offset(x: 4, y: -6) } }
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
                .font(Theme.Font.heading(.subheadline))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let year = entity.year {
                Text(String(year))
                    .font(Theme.Font.flourish(.footnote))
                    .foregroundStyle(Theme.Color.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Expanded card (flips to what's behind it)

/// An actor card or framed poster lifted out of the grid. Tap it (or Flip) to
/// turn it over: an actor's back lists the films linked through them, a movie's
/// the actors. Holo cards catch the light here, and only here.
struct ReelCardDetail: View {
    let entity: CollectedEntity
    let linked: [CollectedEntity]
    let model: ReelTierModel
    let dismiss: () -> Void

    @State private var flipped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var links: Int { entity.links.count }
    private var isActor: Bool { entity.kind == .actor }
    private var live: Bool {
        isActor && !reduceMotion && TiltMotion.shared.isAvailable
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
                        front.opacity(flipped ? 0 : 1)
                            .overlay { back.opacity(flipped ? 1 : 0) }
                    } else {
                        FlipView(angle: flipped ? 180 : 0, front: front, back: back)
                    }
                }
                .frame(width: isActor ? 270 : 250)
                .onTapGesture(perform: toggle)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(flipped ? "Shows the front"
                                   : isActor ? "Shows the films linked through them"
                                   : "Shows the actors linked through it")

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

    @ViewBuilder private var front: some View {
        if isActor {
            ReelActorCard(entity: entity, model: model,
                          tilt: live ? TiltMotion.shared.tilt : .zero, large: true)
        } else {
            ReelFrame(entity: entity, large: true)
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
                    .font(Theme.Font.flourish(.footnote))
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
        .neoSurface(radius: isActor ? Theme.Radius.md : 0, fill: .clear, shadow: Theme.Shadow.large)
    }

    @ViewBuilder private func row(_ other: CollectedEntity) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            if other.kind == .actor {
                ReelArt(path: other.imagePath, kind: .actor, name: other.name, size: "w92", monogramSize: 10)
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
                    .font(Theme.Font.flourish(.footnote))
                    .foregroundStyle(Theme.Color.muted)
            }
        }
    }

    /// The only place a denominator appears, and only in Share. Missing titles
    /// are never listed: that would turn the Reel into a study sheet for the
    /// next run.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isActor, model == .share, let known = entity.wellKnownFilms {
                    Text("\(links) of ~\(known) well-known films")
                } else if isActor {
                    Text("\(links) \(links == 1 ? "film" : "films") linked")
                } else {
                    Text("\(links) \(links == 1 ? "actor" : "actors") linked")
                }
            }
            .font(Theme.Font.numeral(.subheadline))
            .foregroundStyle(Theme.Color.ink)

            Text("In \(entity.timesLogged) \(entity.timesLogged == 1 ? "chain" : "chains")")
                .font(Theme.Font.flourish(.footnote))
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

// MARK: - Pieces

private struct NewBadge: View {
    var body: some View {
        Text("New")
            .metaLabel(Theme.Color.onAccent, size: .small)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Color.good))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
    }
}

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
    /// The well-known counts and genres are real (TMDB, 2026-10-22).
    static func demo() -> CollectionStore {
        func actor(_ id: Int, _ name: String, _ path: String?, wellKnown: Int) -> (Person, Int) {
            (Person(id: id, name: name, imagePath: path), wellKnown)
        }
        func film(_ id: Int, _ title: String, _ year: Int, _ path: String?, _ genres: [Int]) -> Movie {
            Movie(id: id, title: title, year: year, imagePath: path, genreIDs: genres)
        }
        let deck: [((Person, Int), [Movie])] = [
        (actor(6384, "Keanu Reeves", "/8RZLOyYGsoRe9p44q3xin9QkMHv.jpg", wellKnown: 48), [
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
        (actor(31, "Tom Hanks", "/oFvZoKI6lvU03n4YoNGAll9rkas.jpg", wellKnown: 52), [
                    film(13, "Forrest Gump", 1994, "/saHP97rTPS5eLmrLQEcANmKrsFl.jpg", [35, 18, 10749]),
                    film(8358, "Cast Away", 2000, "/7lLJgKnAicAcR5UEuo8xhSMj18w.jpg", [12, 18]),
                    film(862, "Toy Story", 1995, "/uXDfjJbdP4ijW5hWSBrPrlKpxab.jpg", [10751, 35, 16, 12]),
                    film(857, "Saving Private Ryan", 1998, "/uqx37cS8cpHg8U35f9U5IBlrCV3.jpg", [10752, 18, 36]),
                    film(2280, "Big", 1988, "/eWhCDJiwxvx3YXkAFRiHjimnF0j.jpg", [14, 18, 35]),
                    film(640, "Catch Me If You Can", 2002, "/ctjEj2xM32OvBXCq8zAdK3ZrsAj.jpg", [18, 80])]),
        (actor(1373737, "Florence Pugh", "/1QfiLnofJFlOJOLCWaxyDpIN03v.jpg", wellKnown: 14), [
                    film(872585, "Oppenheimer", 2023, "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", [18, 36, 10752]),
                    film(331482, "Little Women", 2019, "/yn5ihODtZ7ofn8pDYfxCmxh8AXI.jpg", [18, 10749]),
                    film(530385, "Midsommar", 2019, "/7LEI8ulZzO5gy9Ww2NVCrKmHeDZ.jpg", [27, 18, 9648]),
                    film(693134, "Dune: Part Two", 2024, "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", [878, 12])]),
        (actor(234352, "Margot Robbie", "/euDPyqLnuwaWMHajcU3oZ9uZezR.jpg", wellKnown: 20), [
                    film(346698, "Barbie", 2023, "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg", [35, 12, 14]),
                    film(106646, "The Wolf of Wall Street", 2013, "/kW9LmvYHAaS9iA0tHmZVq8hQYoq.jpg", [80, 18, 35]),
                    film(615777, "Babylon", 2022, "/wjOHjWCUE0YzDiEzKv8AfqHj3ir.jpg", [18, 35]),
                    film(466272, "Once Upon a Time in Hollywood", 2019, "/8j58iEBw9pOXFD2L0nt0ZXeHviB.jpg", [35, 18, 53])]),
        (actor(139, "Uma Thurman", "/sBgAZWi3o4FsnaTvnTNtK6jpQcF.jpg", wellKnown: 20), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", [53, 80, 35]),
                    film(24, "Kill Bill: Vol. 1", 2003, "/v7TaX8kXMXs5yFFGR41guUDNcnB.jpg", [28, 80]),
                    film(782, "Gattaca", 1997, "/eSKr5Fl1MEC7zpAXaLWBWSBjgJq.jpg", [878, 18])]),
        (actor(884, "Steve Buscemi", "/n0pZumkrcZrAPMoPq684RhYnjPV.jpg", wellKnown: 48), [
                    film(275, "Fargo", 1996, "/rt7cpEr1uP6RTZykBFhBTcRaKvG.jpg", [80, 18, 53])]),
        (actor(2231, "Samuel L. Jackson", "/AiAYAqwpM5xmiFrAIeQvUXDCVvo.jpg", wellKnown: 77), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", [53, 80, 35])]),
        (actor(8891, "John Travolta", "/ap8eEYfBKTLixmVVpRlq4NslDD5.jpg", wellKnown: 26), [
                    film(680, "Pulp Fiction", 1994, "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", [53, 80, 35])]),
        (actor(2975, "Laurence Fishburne", "/2GbXERENPpl5MmlqOLlPVaVtifD.jpg", wellKnown: 36), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", [28, 878])]),
        (actor(530, "Carrie-Anne Moss", "/9zya72vRZYBQILfetACsnmCBgdj.jpg", wellKnown: 14), [
                    film(603, "The Matrix", 1999, "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", [28, 878])]),
        (actor(2037, "Cillian Murphy", "/2lKs67r7FI4bPu0AXxMUJZxmUXn.jpg", wellKnown: 22), [
                    film(872585, "Oppenheimer", 2023, "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", [18, 36, 10752])]),
        (actor(32, "Robin Wright", "/d3rIv0y2p0jMsQ7ViR7O1606NZa.jpg", wellKnown: 19), [
                    film(13, "Forrest Gump", 1994, "/saHP97rTPS5eLmrLQEcANmKrsFl.jpg", [35, 18, 10749])]),
        (actor(30614, "Ryan Gosling", "/lyUyVARQKhGxaxy0FbPJCQRpiaW.jpg", wellKnown: 24), [
                    film(346698, "Barbie", 2023, "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg", [35, 12, 14])]),
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

#Preview("Deck") {
    CollectionView(store: .demo(), bestChain: 11)
}

#Preview("Card and frame") {
    let store = CollectionStore.demo()
    HStack(alignment: .top, spacing: Theme.Spacing.md) {
        if let actor = store.sortedActors.first { ReelActorCard(entity: actor, model: .rank) }
        if let movie = store.sortedMovies.first {
            VStack(spacing: Theme.Spacing.sm) {
                ReelFrame(entity: movie)
                ReelFrameCaption(entity: movie)
            }
        }
    }
    .padding(Theme.Spacing.gutter)
    .background(Theme.Color.canvas)
}
#endif
