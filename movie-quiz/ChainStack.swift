//
//  ChainStack.swift
//  movie-quiz
//
//  The chain rendered as a stack of Connections-style category tiles. This is
//  the game's signature visual: every accepted link is a colored block, and the
//  column *builds* — each new link drops in from the top and the stack rises,
//  Tetris-style.
//
//  Two modes, driven by `maxVisible`:
//    • Rising window (play): show only the most recent `maxVisible` links; older
//      ones collapse into a "+N earlier" marker so the stack stays inside the
//      band above the always-present keyboard.
//    • Full (game over): `maxVisible == nil` shows the whole chain, numbered, for
//      the recap.
//

import SwiftUI

struct ChainStack: View {
    let chain: [ChainNode]
    /// Size of the visible window during play; `nil` shows the whole chain (recap).
    var maxVisible: Int? = nil
    /// Stamp each tile with its 1-based position (recap).
    var numbered = false
    /// Show the "ACTOR" / "MOVIE" kind label on each tile.
    var showKind = true
    /// Reveal the tiles one-after-another on appear (the game-over recap). Off
    /// during play, where tiles land individually via the `drop` transition as
    /// the chain grows — there, this is a transparent passthrough.
    var staggered = false

    private var visible: [(index: Int, node: ChainNode)] {
        let all = chain.enumerated().map { (index: $0.offset, node: $0.element) }
        guard let maxVisible, all.count > maxVisible else { return all }
        return Array(all.suffix(maxVisible))
    }

    private var hiddenCount: Int {
        guard let maxVisible else { return 0 }
        return max(0, chain.count - maxVisible)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs + 2) {
            if hiddenCount > 0 {
                Text("+\(hiddenCount) earlier")
                    .metaLabel(size: .small)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            ForEach(Array(visible.enumerated()), id: \.element.node.id) { pos, item in
                NodeTile(
                    node: item.node,
                    showKind: showKind,
                    index: numbered ? item.index + 1 : nil
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
                .appear(pos, animation: Theme.Motion.cascade, offset: 14, enabled: staggered)
            }
        }
        .animation(Theme.Motion.drop, value: chain.count)
    }
}

#Preview("Rising window") {
    ChainStack(
        chain: [
            .actor(Person(id: 1, name: "Tom Hanks")),
            .movie(Movie(id: 2, title: "Forrest Gump", year: 1994)),
            .actor(Person(id: 3, name: "Robin Wright")),
            .movie(Movie(id: 4, title: "Wonder Woman", year: 2017)),
        ],
        maxVisible: 3
    )
    .padding()
    .frame(maxHeight: .infinity, alignment: .bottom)
    .background(Theme.Color.canvas)
}
