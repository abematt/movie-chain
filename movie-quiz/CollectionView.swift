//
//  CollectionView.swift
//  movie-quiz
//
//  "Your Reel" — the collection screen. Every actor/movie the player has logged
//  through play, shown as a grid of headshots/posters with pure count stats on
//  top ("look how many you know"). Presented as a sheet from the seed and
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
    /// Gates the hero numbers so they roll up from 0 on first appear.
    @State private var statsIn = false

    /// Fade art in as it streams from the network, unless motion is reduced.
    private var imageTransaction: Transaction {
        Transaction(animation: reduceMotion ? nil : .easeIn(duration: 0.25))
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
                            grids
                            TMDBAttribution()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, Theme.Spacing.md)
                        .onAppear {
                            guard !statsIn else { return }
                            if reduceMotion { statsIn = true }
                            else { withAnimation(Theme.Motion.emphasized) { statsIn = true } }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.canvas.ignoresSafeArea())
            .navigationTitle("Your Reel")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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

    // MARK: Hero — the flex line + category split + stat strip

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("You have logged")
                    .font(Theme.Font.flourish(.body))
                    .foregroundStyle(.secondary)
                Text("\(statsIn ? store.total : 0)")
                    .font(Theme.Font.display(64))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(store.total)))
                    .foregroundStyle(Theme.Color.ink)
            }

            HStack(spacing: Theme.Spacing.sm) {
                countCard(.actor, store.actorCount, "Actors")
                countCard(.movie, store.movieCount, "Movies")
            }

            if bestChain > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                    Text("Best chain").metaLabel()
                    Text("\(bestChain) links")
                        .font(Theme.Font.numeral(.subheadline))
                        .foregroundStyle(Theme.Color.ink)
                }
            }
        }
    }

    private func countCard(_ kind: NodeKind, _ value: Int, _ label: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("\(statsIn ? value : 0)")
                .font(Theme.Font.display(44))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.ink)
                .contentTransition(.numericText(value: Double(value)))
            KindChip(kind: kind)
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .neoSurface(radius: Theme.Radius.card)
    }

    // MARK: Regulars — most-logged actor + movie

    @ViewBuilder private var regulars: some View {
        if store.mostLoggedActor != nil || store.mostLoggedMovie != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionLabel("Your regulars", trailing: "most logged")
                HStack(spacing: Theme.Spacing.sm) {
                    if let a = store.mostLoggedActor { regularCard(a) }
                    if let m = store.mostLoggedMovie { regularCard(m) }
                }
            }
        }
    }

    private func regularCard(_ entity: CollectedEntity) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            thumb(entity)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.kind.tileLabel).metaLabel()
                Text(entity.name)
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                Text("in \(entity.timesLogged) \(entity.timesLogged == 1 ? "chain" : "chains")")
                    .font(Theme.Font.flourish(.footnote))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm + 2)
        .frame(maxWidth: .infinity)
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
                    .foregroundStyle(filter == f ? Theme.Color.onInk : .secondary)
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

    private func count(for f: Filter) -> Int {
        switch f {
        case .actors: store.actorCount
        case .movies: store.movieCount
        }
    }

    // MARK: Grids

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)
    }

    @ViewBuilder private var grids: some View {
        Group {
            switch filter {
            case .actors:
                gridSection(.actor, "Actors", store.actorCount, store.sortedActors)
            case .movies:
                gridSection(.movie, "Movies", store.movieCount, store.sortedMovies)
            }
        }
        // Give each filter its own identity so switching cross-fades and re-deals
        // the tiles, rather than reflowing one grid's contents into the other's.
        .id(filter)
        .transition(.opacity)
    }

    private func gridSection(_ kind: NodeKind, _ title: String, _ n: Int, _ items: [CollectedEntity]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                NodeDot(kind: kind, size: 9)
                Text(title).metaLabel()
                Spacer()
                Text("\(n)")
                    .font(Theme.Font.numeral(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, entity in
                    ReelTile(entity: entity, isNew: store.isNew(entity))
                        .appear(i)
                }
            }
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.Font.heading(.title3)).foregroundStyle(Theme.Color.ink)
            Spacer()
            Text(trailing).font(Theme.Font.flourish(.footnote)).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "film.stack")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Your reel is empty")
                    .font(Theme.Font.heading(.title3))
                Text("Finish a chain and every actor and movie you named lands here.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Reel tile

/// One collection entry: a poster/headshot (or typographic placeholder) with the
/// name, a "×N chains" chip, and a "New" badge for this session's discoveries.
private struct ReelTile: View {
    let entity: CollectedEntity
    let isNew: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                entity.kind.accent
                artContent
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topTrailing) { countChip }
            .overlay(alignment: .topLeading) { if isNew { newBadge } }

            Rectangle().fill(Theme.Color.border).frame(height: Theme.Border.width)

            nameBar
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
    }

    @ViewBuilder private var artContent: some View {
        if let url = Config.imageURL(path: entity.imagePath, size: "w185") {
            AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeIn(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    glyph
                @unknown default:
                    glyph
                }
            }
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Image(systemName: entity.kind.symbol)
            .font(.system(size: 32))
            .foregroundStyle(entity.kind.onAccent.opacity(0.5))
    }

    // A solid name strip under the art, not a gradient scrim over it — the spec
    // allows no gradients, and ink-on-white reads in both themes.
    private var nameBar: some View {
        Text(entity.displayName)
            .font(Theme.Font.small.weight(.semibold))
            .foregroundStyle(Theme.Color.ink)
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background(Theme.Color.tile)
    }

    private var countChip: some View {
        Text("×\(entity.timesLogged)")
            .font(Theme.Font.numeral(.caption))
            .monospacedDigit()
            .foregroundStyle(Theme.Color.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Color.tile))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1.5))
            .padding(6)
    }

    private var newBadge: some View {
        Text("New")
            .metaLabel(Theme.Color.onAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.Color.good))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1.5))
            .padding(6)
    }
}

// MARK: - Preview

#Preview {
    let store = CollectionStore(fileURL: nil)
    // Seed some sample chains so the preview has content.
    store.record(chain: [
        .actor(Person(id: 1, name: "Samuel L. Jackson")),
        .movie(Movie(id: 680, title: "Pulp Fiction", year: 1994)),
        .actor(Person(id: 2, name: "Uma Thurman")),
        .movie(Movie(id: 24, title: "Kill Bill", year: 2003)),
    ])
    store.record(chain: [
        .actor(Person(id: 1, name: "Samuel L. Jackson")),
        .movie(Movie(id: 954, title: "Mission: Impossible", year: 1996)),
        .actor(Person(id: 3, name: "Tom Cruise")),
    ])
    return CollectionView(store: store)
}
