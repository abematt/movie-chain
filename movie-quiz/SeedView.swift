//
//  SeedView.swift
//  movie-quiz
//
//  Pick the starting actor or movie. This is the only screen that uses global
//  search — there is no bounded candidate set until play begins.
//

import SwiftUI

struct SeedView: View {
    @Bindable var engine: GameEngine

    @State private var query = ""
    @State private var results: [ChainNode] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Start with", selection: $engine.seedKind) {
                    Text("Actor").tag(NodeKind.actor)
                    Text("Movie").tag(NodeKind.movie)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: engine.seedKind) { runSearch() }

                List(results) { node in
                    Button {
                        start(with: node)
                    } label: {
                        HStack {
                            Image(systemName: node.symbol)
                                .foregroundStyle(node.accent)
                            Text(node.displayName)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if results.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "Pick your start" : "No matches",
                            systemImage: engine.seedKind == .actor ? "person.fill" : "film",
                            description: Text(query.isEmpty
                                ? "Search for an \(engine.seedKind == .actor ? "actor" : "movie") to begin your chain."
                                : "Try a different spelling.")
                        )
                    }
                }
            }
            .navigationTitle("Movie Chain")
            .searchable(text: $query, prompt: engine.seedKind == .actor ? "Search actors" : "Search movies")
            .onChange(of: query) { runSearch() }
        }
    }

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
