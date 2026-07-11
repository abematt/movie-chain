//
//  SeedView.swift
//  movie-quiz
//
//  The start screen — pick the actor or movie to open the chain. This is the only
//  screen that uses global search (there is no bounded candidate set until play
//  begins). Styled as a puzzle-page landing (serif wordmark, warm-tile surfaces,
//  the two category accents) on the shared design system, rather than a stock
//  navigation/list/`.searchable` screen, which reads as "iOS Settings".
//

import SwiftUI

struct SeedView: View {
    @Bindable var engine: GameEngine
    var collection: CollectionStore

    @State private var query = ""
    @State private var results: [ChainNode] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var showReel = false
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
        .background(Theme.Color.canvas.ignoresSafeArea())
        .sheet(isPresented: $showReel) {
            CollectionView(store: collection)
        }
    }

    // MARK: Branded header (category lockup · serif wordmark · best badge)

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            chainLockup

            Text("Movie\nChain")
                .font(.system(size: 46, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text("Actor → movie → actor. How long can you keep the chain alive?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.sm) {
                if engine.bestChain > 0 {
                    Text("Your best · \(engine.bestChain) links")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs + 2)
                        .overlay(Capsule().strokeBorder(Theme.Color.hairline, lineWidth: 1))
                }
                if collection.total > 0 {
                    Button { showReel = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "film.stack")
                            Text("Your Reel · \(collection.total)")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs + 2)
                        .overlay(Capsule().strokeBorder(Theme.Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    // MARK: Chain lockup — an ambient mini-chain that telegraphs the game

    private var chainLockup: some View {
        HStack(spacing: 5) {
            ForEach(Array([NodeKind.actor, .movie, .actor, .movie].enumerated()), id: \.offset) { _, kind in
                RoundedRectangle(cornerRadius: 4)
                    .fill(kind.accent)
                    .frame(width: 26, height: 15)
            }
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                .frame(width: 26, height: 15)
                .overlay(
                    Text("?")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                )
        }
    }

    // MARK: Start choice — two big category tiles ("start with an actor / movie")

    private var modeToggle: some View {
        HStack(spacing: Theme.Spacing.sm) {
            choiceTile(.actor)
            choiceTile(.movie)
        }
    }

    private func choiceTile(_ kind: NodeKind) -> some View {
        let selected = engine.seedKind == kind
        return Button {
            engine.seedKind = kind
            searchFocused = true
            runSearch()
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: kind.symbol)
                    .font(.title2)
                Text(kind == .actor ? "Actor" : "Movie")
                    .font(.headline)
                Text(kind == .actor ? "start with a name" : "start with a title")
                    .font(.caption2)
                    .opacity(0.65)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .foregroundStyle(Theme.Color.onAccent)
            .background(kind.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Color.ink, lineWidth: selected ? 2.5 : 0)
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
        .padding(.vertical, Theme.Spacing.sm + 4)
        .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onChange(of: query) { runSearch() }
    }

    // MARK: Results — warm-tile rows with a category dot

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
            NodeDot(kind: node.kind, size: 11)
            Text(node.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md - 2)
        .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(query.isEmpty ? "Pick your start" : "No matches")
                .font(.headline)
            Text(query.isEmpty
                 ? "Search an \(engine.seedKind == .actor ? "actor" : "movie") to begin your chain."
                 : "Try a different spelling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Theme.Spacing.xl)
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
    SeedView(engine: GameEngine(), collection: CollectionStore(fileURL: nil))
}
