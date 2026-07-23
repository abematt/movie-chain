//
//  Choices.swift
//  movie-quiz
//
//  The rule that builds the multiple-choice option set for Assisted difficulty.
//  Pure and stateless (like `SeedDeal`, `FuzzyMatch`, `ActorRanking`, `Scoring`)
//  so the policy is unit-tested with a seeded RNG — no network, no engine.
//
//  The whole design turns on the engine's bounded candidate set: at every turn
//  the valid answers are exactly one movie's cast or one actor's filmography, so
//  a "1 correct + N wrong" option set is a pure function of state the engine
//  already owns — the correct answer comes from the candidates, the recognizable
//  distractors come from the popularity pool, and no distractor can accidentally
//  be right because we exclude *every* candidate id from the distractor pool.
//

import Foundation

enum Choices {

    /// Build a shuffled option set: one valid answer plus recognizable distractors.
    ///
    /// - Parameters:
    ///   - candidates: the bounded valid-answer set for the turn (cast/filmography).
    ///     The one correct option is drawn from here (minus `usedIds`).
    ///   - pool: the recognizable-name pool of the *same kind* as the turn expects
    ///     (the deal pool). Distractors are drawn from here, excluding anything that
    ///     is actually a valid answer — so a "wrong" option is never secretly right.
    ///   - count: total options wanted (e.g. `Config.optionCount`). The result may
    ///     be smaller if the pool can't supply enough distinct distractors.
    ///   - usedIds: `ChainNode.id`s already in the chain — never offered again.
    ///   - generator: injected so tests are deterministic.
    /// - Returns: up to `count` options, shuffled, the correct one always included
    ///   when the turn has any unused valid answer. Empty only if it does not.
    static func build<G: RandomNumberGenerator>(
        correctFrom candidates: [ChainNode],
        distractorsFrom pool: [ChainNode],
        count: Int,
        excluding usedIds: Set<String>,
        using generator: inout G
    ) -> [ChainNode] {
        // The one correct option: a valid answer not already used. If there is
        // none, the turn is unwinnable anyway — return nothing and let the clock
        // run (mirrors an exhausted candidate set in the typed game).
        guard let correct = candidates
            .filter({ !usedIds.contains($0.id) })
            .randomElement(using: &generator)
        else { return [] }

        // Distractors: pool entries that are neither a valid answer (any candidate,
        // not just unused ones — so we never show a wrong option that's really
        // right) nor already in the chain.
        let candidateIds = Set(candidates.map(\.id))
        let distractors = pool
            .filter { !candidateIds.contains($0.id) && !usedIds.contains($0.id) }
            .shuffled(using: &generator)
            .prefix(max(0, count - 1))

        return ([correct] + distractors).shuffled(using: &generator)
    }
}
