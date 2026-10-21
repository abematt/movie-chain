//
//  ChainCards.swift
//  movie-quiz
//
//  PROTOTYPE (0.6.0 design overhaul) — the chain drawn as a stack of
//  neobrutalist cards, the roadmap's leading candidate. It keeps `ChainStack`'s
//  information architecture (stack, collapse older, emphasise newest) and spends
//  the vertical room differently:
//
//    • The newest link is a full **hero card**: poster or headshot art, a kind
//      chip, and the name set in display type. It is the thing you're building
//      from, so it gets the room.
//    • The few links before it are **compact cards**: a small art thumb and the
//      name, one line each.
//    • Anything older collapses into "+N earlier".
//
//  Newest sits at the bottom, nearest the docked input, so the eye travels from
//  "what I'm linking from" straight to "where I type". Settings → Chain style
//  switches between this and the tile stack for side-by-side judging on device.
//

import SwiftUI

struct ChainCardStack: View {
    let chain: [ChainNode]
    /// How many compact cards to show above the hero before collapsing. Two is
    /// what fits on an iPhone 16 with the keyboard docked while keeping the
    /// "+N earlier" marker on screen; a third gets clipped off the top.
    var maxEarlier = 2

    private var earlier: [ChainNode] {
        Array(chain.dropLast().suffix(maxEarlier))
    }

    private var hiddenCount: Int {
        max(0, chain.count - 1 - maxEarlier)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs + 2) {
            if hiddenCount > 0 {
                Text("+\(hiddenCount) earlier")
                    .metaLabel()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            ForEach(earlier) { node in
                CompactChainCard(node: node)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            if let newest = chain.last {
                HeroChainCard(node: newest, position: chain.count)
                    // Re-identify per node so each new link drops in as a new card
                    // rather than the old hero morphing its text.
                    .id(newest.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        // Leave room for the hard shadow, which draws outside the card's frame.
        .padding(.trailing, Theme.Shadow.large)
        .padding(.bottom, Theme.Shadow.large)
        .animation(Theme.Motion.drop, value: chain.count)
    }
}

// MARK: - Hero card (the newest link)

struct HeroChainCard: View {
    let node: ChainNode
    /// 1-based position in the chain, stamped quietly in the corner.
    var position: Int? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ChainArt(node: node, width: 48, height: 72)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    KindChip(kind: node.kind)
                    Spacer(minLength: 0)
                    if let position {
                        Text("#\(position)")
                            .monospacedDigit()
                            .metaLabel()
                    }
                }
                Text(node.matchText)
                    .font(Theme.Font.heading(.title2))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                if case .movie(let m) = node, let year = m.year {
                    Text(String(year))
                        .font(Theme.Font.flourish(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md - 4)
        .neoSurface(radius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Compact card (earlier links)

struct CompactChainCard: View {
    let node: ChainNode
    /// 1-based position, shown as a leading numeral (the game-over recap).
    var position: Int? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            if let position {
                Text("\(position)")
                    .font(Theme.Font.heading(.subheadline))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18)
            }
            ChainArt(node: node, width: 26, height: 26, radius: 6, glyphSize: 11)
            NodeName(node: node)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Text(node.kind.tileLabel)
                .metaLabel()
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
            .metaLabel(kind.onAccent)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(kind.accent))
            .overlay(Capsule().strokeBorder(Theme.Color.border, lineWidth: 1.5))
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
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        glyph
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

// MARK: - Chain style switch (prototype)

/// Which chain treatment the play screen draws. A prototype switch so the
/// candidates can be judged running on a device; delete it once one wins.
enum ChainStyle: String, CaseIterable, Identifiable {
    case cards
    case tiles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cards: "Cards"
        case .tiles: "Tiles"
        }
    }
}

#Preview("Card stack") {
    ChainCardStack(chain: [
        .actor(Person(id: 1, name: "Brad Pitt")),
        .movie(Movie(id: 1001, title: "Ocean's Eleven", year: 2001)),
        .actor(Person(id: 2, name: "Matt Damon")),
        .movie(Movie(id: 1002, title: "The Departed", year: 2006)),
        .actor(Person(id: 3, name: "Leonardo DiCaprio")),
        .movie(Movie(id: 1003, title: "Inception", year: 2010)),
    ])
    .padding()
    .frame(maxHeight: .infinity, alignment: .bottom)
    .background(Theme.Color.canvas)
}
