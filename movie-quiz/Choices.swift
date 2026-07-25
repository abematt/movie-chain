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

    /// The rule deciding which valid answers are *familiar enough* to offer in
    /// Assisted mode — the heart of the mode's beginner-friendliness.
    ///
    /// An assisted chain may only step to a node that is itself globally familiar:
    /// the same standard the seed deal applies at step 0, applied at **every** step.
    /// Without it the walk drifts — a globally-known actor whose filmography is
    /// almost entirely regional cinema strands the chain in a region the player
    /// can't recognize, and no amount of *ordering that node's own candidates* can
    /// escape it (ordering a set that is 95% unfamiliar still yields something
    /// unfamiliar). The gate is self-reinforcing: widely-seen films have widely-known
    /// leads and vice versa, so a walk that never leaves the mainstream component of
    /// the graph stays inside it.
    enum FamiliarityGate {
        /// Actor turns. The current node is a film that already cleared the gate, so
        /// its **top-billed** cast are recognizable by construction — billing order
        /// is the actor-side familiarity signal (the same one the deal pool is
        /// derived from). Candidates are assumed in TMDB billing order.
        case topBilled(Int)
        /// Movie turns. Only films a lot of people have actually *seen* qualify,
        /// measured by TMDB `vote_count` (a stable all-time signal, unlike the
        /// right-now `popularity` metric).
        case minVoteCount(Int)
        /// No gate — Hardcore, or the stub graph (which carries no vote counts).
        case none

        /// Apply the gate to a turn's unused valid answers. May return an empty list
        /// (the caller relaxes — see `build`).
        func eligible(from unused: [ChainNode]) -> [ChainNode] {
            switch self {
            case .topBilled(let n):
                return Array(unused.prefix(max(1, n)))
            case .minVoteCount(let floor):
                return unused.filter { ($0.voteCount ?? 0) >= floor }
            case .none:
                return unused
            }
        }
    }

    /// Build a shuffled option set: one valid answer plus recognizable distractors.
    ///
    /// - Parameters:
    ///   - candidates: the bounded valid-answer set for the turn (cast/filmography),
    ///     **assumed ordered most-recognizable first** (cast = billing order;
    ///     filmography = popularity-sorted). The one correct option is drawn from
    ///     here (minus `usedIds`).
    ///   - pool: the recognizable-name pool of the *same kind* as the turn expects
    ///     (the deal pool). Distractors are drawn from here, excluding anything that
    ///     is actually a valid answer — so a "wrong" option is never secretly right.
    ///   - count: total options wanted (e.g. `Config.optionCount`). The result may
    ///     be smaller if the pool can't supply enough distinct distractors.
    ///   - usedIds: `ChainNode.id`s already in the chain — never offered again.
    ///   - gate: the familiarity rule the correct answer must clear, so the chain
    ///     only ever steps to a node the player plausibly knows (see
    ///     `FamiliarityGate`). If *no* unused candidate clears it, the gate is
    ///     relaxed rather than stalling the turn — a rare dead end (an actor whose
    ///     only widely-seen film is already in the chain) still gets playable
    ///     options.
    ///   - generator: injected so tests are deterministic.
    /// - Returns: up to `count` options, shuffled, the correct one always included
    ///   when the turn has any unused valid answer. Empty only if it does not.
    static func build<G: RandomNumberGenerator>(
        correctFrom candidates: [ChainNode],
        distractorsFrom pool: [ChainNode],
        count: Int,
        excluding usedIds: Set<String>,
        gate: FamiliarityGate = .none,
        using generator: inout G
    ) -> [ChainNode] {
        // The one correct option: a valid, unused answer that clears the familiarity
        // gate. If there is no unused answer at all the turn is unwinnable — return
        // nothing and let the clock run (mirrors an exhausted candidate set in the
        // typed game).
        let unusedCorrect = candidates.filter { !usedIds.contains($0.id) }
        let eligible = gate.eligible(from: unusedCorrect)
        // Relax to the ungated set rather than stalling: better a less-familiar
        // option than a turn with nothing to tap.
        guard let correct = (eligible.isEmpty ? unusedCorrect : eligible)
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
