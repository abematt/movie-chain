//
//  SeedDeal.swift
//  movie-quiz
//
//  The rule that deals a starting node on the home screen. Pure and stateless
//  (like `FuzzyMatch`, `ActorRanking`, `Scoring`) so the selection policy can be
//  unit-tested with a seeded RNG — no network, no live TMDB round-trip.
//
//  The policy: deal a *fresh, familiar* start. "Familiar" is the caller's job —
//  it passes the popularity-ranked pools. "Fresh" is this type's job — it avoids
//  ids the player has been dealt recently so repeated shuffles don't keep handing
//  back the same few faces, and it mixes actors and movies by a tunable bias.
//

import Foundation

enum SeedDeal {

    /// Pick a random starting node from the popularity pools.
    ///
    /// - Parameters:
    ///   - actors/movies: the recognizable-name pools (already popularity-ranked
    ///     by the provider/`ActorRanking`).
    ///   - recentIds: `ChainNode.id`s dealt recently — avoided so a shuffle feels
    ///     fresh. If *every* candidate of the chosen kind is recent (a small
    ///     pool), the full pool is used rather than returning nothing.
    ///   - actorBias: probability in `0...1` of dealing an actor vs a movie. If
    ///     the chosen kind's pool is empty, the other kind is dealt instead.
    ///   - generator: injected so tests are deterministic.
    /// - Returns: a dealt node, or `nil` only if *both* pools are empty.
    static func pick<G: RandomNumberGenerator>(
        actors: [Person],
        movies: [Movie],
        recentIds: Set<String>,
        actorBias: Double,
        using generator: inout G
    ) -> ChainNode? {
        let actorNodes = actors.map(ChainNode.actor)
        let movieNodes = movies.map(ChainNode.movie)

        // Prefer candidates not dealt recently; fall back to the whole pool for a
        // kind if all of it is recent (keeps a tiny pool from dealing nothing).
        let freshActors = actorNodes.filter { !recentIds.contains($0.id) }
        let freshMovies = movieNodes.filter { !recentIds.contains($0.id) }
        let actorPool = freshActors.isEmpty ? actorNodes : freshActors
        let moviePool = freshMovies.isEmpty ? movieNodes : freshMovies

        let wantActor = Double.random(in: 0..<1, using: &generator) < actorBias
        // Deal the wanted kind if it has candidates, otherwise the other kind.
        if wantActor {
            return actorPool.randomElement(using: &generator)
                ?? moviePool.randomElement(using: &generator)
        } else {
            return moviePool.randomElement(using: &generator)
                ?? actorPool.randomElement(using: &generator)
        }
    }
}
