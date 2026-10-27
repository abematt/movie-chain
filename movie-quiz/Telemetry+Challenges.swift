//
//  Telemetry+Challenges.swift
//  movie-quiz
//
//  `challenge_opened`: a chain link was opened, and what it turned out to be.
//  It's the one head-to-head moment no run event sees — a reply lands, or a
//  link is refused, without a run. Playing a challenge reuses the run events
//  (`source: challenge`, `rival_links`, `challenge_outcome`).
//

import Foundation

extension Telemetry {
    func challengeOpened(_ arrival: Arrival) {
        var properties: [String: AnyHashable] = [:]
        switch arrival {
        case .challenge(let challenge):
            properties["result"] = "new"
            properties["rival_links"] = challenge.linkCount
        case .played(let match, _):
            properties["result"] = "played"
            if let outcome = match.outcome { properties["outcome"] = outcome.rawValue }
        case .reply(let match, let rival):
            properties["result"] = "reply"
            if let outcome = match.outcome { properties["outcome"] = outcome.rawValue }
            properties["rival_matches"] = rival.matches.count
        case .own: properties["result"] = "own"
        case .needsUpdate: properties["result"] = "needs_update"
        case .invalid: properties["result"] = "invalid"
        }
        send(.challengeOpened, properties)
    }
}
