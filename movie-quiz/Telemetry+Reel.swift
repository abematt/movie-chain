//
//  Telemetry+Reel.swift
//  movie-quiz
//
//  A visit to Your Reel: one `card_viewed` per card put back (which card, for how
//  long, flipped, dragged) and one `reel_closed` for the visit. The sheet reports
//  its own open and close, so every way into it is counted.
//

import Foundation

extension Telemetry {
    struct ReelState {
        var openedFrom: Screen?
        var openedAt: Date?
        var cardsViewed = 0
        var flips = 0
        var filtersUsed: [String] = []
        /// The card that's out of the grid right now.
        var lifted: LiftedCard?
    }

    struct LiftedCard {
        let entity: CollectedEntity
        let at: Date
        var flipped = false
        var dragged = false
    }

    func reelOpened(from screen: Screen) {
        reel = ReelState(openedFrom: screen, openedAt: now())
    }

    func cardLifted(_ entity: CollectedEntity) {
        reel.lifted = LiftedCard(entity: entity, at: now())
    }

    func cardFlipped() {
        reel.flips += 1
        reel.lifted?.flipped = true
    }

    func cardDragged() { reel.lifted?.dragged = true }

    func cardPutDown() {
        guard let card = reel.lifted else { return }
        reel.lifted = nil
        reel.cardsViewed += 1
        let links = card.entity.links.count
        var properties: [String: AnyHashable] = [
            "tmdb_id": card.entity.tmdbID,
            "kind": card.entity.kind.rawValue,
            "linked": links,
            "duration_s": seconds(since: card.at),
            "flipped": card.flipped,
            "dragged": card.dragged,
        ]
        if card.entity.kind == .actor {
            properties["finish"] = ReelTier.finish(links: links).label.lowercased()
        }
        send(.cardViewed, properties)
    }

    /// A tab, decade or genre chosen — named like `tab:movies`, `decade:1990`, `genre:18`.
    func reelFiltered(_ filter: String) {
        if !reel.filtersUsed.contains(filter) { reel.filtersUsed.append(filter) }
    }

    func reelClosed() {
        cardPutDown()   // a card still out when the sheet goes counts as viewed
        guard let openedAt = reel.openedAt else { return }
        send(.reelClosed, [
            "from": reel.openedFrom?.rawValue ?? "unknown",
            "duration_s": seconds(since: openedAt),
            "cards_viewed": reel.cardsViewed,
            "flips": reel.flips,
            "filters": reel.filtersUsed,
        ])
        reel = ReelState()
    }
}
