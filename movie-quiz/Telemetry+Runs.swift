//
//  Telemetry+Runs.swift
//  movie-quiz
//
//  A run, start to finish: `run_started`, one `link_landed` per answer, and
//  `run_ended` (sent from `phaseChanged`). Every event inside a run carries its
//  `run_id`, so one game can be read back turn by turn.
//

import Foundation

extension Telemetry {
    enum StartSource: String { case dealt, picked }

    struct RunState {
        var id: UUID?
        var startedAt: Date?
    }

    func runStarted(seed: ChainNode, source: StartSource) {
        let id = UUID()
        runs = RunState(id: id, startedAt: now())
        var properties: [String: AnyHashable] = [
            "run_id": id.uuidString,
            "seed_id": seed.tmdbID,
            "seed_kind": seed.kind.rawValue,
            "source": source.rawValue,
            "deals_before_start": screen.dealsSinceHome,
            "home_s": seconds(since: screen.since),
        ]
        if let gameOver = screen.lastGameOverSeconds { properties["game_over_s"] = gameOver }
        screen.lastGameOverSeconds = nil
        send(.runStarted, properties)
    }

    func linkLanded(_ turn: GameEngine.Turn, link: Int, fast: Bool) {
        send(.linkLanded, inRun([
            "link": link,
            "prompt_id": turn.prompt.tmdbID,
            "prompt_kind": turn.prompt.kind.rawValue,
            "answer_id": turn.answer.tmdbID,
            "typed": Self.clip(turn.typed),
            "misses": turn.misses.map(Self.clip),
            "answer_ms": Self.ms(turn.answerTime),
            "load_ms": Self.ms(turn.loadTime),
            "fast": fast,
        ]))
    }

    func turnLoadFailed(links: Int) {
        send(.turnLoadFailed, inRun(["links": links]))
    }

    func runEnded(_ summary: GameEngine.Summary) {
        let answers = summary.turns.map { Self.ms($0.answerTime) }
        var properties: [String: AnyHashable] = [
            "reason": summary.endedByQuit ? "quit" : "timeout",
            "links": summary.links,
            "points": summary.points,
            "new_best": summary.isNewBest,
            "reel_additions": summary.reelAdditions,
            "play_s": Self.round(Double(Self.ms(summary.playTime)) / 1000),
            "wrong_guesses": summary.turns.reduce(summary.finalMisses.count) { $0 + $1.misses.count },
            "final_misses": summary.finalMisses.map(Self.clip),
            "retries": summary.retries,
        ]
        if let startedAt = runs.startedAt { properties["duration_s"] = seconds(since: startedAt) }
        if !answers.isEmpty {
            properties["avg_answer_ms"] = answers.reduce(0, +) / answers.count
            properties["slowest_answer_ms"] = answers.max()
        }
        if let last = summary.chain.last { properties["final_prompt_id"] = last.tmdbID }
        if let missed = summary.missedAnswer { properties["near_miss_id"] = missed.tmdbID }
        send(.runEnded, inRun(properties))
        runs = RunState()
    }

    /// Stamps the run in progress onto an event.
    private func inRun(_ properties: [String: AnyHashable]) -> [String: AnyHashable] {
        guard let id = runs.id else { return properties }
        return properties.merging(["run_id": id.uuidString]) { own, _ in own }
    }
}
