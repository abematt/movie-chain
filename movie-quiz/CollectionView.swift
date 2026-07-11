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
//  actor, purple = movie), matching the NYT-Games puzzle-page treatment used
//  everywhere else. Images stream in via `AsyncImage` (system-cached, never
//  stored on disk); when there's no art — the stub graph, or a title TMDB has no
//  poster for — the tile falls back to a typographic placeholder.
//

import SwiftUI

struct CollectionView: View {
    let store: CollectionStore

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Filter = .actors

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
                        }
                        .padding(.horizontal)
                        .padding(.vertical, Theme.Spacing.md)
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(store.total)")
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.Color.ink)
            }

            HStack(spacing: Theme.Spacing.sm) {
                countCard(.actor, store.actorCount, "Actors")
                countCard(.movie, store.movieCount, "Movies")
            }
        }
    }

    private func countCard(_ kind: NodeKind, _ value: Int, _ label: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("\(value)")
                .font(.system(size: 44, weight: .bold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(kind.accent)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
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
                Text(entity.kind.tileLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.tertiary)
                Text(entity.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                Text("in \(entity.timesLogged) \(entity.timesLogged == 1 ? "chain" : "chains")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm + 2)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.Color.hairline, lineWidth: 1)
        )
    }

    private func thumb(_ entity: CollectedEntity) -> some View {
        ZStack {
            entity.kind.accent
            if let url = Config.imageURL(path: entity.imagePath, size: "w185") {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: entity.kind.symbol)
                        .foregroundStyle(Theme.Color.onAccent.opacity(0.4))
                }
            } else {
                Image(systemName: entity.kind.symbol)
                    .foregroundStyle(Theme.Color.onAccent.opacity(0.5))
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
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
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .foregroundStyle(filter == f ? Theme.Color.ink : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm + 1)
                            .fill(filter == f ? Theme.Color.canvas : .clear)
                            .shadow(color: .black.opacity(filter == f ? 0.12 : 0), radius: 2, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
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
        switch filter {
        case .actors:
            gridSection(.actor, "Actors", store.actorCount, store.sortedActors)
        case .movies:
            gridSection(.movie, "Movies", store.movieCount, store.sortedMovies)
        }
    }

    private func gridSection(_ kind: NodeKind, _ title: String, _ n: Int, _ items: [CollectedEntity]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 3).fill(kind.accent).frame(width: 9, height: 9)
                Text(title)
                    .font(.caption.weight(.heavy)).tracking(1.4).textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(n)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(items) { entity in
                    ReelTile(entity: entity, isNew: store.isNew(entity))
                }
            }
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Theme.Color.ink)
            Spacer()
            Text(trailing).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Your reel is empty")
                .font(.title3.weight(.semibold))
            Text("Finish a chain and every actor and movie you named lands here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - Reel tile

/// One collection entry: a poster/headshot (or typographic placeholder) with the
/// name, a "×N chains" chip, and a "New" badge for this session's discoveries.
private struct ReelTile: View {
    let entity: CollectedEntity
    let isNew: Bool

    var body: some View {
        ZStack {
            entity.kind.accent
            artContent
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        .overlay(alignment: .bottom) { nameBar }
        .overlay(alignment: .topTrailing) { countChip }
        .overlay(alignment: .topLeading) { if isNew { newBadge } }
    }

    @ViewBuilder private var artContent: some View {
        if let url = Config.imageURL(path: entity.imagePath, size: "w185") {
            AsyncImage(url: url) { phase in
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
            .foregroundStyle(Theme.Color.onAccent.opacity(0.32))
    }

    private var nameBar: some View {
        Text(entity.displayName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.bottom, 5)
            .padding(.top, 16)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )
            )
    }

    private var countChip: some View {
        Text("×\(entity.timesLogged)")
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
    }

    private var newBadge: some View {
        Text("NEW")
            .font(.system(size: 8, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(Theme.Color.onAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.Color.good, in: RoundedRectangle(cornerRadius: 5))
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
