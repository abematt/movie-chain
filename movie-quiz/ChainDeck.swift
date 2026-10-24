//
//  ChainDeck.swift
//  movie-quiz
//
//  The chain as a physical pile of cards. Every link is the same full-size card
//  for its whole life — when a new link is dealt in from below, the card it
//  lands on is *pushed back* into the
//  pile (smaller, higher, its shadow sinking) instead of being swapped for a
//  compact copy, so nothing ever cross-fades.
//
//  The pile fills whatever height the play screen can spare above the docked
//  keyboard: cards behind the newest peek out with their kind and name while
//  there's room for that, then a few more show only as card edges (the pile's
//  thickness), and anything older tucks under and counts into "+N earlier".
//  Each step back peeks a little less and shrinks a little more, so the pile
//  reads in perspective.
//

import SwiftUI

struct ChainDeck: View {
    let chain: [ChainNode]
    /// Height the play screen can give the pile (the chain band). The deck works
    /// out how many cards fit; `nil` (previews) allows two named peeks.
    var availableHeight: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Upper bound on cards behind the newest, however tall the screen.
    private static let maxBehind = 8
    /// A named peek shows the card's whole header row: its height at full scale.
    /// Scales with the chip's text, so a large text size can't clip the row.
    @ScaledMetric(relativeTo: .caption2) private var namedPeek: CGFloat = 30
    /// The card's height, scaled with its name (`DeckCard.baseHeight` at Large).
    @ScaledMetric(relativeTo: .title2) private var cardHeight: CGFloat = 122
    /// An edge peek shows just the card's top border — pile thickness.
    private static let edgePeek: CGFloat = 6
    private static let maxEdges = 4
    /// Each step back shrinks the card by this much.
    private static let scaleStep: CGFloat = 0.03
    /// Room kept for the "+N earlier" line above the pile.
    private static let labelReserve: CGFloat = 22

    private static func scale(_ depth: Int) -> CGFloat { 1 - CGFloat(depth) * scaleStep }

    /// How far above the newest card's top each depth sits (index = depth), for
    /// as many depths as fit the available height.
    private var offsets: [CGFloat] {
        let budget = (availableHeight ?? (cardHeight + Theme.Shadow.small + Self.labelReserve + 60))
            - cardHeight - Theme.Shadow.small - Self.labelReserve
        var offsets: [CGFloat] = [0]
        var total: CGFloat = 0
        var edges = 0
        for depth in 1...Self.maxBehind {
            let named = (namedPeek * Self.scale(depth)).rounded(.up)
            if edges == 0, total + named <= budget {
                total += named
            } else if edges < Self.maxEdges, total + Self.edgePeek <= budget {
                total += Self.edgePeek
                edges += 1
            } else {
                break
            }
            offsets.append(total)
        }
        return offsets
    }

    var body: some View {
        let offsets = offsets
        let visible = Array(chain.enumerated().suffix(offsets.count))
        let hiddenCount = chain.count - visible.count

        VStack(spacing: Theme.Spacing.xs + 2) {
            if hiddenCount > 0 {
                Text("+\(hiddenCount) earlier")
                    .metaLabel(size: .small)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            ZStack(alignment: .top) {
                ForEach(visible, id: \.element.id) { index, node in
                    let depth = chain.count - 1 - index
                    DeckCard(node: node, isStart: index == 0, depth: depth, height: cardHeight)
                        .scaleEffect(Self.scale(depth), anchor: .top)
                        .offset(y: -offsets[min(depth, offsets.count - 1)])
                        // Under Reduce Motion a card snaps to its new depth rather
                        // than travelling there.
                        .animation(reduceMotion ? nil : Theme.Motion.drop, value: depth)
                        // Older links sit underneath; a leaving card stays lowest.
                        .zIndex(Double(index))
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            // Dealt in from below — out from behind the input.
                            insertion: .move(edge: .bottom),
                            // Tucked down under the pile, hidden by the cards in
                            // front as it goes (the fade is mostly occluded).
                            removal: .modifier(active: DeckTuck(on: true),
                                               identity: DeckTuck(on: false))
                        ))
                }
            }
            // The peeks draw above the cards' frame; make room for them so the
            // band's top clip never cuts them. Grows as the pile does.
            .padding(.top, offsets[max(0, visible.count - 1)])
        }
        // Room for the side, which draws below the card's frame.
        .padding(.bottom, Theme.Shadow.small)
        .animation(reduceMotion ? Theme.Motion.reducedFade : Theme.Motion.drop, value: chain.count)
    }
}

/// The removal for the card leaving the back of the pile: it drops down behind
/// the cards in front and shrinks a little further as it fades.
private struct DeckTuck: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 0.9 : 1, anchor: .top)
            .offset(y: on ? 40 : 0)
            .opacity(on ? 0 : 1)
    }
}

// MARK: - Deck card

/// One link in the pile. Same card at every depth: the header row carries the
/// kind chip and — once the card is pushed back and only its top edge shows —
/// the name, so a peek still says which link it is. The dealt start wears a
/// holographic flag sticker instead of a number.
struct DeckCard: View {
    let node: ChainNode
    /// The dealt start (chain[0]) — not a link, so it gets the start flag.
    var isStart = false
    /// 0 = the newest, on top; higher = further back in the pile.
    let depth: Int

    /// The home → play handoff lands in the start card while it is the only one.
    @Environment(HandoffStage.self) private var stage: HandoffStage?

    /// One height for every card in the pile, so the peeks line up. `ChainDeck`
    /// scales it with the reader's text size; this is its value at Large.
    static let baseHeight: CGFloat = 122
    var height: CGFloat = DeckCard.baseHeight

    private var isFront: Bool { depth == 0 }

    /// This card is where the home's name, chip and avatar fly to.
    private var isHandoffTarget: Bool { isStart && isFront }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                ChainArt(node: node, width: 48, height: 72)
                    .handoffTarget(.art, isHandoffTarget ? stage : nil)
                VStack(alignment: .leading, spacing: 2) {
                    DeckName(text: node.matchText)
                        .handoffTarget(.name, isHandoffTarget ? stage : nil)
                    if case .movie(let m) = node, let year = m.year {
                        Text(String(year))
                            .font(Theme.Font.sentence(.subheadline))
                            .foregroundStyle(Theme.Color.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.md - 4)
        .frame(height: height, alignment: .top)
        // One thin side for every card: the pile's peeks already carry its
        // thickness, and a deeper slab under the front card read as a heavy
        // black bar across the bottom of the play screen.
        .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
        // Stuck flat on the card's face, inside its edges — a sticker hanging off
        // the border read as floating. Sits in the header row, so it shows in
        // the card's peek once the start is pushed back.
        .overlay(alignment: .topTrailing) {
            if isStart {
                StartSticker()
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.trailing, Theme.Spacing.sm + 2)
            }
        }
        .handoffTarget(.card, isHandoffTarget ? stage : nil)
        // Hidden while the handoff's copies fly in; shown in the same frame they go.
        .opacity(isHandoffTarget && stage?.isFlying == true ? 0 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!isFront)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            KindChip(kind: node.kind)
                .handoffTarget(.chip, isHandoffTarget ? stage : nil)
            // Only the peek needs the name up here; on the front card the body
            // already carries it in display type.
            Text(node.matchText)
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(isFront ? 0 : 1)
            Spacer(minLength: 0)
        }
        // Keep the name clear of the start sticker.
        .padding(.trailing, isStart ? 64 : 0)
    }
}

#Preview("Deck") {
    ChainDeck(chain: [
        .actor(Person(id: 1, name: "Brad Pitt")),
        .movie(Movie(id: 1001, title: "Ocean's Eleven", year: 2001)),
        .actor(Person(id: 2, name: "Matt Damon")),
        .movie(Movie(id: 1002, title: "The Departed", year: 2006)),
        .actor(Person(id: 3, name: "Leonardo DiCaprio")),
    ], availableHeight: 320)
    .padding()
    .frame(maxHeight: .infinity, alignment: .bottom)
    .background(Theme.Color.canvas)
}
