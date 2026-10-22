//
//  ReelCardsPrototype.swift
//  movie-quiz
//
//  PROTOTYPE — not wired into the app; preview-only. Explores Your Reel as a
//  deck of collectibles: actors as playing cards ranked by the films you've
//  linked *through them*, movies as stamps carrying the actors you linked
//  through them (a reverse reference, no progress).
//
//  Three tier models sit behind the toggle so they can be compared on the same
//  deck. The mock numbers are real: the "well-known" counts are each actor's
//  TMDB credits with 1,000+ votes, as of 2026-10-22.
//
//  Delete this file, or promote pieces of it, once a direction is chosen.
//

import SwiftUI

// MARK: - Mock data

private struct MockFilm: Identifiable, Hashable {
    let title: String
    let year: Int
    var id: String { "\(title)\(year)" }
}

private struct MockActor: Identifiable {
    let id: Int
    let name: String
    let imagePath: String?
    /// Films linked through this actor — the adjacent actor↔movie pairs in your
    /// chains. This is the card's number.
    let linked: [MockFilm]
    /// Their credits with 1,000+ TMDB votes, snapshotted when their filmography
    /// loaded during play. Only the Share model reads it.
    let wellKnown: Int
}

private struct MockMovie: Identifiable {
    let id: Int
    let title: String
    let year: Int
    let posterPath: String?
    /// Actors you've linked through this film. No denominator: a cast runs to
    /// extras, so it could never be completed.
    let linkedActors: [String]
}

private enum Mock {
    static let actors: [MockActor] = [
        MockActor(id: 6384, name: "Keanu Reeves", imagePath: "/8RZLOyYGsoRe9p44q3xin9QkMHv.jpg", linked: [
            MockFilm(title: "The Matrix", year: 1999), MockFilm(title: "John Wick", year: 2014),
            MockFilm(title: "Speed", year: 1994), MockFilm(title: "Point Break", year: 1991),
            MockFilm(title: "The Devil's Advocate", year: 1997), MockFilm(title: "Constantine", year: 2005),
            MockFilm(title: "Bill & Ted's Excellent Adventure", year: 1989),
            MockFilm(title: "The Matrix Reloaded", year: 2003), MockFilm(title: "John Wick: Chapter 2", year: 2017),
            MockFilm(title: "Toy Story 4", year: 2019), MockFilm(title: "Always Be My Maybe", year: 2019),
        ], wellKnown: 48),
        MockActor(id: 31, name: "Tom Hanks", imagePath: "/oFvZoKI6lvU03n4YoNGAll9rkas.jpg", linked: [
            MockFilm(title: "Forrest Gump", year: 1994), MockFilm(title: "Cast Away", year: 2000),
            MockFilm(title: "Toy Story", year: 1995), MockFilm(title: "Saving Private Ryan", year: 1998),
            MockFilm(title: "Big", year: 1988), MockFilm(title: "Catch Me If You Can", year: 2002),
        ], wellKnown: 52),
        MockActor(id: 1373737, name: "Florence Pugh", imagePath: "/1QfiLnofJFlOJOLCWaxyDpIN03v.jpg", linked: [
            MockFilm(title: "Oppenheimer", year: 2023), MockFilm(title: "Little Women", year: 2019),
            MockFilm(title: "Midsommar", year: 2019), MockFilm(title: "Dune: Part Two", year: 2024),
        ], wellKnown: 14),
        MockActor(id: 234352, name: "Margot Robbie", imagePath: "/euDPyqLnuwaWMHajcU3oZ9uZezR.jpg", linked: [
            MockFilm(title: "Barbie", year: 2023), MockFilm(title: "The Wolf of Wall Street", year: 2013),
            MockFilm(title: "Babylon", year: 2022), MockFilm(title: "Once Upon a Time in Hollywood", year: 2019),
        ], wellKnown: 20),
        MockActor(id: 139, name: "Uma Thurman", imagePath: "/sBgAZWi3o4FsnaTvnTNtK6jpQcF.jpg", linked: [
            MockFilm(title: "Pulp Fiction", year: 1994), MockFilm(title: "Kill Bill: Vol. 1", year: 2003),
            MockFilm(title: "Gattaca", year: 1997),
        ], wellKnown: 20),
        MockActor(id: 884, name: "Steve Buscemi", imagePath: "/n0pZumkrcZrAPMoPq684RhYnjPV.jpg", linked: [
            MockFilm(title: "Fargo", year: 1996),
        ], wellKnown: 48),
    ]

    static let movies: [MockMovie] = [
        MockMovie(id: 680, title: "Pulp Fiction", year: 1994, posterPath: "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg",
                  linkedActors: ["Uma Thurman", "Samuel L. Jackson", "John Travolta", "Bruce Willis"]),
        MockMovie(id: 603, title: "The Matrix", year: 1999, posterPath: "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg",
                  linkedActors: ["Keanu Reeves", "Laurence Fishburne", "Carrie-Anne Moss"]),
        MockMovie(id: 872585, title: "Oppenheimer", year: 2023, posterPath: "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg",
                  linkedActors: ["Florence Pugh", "Cillian Murphy"]),
        MockMovie(id: 13, title: "Forrest Gump", year: 1994, posterPath: "/saHP97rTPS5eLmrLQEcANmKrsFl.jpg",
                  linkedActors: ["Tom Hanks", "Robin Wright"]),
        MockMovie(id: 346698, title: "Barbie", year: 2023, posterPath: "/iuFNMS8U5cb6xfzi51Dbkovj7vM.jpg",
                  linkedActors: ["Margot Robbie"]),
        MockMovie(id: 275, title: "Fargo", year: 1996, posterPath: "/rt7cpEr1uP6RTZykBFhBTcRaKvG.jpg",
                  linkedActors: ["Steve Buscemi"]),
    ]
}

// MARK: - Tier models

private enum TierModel: String, CaseIterable, Identifiable {
    /// The count *is* the card's rank: 1 = A … 11 = J, 12 = Q, 13+ = K. Number
    /// cards are paper, 5+ is inked, face cards are holo. Same rule for everyone.
    case rank
    /// Thresholds scale with the actor's well-known films, clamped so a huge
    /// filmography never makes holo unreachable and a tiny one never makes it free.
    case share
    /// No tiers at all: every card is paper, the corner is just the count.
    case plain

    var id: Self { self }

    var label: String {
        switch self {
        case .rank: "Rank"
        case .share: "Share"
        case .plain: "Plain"
        }
    }

    var rule: String {
        switch self {
        case .rank: "Same for everyone. Links are the card's rank, A to K. 5+ is inked; face cards (11+) go holo."
        case .share: "Scaled to each actor: inked at a quarter of their well-known films (2 to 5), holo at half (4 to 10)."
        case .plain: "No tiers. The corner is the count; nothing to complete."
        }
    }
}

private enum Finish { case paper, inked, holo }

private extension MockActor {
    var count: Int { linked.count }

    func finish(_ model: TierModel) -> Finish {
        switch model {
        case .rank:
            if count >= 11 { return .holo }
            return count >= 5 ? .inked : .paper
        case .share:
            if count >= holoAt { return .holo }
            return count >= inkedAt ? .inked : .paper
        case .plain:
            return .paper
        }
    }

    var inkedAt: Int { Self.threshold(wellKnown, share: 0.25, floor: 2, cap: 5) }
    var holoAt: Int { Self.threshold(wellKnown, share: 0.5, floor: 4, cap: 10) }

    static func threshold(_ wellKnown: Int, share: Double, floor: Int, cap: Int) -> Int {
        min(cap, max(floor, Int((Double(wellKnown) * share).rounded(.up))))
    }

    func corner(_ model: TierModel) -> String {
        guard model == .rank else { return "\(count)" }
        switch count {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13...: return "K"
        default: return "\(count)"
        }
    }

    /// The next tier's threshold, for the back of the card. `nil` at the top.
    func nextTier(_ model: TierModel) -> (label: String, at: Int)? {
        switch (model, finish(model)) {
        case (.plain, _), (_, .holo): nil
        case (.rank, .paper): ("Inked", 5)
        case (.rank, .inked): ("Holo", 11)
        case (.share, .paper): ("Inked", inkedAt)
        case (.share, .inked): ("Holo", holoAt)
        }
    }
}

// MARK: - The deck

struct ReelDeckPrototype: View {
    @State private var model: TierModel = .rank
    @State private var selected: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 2)

    var body: some View {
        ZStack {
            Theme.Color.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    SplitHeading(roman: "Your", flourish: "Reel", style: .title)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        NeoSegmented(selection: $model,
                                     options: TierModel.allCases.map { ($0, $0.label) })
                        Text(model.rule)
                            .font(Theme.Font.flourish(.footnote))
                            .foregroundStyle(Theme.Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Actors").metaLabel()
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(Mock.actors) { actor in
                            Button {
                                withAnimation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.emphasized) {
                                    selected = actor.id
                                }
                            } label: {
                                ActorCard(actor: actor, model: model, tilt: .zero)
                            }
                            .buttonStyle(.pressScale)
                            .opacity(selected == actor.id ? 0 : 1)
                        }
                    }

                    Text("Movies").metaLabel()
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(Mock.movies) { MovieStamp(movie: $0) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.md)
            }

            if let id = selected, let actor = Mock.actors.first(where: { $0.id == id }) {
                CardDetail(actor: actor, model: model) {
                    withAnimation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.standard) {
                        selected = nil
                    }
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                .zIndex(1)
            }
        }
    }
}

// MARK: - Actor card (playing card)

private struct ActorCard: View {
    let actor: MockActor
    let model: TierModel
    /// Live tilt for the expanded card; the grid passes `.zero` so a deck full of
    /// holo never runs the gyro.
    let tilt: CGSize
    var large = false

    private var finish: Finish { actor.finish(model) }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            art
            Text(actor.name)
                .font(Theme.Font.heading(large ? .title3 : .subheadline))
                .foregroundStyle(finish == .holo ? Theme.Color.onAccent : Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if model != .plain { pips }
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .neoSurface(radius: Theme.Radius.md, fill: .clear,
                    shadow: large ? Theme.Shadow.large : Theme.Shadow.small)
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(actor.name), \(actor.count) films linked")
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
            Text(actor.corner(model))
                .font(Theme.Font.numeral(large ? .title2 : .headline))
                .monospacedDigit()
            Image(systemName: "film.fill")
                .font(.system(size: large ? 11 : 8))
        }
        .foregroundStyle(finish == .holo ? Theme.Color.onAccent : Theme.Color.ink)
        .fixedSize()
    }

    private var art: some View {
        ZStack {
            Theme.Color.actor
            if let url = Config.imageURL(path: actor.imagePath, size: large ? "w342" : "w185") {
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
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
            .strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
    }

    private var monogram: some View {
        Text(actor.name.split(separator: " ").compactMap(\.first).map(String.init).joined())
            .font(Theme.Font.display(28))
            .foregroundStyle(.white.opacity(0.7))
    }

    /// One pip per linked film, up to ten. Share fills a ten-segment bar toward
    /// the holo threshold instead, so the pips mean "how close", not "how many".
    private var pips: some View {
        let total = 10
        let filled: Int = switch model {
        case .share: min(total, Int((Double(actor.count) / Double(actor.holoAt) * Double(total)).rounded()))
        default: min(total, actor.count)
        }
        return HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filled ? Theme.Color.ink : Theme.Color.ink.opacity(0.12))
                    .frame(height: large ? 6 : 4)
            }
        }
    }
}

// MARK: - Expanded card (flips to the ledger)

private struct CardDetail: View {
    let actor: MockActor
    let model: TierModel
    let dismiss: () -> Void

    @State private var flipped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var live: Bool { !reduceMotion && TiltMotion.shared.isAvailable && actor.finish(model) == .holo }

    var body: some View {
        ZStack {
            Theme.Color.canvas.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: Theme.Spacing.lg) {
                Group {
                    if reduceMotion {
                        // No rotation: the faces cross-fade.
                        ZStack {
                            front.opacity(flipped ? 0 : 1)
                            back.opacity(flipped ? 1 : 0)
                        }
                    } else {
                        FlipView(angle: flipped ? 180 : 0, front: front, back: back)
                    }
                }
                .frame(width: 270)
                .onTapGesture { toggle() }

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
        ActorCard(actor: actor, model: model,
                  tilt: live ? TiltMotion.shared.tilt : .zero, large: true)
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Linked through").metaLabel(size: .small)
            Text(actor.name)
                .font(Theme.Font.heading(.title3))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Rectangle().fill(Theme.Color.border).frame(height: Theme.Border.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(actor.linked) { film in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Color.movie)
                                .overlay(RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Theme.Color.border, lineWidth: 1))
                                .frame(width: 8, height: 8)
                            Text(film.title)
                                .font(Theme.Font.bodyStrong)
                                .foregroundStyle(Theme.Color.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(String(film.year))
                                .font(Theme.Font.flourish(.footnote))
                                .foregroundStyle(Theme.Color.muted)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.tile)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .neoSurface(radius: Theme.Radius.md, fill: .clear, shadow: Theme.Shadow.large)
        .aspectRatio(5.0 / 7.0, contentMode: .fit)
    }

    /// The only place a denominator appears, and only in Share. No missing titles
    /// are listed: that would turn the Reel into a study sheet for the next run.
    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model == .share {
                Text("\(actor.count) of ~\(actor.wellKnown) well-known films")
                    .font(Theme.Font.numeral(.subheadline))
                    .foregroundStyle(Theme.Color.ink)
            } else {
                Text("\(actor.count) \(actor.count == 1 ? "film" : "films") linked")
                    .font(Theme.Font.numeral(.subheadline))
                    .foregroundStyle(Theme.Color.ink)
            }
            if let next = actor.nextTier(model) {
                Text("\(next.label) at \(next.at) · \(next.at - actor.count) to go")
                    .font(Theme.Font.flourish(.footnote))
                    .foregroundStyle(Theme.Color.muted)
            }
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

private struct MovieStamp: View {
    let movie: MockMovie

    var body: some View {
        let edge = PerforatedEdge(radius: 4)
        VStack(alignment: .leading, spacing: 6) {
            poster
            Text(movie.title)
                .font(Theme.Font.heading(.subheadline))
                .foregroundStyle(Theme.Color.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            linkedThrough
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
        .overlay(alignment: .topTrailing) { denomination }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(movie.title), linked through \(movie.linkedActors.formatted(.list(type: .and)))")
    }

    private var poster: some View {
        ZStack {
            Theme.Color.movie
            if let url = Config.imageURL(path: movie.posterPath) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "film.fill").foregroundStyle(Theme.Color.onAccent.opacity(0.5))
                    }
                }
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipped()
        .overlay(Rectangle().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
    }

    /// The postmark: the year, like a stamp's issue date.
    private var denomination: some View {
        Text(String(movie.year))
            .font(Theme.Font.flourish(.caption))
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Theme.Color.tile))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1.5))
            .rotationEffect(.degrees(8))
            .offset(x: -4, y: 4)
    }

    /// Reverse reference: who you linked through this film. Faces, no count.
    private var linkedThrough: some View {
        HStack(spacing: -6) {
            ForEach(movie.linkedActors.prefix(4), id: \.self) { name in
                Text(name.split(separator: " ").compactMap(\.first).map(String.init).joined())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.Color.actor))
                    .overlay(Circle().strokeBorder(Theme.Color.border, lineWidth: 1.5))
            }
        }
    }
}

/// A rectangle whose edges are bitten by evenly spaced semicircles, like a
/// stamp torn from its sheet.
private struct PerforatedEdge: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var holes = Path()
        let pitch = radius * 2.8
        func bite(_ center: CGPoint) {
            holes.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2))
        }
        let across = max(1, Int(rect.width / pitch))
        let down = max(1, Int(rect.height / pitch))
        let dx = rect.width / CGFloat(across)
        let dy = rect.height / CGFloat(down)
        for i in 0..<across {
            let x = rect.minX + dx * (CGFloat(i) + 0.5)
            bite(CGPoint(x: x, y: rect.minY))
            bite(CGPoint(x: x, y: rect.maxY))
        }
        for j in 0..<down {
            let y = rect.minY + dy * (CGFloat(j) + 0.5)
            bite(CGPoint(x: rect.minX, y: y))
            bite(CGPoint(x: rect.maxX, y: y))
        }
        return Path(rect).subtracting(holes)
    }
}

// MARK: - Previews

#Preview("Reel deck") {
    ReelDeckPrototype()
}

#Preview("One of each finish") {
    HStack(spacing: Theme.Spacing.md) {
        ActorCard(actor: Mock.actors[5], model: .rank, tilt: .zero)
        ActorCard(actor: Mock.actors[1], model: .rank, tilt: .zero)
        ActorCard(actor: Mock.actors[0], model: .rank, tilt: .zero)
    }
    .padding(Theme.Spacing.gutter)
    .background(Theme.Color.canvas)
}
