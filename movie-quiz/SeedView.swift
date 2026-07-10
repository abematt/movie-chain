//
//  SeedView.swift
//  movie-quiz
//
//  The start screen — pick the actor or movie to open the chain. This is the only
//  screen that uses global search (there is no bounded candidate set until play
//  begins). Styled as a branded game landing on the shared design system
//  (`NodeGlyph`, node accents, `Theme` tokens, the radial-heat background) rather
//  than a stock navigation/list/`.searchable` screen, which read as "iOS Settings".
//

import SwiftUI

struct SeedView: View {
    @Bindable var engine: GameEngine

    @State private var query = ""
    @State private var results: [ChainNode] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            header
            modeToggle
            searchField
            if results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
    }

    // MARK: Branded header (icon lockup · title · best badge)

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                NodeGlyph(kind: .actor, size: 40)
                Image(systemName: "link")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
                NodeGlyph(kind: .movie, size: 40)
            }

            Text("MOVIE CHAIN")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .tracking(1)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("Actor → movie → actor. Keep the chain alive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if engine.bestChain > 0 {
                Label("Best chain \(engine.bestChain)", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .background(.orange.opacity(0.12), in: Capsule())
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    // MARK: Mode toggle — two big tappable pills, lit by the node accent

    private var modeToggle: some View {
        HStack(spacing: Theme.Spacing.sm) {
            modeButton(.actor)
            modeButton(.movie)
        }
    }

    private func modeButton(_ kind: NodeKind) -> some View {
        let selected = engine.seedKind == kind
        return Button {
            engine.seedKind = kind
            runSearch()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: kind.symbol)
                Text(kind == .actor ? "Actor" : "Movie").fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(kind.accent))
            .background(
                selected ? AnyShapeStyle(kind.accent) : AnyShapeStyle(kind.accent.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: Theme.Radius.md)
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.standard, value: selected)
    }

    // MARK: Search field (in-app styled, not a system search bar)

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(engine.seedKind == .actor ? "Search actors" : "Search movies", text: $query)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onChange(of: query) { runSearch() }
    }

    // MARK: Results — tinted cards with a clear "start" affordance

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(results) { node in
                    Button { start(with: node) } label: { resultRow(node) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(_ node: ChainNode) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            NodeGlyph(kind: node.kind, size: 40)
            Text(node.displayName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(node.accent)
        }
        .padding(Theme.Spacing.sm + 2)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(query.isEmpty ? "Pick your start" : "No matches",
                  systemImage: engine.seedKind.symbol)
        } description: {
            Text(query.isEmpty
                 ? "Search for an \(engine.seedKind == .actor ? "actor" : "movie") to begin your chain."
                 : "Try a different spelling.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Background — the same subtle radial heat as the play screen

    private var background: some View {
        RadialGradient(
            colors: [engine.seedKind.accent.opacity(0.10), .clear],
            center: .top,
            startRadius: 0,
            endRadius: 500
        )
        .animation(.easeInOut(duration: 0.5), value: engine.seedKind)
    }

    // MARK: Search

    private func runSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250)) // debounce
            if Task.isCancelled { return }
            let found = await engine.search(q)
            if Task.isCancelled { return }
            results = found
        }
    }

    private func start(with node: ChainNode) {
        Task { await engine.startGame(with: node) }
    }
}

#Preview {
    SeedView(engine: GameEngine())
}
