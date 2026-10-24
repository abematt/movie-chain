//
//  ChainCards.swift
//  movie-quiz
//
//  The chain's card pieces, shared by the play screen's `ChainDeck` and the
//  home → play handoff: the actor/movie kind chip, and `ChainArt`, the poster or
//  headshot that develops in as it streams. (Game over draws the chain as a
//  `CoinStack` instead.)
//
//  The chain used to come in three styles (Cards, Deck, Tiles) behind a
//  setting; the Deck won and the other two were removed.
//

import SwiftUI

// MARK: - Pieces

/// The category stamp: accent fill, ink border, uppercase tracked label.
struct KindChip: View {
    let kind: NodeKind

    var body: some View {
        Text(kind.tileLabel)
            .metaLabel(kind.onAccent, size: .small)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(kind.accent))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
    }
}

/// Poster or headshot art in a bordered frame. Falls back to the category
/// colour with the kind's glyph when there is no art (the stub graph) or while
/// it loads, so the category reads even before the image arrives.
struct ChainArt: View {
    let node: ChainNode
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat = Theme.Radius.sm
    var glyphSize: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        ZStack {
            node.accent
            if let url = Config.imageURL(path: node.imagePath, size: "w185") {
                if let warmed = ArtCache.shared.image(for: url) {
                    // The dealt start, pre-fetched on the home screen: drawn at
                    // once, so it is already in place as the play screen arrives.
                    warmed.resizable().aspectRatio(contentMode: .fill)
                } else {
                    // No transaction here: an animated phase change also re-ran
                    // the card's matched geometry mid screen-push, sliding the
                    // card against the push. The develop is scoped to the image.
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            DevelopingImage(image: image)
                        } else {
                            glyph
                        }
                    }
                }
            } else {
                glyph
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Color.border, lineWidth: Theme.Border.width))
        .accessibilityHidden(true)
    }

    private var glyph: some View {
        Image(systemName: node.symbol)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(node.kind.onAccent.opacity(0.75))
    }
}

/// Streamed art "develops" in: a quick blur-to-sharp fade, like a print coming up,
/// hiding the moment the download happened to land. The animation is scoped to
/// this view (`.animation(_:value:)`), so it can never drive the card's geometry.
/// Not movement, so it stays under Reduce Motion.
private struct DevelopingImage: View {
    let image: Image
    @State private var developed = false

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .opacity(developed ? 1 : 0)
            .blur(radius: developed ? 0 : 6)
            .animation(.easeOut(duration: 0.22), value: developed)
            .onAppear { developed = true }
    }
}
