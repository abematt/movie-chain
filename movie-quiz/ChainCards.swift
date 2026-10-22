//
//  ChainCards.swift
//  movie-quiz
//
//  The chain's card pieces, shared by the play screen's `ChainDeck` and the
//  game-over recap: the compact card (a small art thumb and the name, one line
//  each), the actor/movie kind chip, and `ChainArt`, the poster or headshot that
//  develops in as it streams.
//
//  The chain used to come in three styles (Cards, Deck, Tiles) behind a
//  setting; the Deck won and the other two were removed.
//

import SwiftUI

// MARK: - Compact card (earlier links)

struct CompactChainCard: View {
    let node: ChainNode
    /// Link number, shown as a leading numeral (the game-over recap). Links
    /// count from 1; the start is not a link.
    var position: Int? = nil
    /// The dealt start: shows a flag in the numeral column instead of a number.
    var isStart = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            if isStart {
                Image(systemName: "flag.fill")
                    .font(Theme.Font.labelSmall)
                    .foregroundStyle(Theme.Color.muted)
                    .frame(minWidth: 18)
                    .accessibilityLabel("Start")
            } else if let position {
                Text("\(position)")
                    .font(Theme.Font.numeral(.subheadline))
                    .foregroundStyle(Theme.Color.muted)
                    .frame(minWidth: 18)
            }
            ChainArt(node: node, width: 26, height: 26, radius: 6, glyphSize: 11)
            NodeName(node: node)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Text(node.kind.tileLabel)
                .metaLabel(size: .small)
        }
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, Theme.Spacing.sm - 1)
        .neoSurface(radius: Theme.Radius.md, shadow: Theme.Shadow.small)
        .accessibilityElement(children: .combine)
    }
}

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

#Preview("Recap cards") {
    VStack(spacing: Theme.Spacing.xs + 2) {
        CompactChainCard(node: .actor(Person(id: 1, name: "Brad Pitt")), position: nil, isStart: true)
        CompactChainCard(node: .movie(Movie(id: 1001, title: "Ocean's Eleven", year: 2001)), position: 1)
        CompactChainCard(node: .actor(Person(id: 2, name: "Matt Damon")), position: 2)
    }
    .padding()
    .background(Theme.Color.canvas)
}
