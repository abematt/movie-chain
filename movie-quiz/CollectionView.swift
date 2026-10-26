//
//  CollectionView.swift
//  movie-quiz
//
//  "Your Reel" — the collection screen. Every actor/movie the player has logged
//  through play, with pure count stats on top ("look how many you know"):
//  actors as a deck of playing cards earned through the films linked through
//  them, movies as framed posters, three across (`ReelCards.swift`), narrowed by decade and
//  genre. Presented as a sheet from the seed and
//  game-over screens.
//
//  Built entirely on the `Theme` tokens and the node-category identity (blue =
//  actor, yellow = movie), matching the Cream Neobrutalist treatment used
//  everywhere else. Images stream in via `AsyncImage` (system-cached, never
//  stored on disk); when there's no art — the stub graph, or a title TMDB has no
//  poster for — the tile falls back to a typographic placeholder.
//

import SwiftUI

struct CollectionView: View {
    let store: CollectionStore
    /// Personal best chain length, surfaced here now that it's off the home
    /// screen. `0` (never played) hides the line.
    var bestChain: Int = 0
    /// Where the sheet was opened from, for analytics.
    var openedFrom: Telemetry.Screen = .home

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.telemetry) private var telemetry
    @State private var filter: Filter = .actors
    /// Decade and genre narrowing, shared by both tabs.
    @State private var narrow = ReelFilter()
    /// The card or frame lifted out of the grid — set for the whole time it's
    /// out, including its flight home — whether it's on the way back, and
    /// whether it's turned over.
    @State private var expanded: CollectedEntity.ID?
    @State private var closing = false
    @State private var flipped = false
    /// Where each grid card sits on screen, for the lift to start from and
    /// land on. A plain object, so measuring never re-renders the grid.
    @State private var slots = SlotFrames()
    /// Gates the hero numbers so they roll up from 0 on first appear.
    @State private var statsIn = false

    /// Fade art in as it streams from the network. A fade isn't movement, so it
    /// stays under Reduce Motion — it hides *when* the image happened to arrive.
    private var imageTransaction: Transaction {
        Transaction(animation: .easeOut(duration: 0.2))
    }

    enum Filter: String, CaseIterable, Identifiable {
        case actors, movies
        var id: String { rawValue }
        var label: String {
            switch self {
            case .actors: "Actors"
            case .movies: "Movies"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            hero
                            regulars
                            filterControl
                            narrowControls
                            grids
                            TMDBAttribution()
                        }
                        .padding(.horizontal, Theme.Spacing.gutter)
                        .padding(.vertical, Theme.Spacing.md)
                        .onAppear {
                            guard !statsIn else { return }
                            if reduceMotion { statsIn = true }
                            else { withAnimation(Theme.Motion.emphasized) { statsIn = true } }
                        }
                    }
                    #if DEBUG
                    // QA hook: lift the first actor card a moment after opening,
                    // to watch the lift and the tilt without tapping.
                    .task {
                        guard ProcessInfo.processInfo.arguments.contains("-uiLiftFirst"),
                              let first = store.actors(matching: narrow).first else { return }
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else { return }
                        expand(first.id)
                    }
                    #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.canvas.ignoresSafeArea())
            .sheetHeader("Your Reel") {
                Button("Done") { dismiss() }
                    .frame(minHeight: 44)
            } trailing: {
                if !store.isEmpty {
                    ShareLink(item: store.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Share your Reel")
                    .simultaneousGesture(TapGesture().onEnded {
                        telemetry?.shared(from: .reel)
                    })
                }
            }
            // Over the header too: the dark room is the whole sheet, so Done and
            // Share don't stay lit (and live) while a card is out.
            .overlay { detail }
        }
        // What was looked at, and for how long: one `card_viewed` per card put
        // back, one `reel_closed` for the visit.
        .onChange(of: flipped) { _, over in if over { telemetry?.cardFlipped() } }
        .onChange(of: filter) { _, tab in telemetry?.reelFiltered("tab:\(tab.rawValue)") }
        .onChange(of: narrow.decade) { _, decade in
            if let decade { telemetry?.reelFiltered("decade:\(decade)") }
        }
        .onChange(of: narrow.genre) { _, genre in
            if let genre { telemetry?.reelFiltered("genre:\(genre)") }
        }
        .onAppear { telemetry?.reelOpened(from: openedFrom) }
        .onDisappear { telemetry?.reelClosed() }
    }

    // MARK: Hero — the flex line + best chain
    //
    // Each fact appears once on this sheet: the total here, the per-kind counts
    // only in the Actors / Movies tabs, and no header repeating them above the
    // grid.

    // Scale is the drama: the count huge and left-set, what it means in a
    // quiet line beside it.
    private var hero: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.md - 4) {
            Text("\(statsIn ? store.total : 0)")
                .font(Theme.Font.display(116))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(store.total)))
                .foregroundStyle(Theme.Color.ink)
                .padding(.bottom, -18)
            // Set like the home's best run: condensed caps, the figures in ink.
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged across")
                stat(store.chainsLogged, store.chainsLogged == 1 ? "chain" : "chains")
                if bestChain > 0 {
                    stat(bestChain, bestChain == 1 ? "link" : "links", lead: "Best run")
                }
            }
            .font(Theme.Font.button)
            .textCase(.uppercase)
            .tracking(Theme.Font.buttonTracking)
            .foregroundStyle(Theme.Color.muted)
            .lineLimit(1)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Best run 13 links": the figure in ink numerals between quiet caps.
    private func stat(_ value: Int, _ unit: String, lead: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm - 2) {
            if let lead { Text(lead) }
            Text("\(value)")
                .font(Theme.Font.numeral(.title3))
                .foregroundStyle(Theme.Color.ink)
            Text(unit)
        }
    }

    // MARK: Regulars — most-logged actor + movie

    @ViewBuilder private var regulars: some View {
        if store.mostLoggedActor != nil || store.mostLoggedMovie != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Heading("Your regulars")
                HStack(spacing: Theme.Spacing.sm) {
                    if let a = store.mostLoggedActor { regularCard(a) }
                    if let m = store.mostLoggedMovie { regularCard(m) }
                }
                // Both cards take the taller one's height, so a two-line name
                // doesn't leave its neighbour short.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func regularCard(_ entity: CollectedEntity) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            thumb(entity)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.kind.tileLabel).metaLabel(size: .small)
                Text(entity.name)
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
                    // Two lines: at the 24pt gutter a half-width card truncates
                    // ordinary names ("Hugh Jac…") on one.
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                Text("in \(entity.timesLogged) \(entity.timesLogged == 1 ? "chain" : "chains")")
                    .font(Theme.Font.sentence(.footnote))
                    .foregroundStyle(Theme.Color.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm + 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
    }

    private func thumb(_ entity: CollectedEntity) -> some View {
        ZStack {
            entity.kind.accent
            if let url = Config.imageURL(path: entity.imagePath, size: "w185") {
                AsyncImage(url: url, transaction: imageTransaction) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: entity.kind.symbol)
                            .foregroundStyle(entity.kind.onAccent.opacity(0.6))
                    }
                }
            } else {
                Image(systemName: entity.kind.symbol)
                    .foregroundStyle(entity.kind.onAccent.opacity(0.7))
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
            .strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
    }

    // MARK: Filter

    private var filterControl: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Filter.allCases) { f in
                Button {
                    withAnimation(Theme.Motion.standard) { filter = f }
                } label: {
                    HStack(spacing: 5) {
                        Text(f.label)
                        Text("\(count(for: f))")
                            .font(Theme.Font.numeral(.subheadline))
                            .contentTransition(.numericText(value: Double(count(for: f))))
                            .opacity(0.6)
                            .monospacedDigit()
                    }
                    .font(Theme.Font.button)
                    .textCase(.uppercase)
                    .tracking(Theme.Font.buttonTracking)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .foregroundStyle(filter == f ? Theme.Color.onInk : Theme.Color.muted)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(filter == f ? Theme.Color.ink : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
    }

    /// Counts follow the decade and genre narrowing, so each tab says what's
    /// under it.
    private func count(for f: Filter) -> Int {
        switch f {
        case .actors: store.actors(matching: narrow).count
        case .movies: store.movies(matching: narrow).count
        }
    }

    // MARK: Narrow — decade and genre
    //
    // Two menus under the tabs. Both describe films; on the Actors tab they keep
    // the actors linked through a matching film. The options come from the Reel
    // itself, so a choice never comes up empty.

    @ViewBuilder private var narrowControls: some View {
        if !store.decades.isEmpty || !store.genres.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    Picker("Decade", selection: $narrow.decade) {
                        Text("Any decade").tag(Int?.none)
                        ForEach(store.decades, id: \.self) { Text(decadeName($0)).tag(Int?.some($0)) }
                    }
                } label: {
                    pill(narrow.decade.map(decadeName) ?? "Decade", active: narrow.decade != nil)
                }
                Menu {
                    Picker("Genre", selection: $narrow.genre) {
                        Text("Any genre").tag(Int?.none)
                        ForEach(genreOptions, id: \.id) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                } label: {
                    pill(narrow.genre.flatMap(ReelGenre.name) ?? "Genre", active: narrow.genre != nil)
                }
                Spacer(minLength: 0)
                if narrow.isActive {
                    Button("Clear") { narrow = ReelFilter() }
                        .font(Theme.Font.bodyStrong)
                        .foregroundStyle(Theme.Color.ink)
                        .transition(.opacity)
                }
            }
            .animation(Theme.Motion.standard, value: narrow)
        }
    }

    private var genreOptions: [(id: Int, name: String)] {
        store.genres
            .compactMap { id in ReelGenre.name(id).map { (id: id, name: $0) } }
            .sorted { $0.name < $1.name }
    }

    private func decadeName(_ decade: Int) -> String { "\(String(decade))s" }

    private func pill(_ title: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .font(Theme.Font.button)
        .textCase(.uppercase)
        .tracking(Theme.Font.buttonTracking)
        .foregroundStyle(active ? Theme.Color.onInk : Theme.Color.ink)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .neoSurface(radius: Theme.Radius.pill, fill: active ? Theme.Color.ink : Theme.Color.tile,
                    shadow: Theme.Shadow.small)
    }

    // MARK: Grids

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm + 2), count: 3)
    }

    @ViewBuilder private var grids: some View {
        Group {
            switch filter {
            case .actors:
                deck
            case .movies:
                frames
            }
        }
        // Give each filter its own identity so switching cross-fades the grids
        // rather than reflowing one grid's contents into the other's. Nothing
        // cascades in: the cards arrive with the sheet, and only their art
        // fades in, the first time, as it lands (`ArtCache`).
        .id(filter)
        .transition(.opacity)
        .animation(Theme.Motion.standard, value: narrow)
    }

    // The tabs above already name the kind and its count, so neither grid
    // carries a header of its own. A card that's out stays in its slot, unseen,
    // until its lifted copy has landed back on it — never rebuilt, so its art is
    // just there.
    @ViewBuilder private var deck: some View {
        let actors = store.actors(matching: narrow)
        // From the whole Reel, so a card keeps its number under any filter.
        let numbers = ReelNumber.numbers(for: store.sortedActors)
        if actors.isEmpty {
            nothingMatches
        } else {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(actors) { entity in
                    Button { expand(entity.id) } label: {
                        ReelCanvas(aspect: ReelActorCard.aspect) {
                            ReelActorCard(entity: entity, number: numbers[entity.id],
                                          isNew: store.isNew(entity))
                        }
                        .modifier(Slot(id: entity.id, slots: slots, out: expanded == entity.id))
                    }
                    .buttonStyle(.reelPress)
                }
            }
        }
    }

    @ViewBuilder private var frames: some View {
        let movies = store.movies(matching: narrow)
        if movies.isEmpty {
            nothingMatches
        } else {
            LazyVGrid(columns: columns, alignment: .center, spacing: Theme.Spacing.lg) {
                ForEach(movies) { entity in
                    Button { expand(entity.id) } label: {
                        VStack(spacing: Theme.Spacing.xs + 2) {
                            ReelCanvas(aspect: ReelFrame.aspect) {
                                ReelFrame(entity: entity, isNew: store.isNew(entity))
                            }
                            // The label stays on the wall while its frame is out.
                            .modifier(Slot(id: entity.id, slots: slots, out: expanded == entity.id))
                            ReelFrameCaption(entity: entity)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.reelPress)
                }
            }
        }
    }

    /// Only reachable through the narrowing — e.g. actors on the Movies-only
    /// side of a filter that matches no linked film.
    private var nothingMatches: some View {
        Text("Nothing here yet. Try another decade or genre.")
            .font(Theme.Font.sentence(.subheadline))
            .foregroundStyle(Theme.Color.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
    }

    /// The lifted card with its backdrop and controls, drawn over the whole
    /// sheet. It flies itself out of its slot and back (see `ReelCardDetail`).
    @ViewBuilder private var detail: some View {
        if let id = expanded, let entity = store.entities[id] {
            ReelCardDetail(entity: entity,
                           number: ReelNumber.numbers(for: store.sortedActors)[entity.id],
                           linked: store.linked(to: entity),
                           slot: slots.frames[id], closing: closing,
                           flipped: $flipped, close: { expand(nil) })
        }
    }

    /// Flying home: quick and unbouncy — the system putting the card back.
    private static let homeFlight: Animation = .spring(duration: 0.28, bounce: 0)

    /// Lift a card out (`id`), or send the one that's out home (`nil`). Picking
    /// a card up is the deliberate moment and the detail runs its own open;
    /// putting it back is the system answering, so it goes home quickly — a
    /// flipped card turning to its front on the way — and only when it has
    /// landed is it removed and the grid card shown again.
    private func expand(_ id: CollectedEntity.ID?) {
        if let id {
            guard expanded == nil else { return }
            Haptics.lift()
            flipped = false
            expanded = id
            if let entity = store.entities[id] {
                telemetry?.cardLifted(entity)
            }
            return
        }
        guard expanded != nil, !closing else { return }
        telemetry?.cardPutDown()
        withAnimation(reduceMotion ? Theme.Motion.reducedFade : Self.homeFlight) {
            closing = true
            flipped = false
        } completion: {
            expanded = nil
            closing = false
        }
    }

    // MARK: Helpers

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "film.stack")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Color.muted)
                Heading("Your reel is empty")
                Text("Finish a chain and every actor and movie you named lands here.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.muted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            // Attribution stays reachable even before the first chain is logged.
            TMDBAttribution()
        }
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - TMDB attribution
//
// TMDB's API Terms of Use require crediting them as the data source in-app, with
// their logo and the standard non-endorsement disclaimer. The wording is §3's
// exactly — the FAQ's shorter line isn't the contract. It lives in the Reel sheet
// and in Settings → About, the calm secondary surfaces, so it stays out of the
// deliberately play-first home while remaining visible in the app (compliant:
// the terms only require it be shown prominently, not that it be on the home screen).
//
// The logo is TMDB's official "long" gradient wordmark, added to the asset
// catalog as a vector SVG (`TMDBLogo`, from themoviedb.org/about/logos-attribution).
// Its brand gradient reads on both the warm-paper and dark canvases, so it's
// rendered as-is (full color, not tinted).
struct TMDBAttribution: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Rectangle().fill(Theme.Color.border).frame(height: Theme.Border.width)
            Image("TMDBLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 14)
                .accessibilityLabel("The Movie Database (TMDB)")
            Text("This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.")
                .font(Theme.Font.sentence(.caption))
                .foregroundStyle(Theme.Color.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    CollectionView(store: .demo(), bestChain: 11)
}
#endif

// MARK: - Grid slots

/// Where each grid card is on screen. Deliberately not observed: the grid
/// measures into it as it lays out and scrolls, and that must never re-render.
final class SlotFrames {
    var frames: [CollectedEntity.ID: CGRect] = [:]
}

/// A grid card's slot: records where it is on screen for the lift, and keeps it
/// unseen (but in place) while its lifted copy is out.
private struct Slot: ViewModifier {
    let id: CollectedEntity.ID
    let slots: SlotFrames
    let out: Bool

    func body(content: Content) -> some View {
        content
            .opacity(out ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                slots.frames[id] = frame
            }
    }
}
