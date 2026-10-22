//
//  CollectionView.swift
//  movie-quiz
//
//  "Your Reel" — the collection screen. Every actor/movie the player has logged
//  through play, with pure count stats on top ("look how many you know"):
//  actors as a deck of playing cards earned through the films linked through
//  them, movies as framed posters (`ReelCards.swift`), narrowed by decade and
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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: Filter = .actors
    @AppStorage("reelTiers") private var tierModel: ReelTierModel = .rank
    /// Decade and genre narrowing, shared by both tabs.
    @State private var narrow = ReelFilter()
    /// The card or frame lifted out of the grid, if any.
    @State private var expanded: CollectedEntity.ID?
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
                    .overlay { detail }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.canvas.ignoresSafeArea())
            .navigationTitle("Your Reel")
            .toolbarTitleDisplayMode(.inline)
            .neoNavigationBar { SplitHeading(roman: "Your", flourish: "Reel", style: .headline) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Done").font(Theme.Font.bodyStrong).foregroundStyle(Theme.Color.ink)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !store.isEmpty {
                        ShareLink(item: store.shareText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    // MARK: Hero — the flex line + best chain
    //
    // Each fact appears once on this sheet: the total here, the per-kind counts
    // only in the Actors / Movies tabs, and no header repeating them above the
    // grid.

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("You have logged")
                    .font(Theme.Font.flourish(.body))
                    .foregroundStyle(Theme.Color.muted)
                Text("\(statsIn ? store.total : 0)")
                    .font(Theme.Font.display(64))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(store.total)))
                    .foregroundStyle(Theme.Color.ink)
            }

            if bestChain > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Color.muted)
                    Text("Best chain").metaLabel()
                    Text("\(bestChain) links")
                        .font(Theme.Font.numeral(.subheadline))
                        .foregroundStyle(Theme.Color.ink)
                }
            }
        }
    }

    // MARK: Regulars — most-logged actor + movie

    @ViewBuilder private var regulars: some View {
        if store.mostLoggedActor != nil || store.mostLoggedMovie != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SplitHeading(roman: "Your", flourish: "regulars")
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
                    .font(Theme.Font.flourish(.footnote))
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
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 2)
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
        // Give each filter its own identity so switching cross-fades and re-deals
        // the cards, rather than reflowing one grid's contents into the other's.
        .id(filter)
        .transition(.opacity)
        .animation(Theme.Motion.standard, value: narrow)
    }

    // The tabs above already name the kind and its count, so neither grid
    // carries a header of its own.
    @ViewBuilder private var deck: some View {
        let actors = store.actors(matching: narrow)
        if actors.isEmpty {
            nothingMatches
        } else {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(Array(actors.enumerated()), id: \.element.id) { i, entity in
                    Button { expand(entity.id) } label: {
                        ReelActorCard(entity: entity, model: tierModel, isNew: store.isNew(entity))
                    }
                    .buttonStyle(.pressScale)
                    // The lifted card stands in for this one while it's out.
                    .opacity(expanded == entity.id ? 0 : 1)
                    .appear(i)
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
                ForEach(Array(movies.enumerated()), id: \.element.id) { i, entity in
                    Button { expand(entity.id) } label: {
                        VStack(spacing: Theme.Spacing.sm) {
                            ReelFrame(entity: entity, isNew: store.isNew(entity))
                                .opacity(expanded == entity.id ? 0 : 1)
                            ReelFrameCaption(entity: entity)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.pressScale)
                    .appear(i)
                }
            }
        }
    }

    /// Only reachable through the narrowing — e.g. actors on the Movies-only
    /// side of a filter that matches no linked film.
    private var nothingMatches: some View {
        Text("Nothing here yet. Try another decade or genre.")
            .font(Theme.Font.flourish(.subheadline))
            .foregroundStyle(Theme.Color.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
    }

    @ViewBuilder private var detail: some View {
        if let id = expanded, let entity = store.entities[id] {
            ReelCardDetail(entity: entity, linked: store.linked(to: entity), model: tierModel) {
                expand(nil)
            }
            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private func expand(_ id: CollectedEntity.ID?) {
        withAnimation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.emphasized) {
            expanded = id
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
                SplitHeading(roman: "Your reel is", flourish: "empty")
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
// their logo and the standard non-endorsement disclaimer. This lives in the Reel
// sheet — the calmest secondary surface — so it stays out of the deliberately
// play-first home while remaining visible in the app (compliant: the terms only
// require it be shown, not that it be on the home screen).
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
            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                .font(Theme.Font.flourish(.caption))
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
