//
//  Models.swift
//  movie-quiz
//
//  Core domain types for the actor/movie chain game.
//

import Foundation

/// A person (actor) as identified by the data provider.
struct Person: Identifiable, Hashable, Sendable {
    let id: Int          // TMDB person id (stable, unambiguous)
    let name: String
    /// TMDB popularity, when known. Drives the obscurity scoring bonus — a
    /// deep-cut pick is worth more than an A-lister. `nil` for the stub graph.
    var popularity: Double? = nil
    /// TMDB `profile_path` (e.g. `/abc.jpg`), when known. The headshot shown in
    /// the collection ("Your Reel"); `nil` for the stub graph → typographic tile.
    var imagePath: String? = nil

    // Identity is the TMDB id, never the name or popularity, so records with the
    // same id compare equal regardless of the metadata we happened to fetch.
    static func == (lhs: Person, rhs: Person) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A movie as identified by the data provider.
struct Movie: Identifiable, Hashable, Sendable {
    let id: Int          // TMDB movie id
    let title: String
    let year: Int?       // release year, for disambiguation/display
    /// TMDB popularity, when known. See `Person.popularity`.
    var popularity: Double? = nil
    /// TMDB `poster_path` (e.g. `/xyz.jpg`), when known. The poster shown in the
    /// collection ("Your Reel"); `nil` for the stub graph → typographic tile.
    var imagePath: String? = nil
    /// TMDB vote count, when known (filmography credits). Marks the actor's
    /// well-known films for the Reel's Share tiers; `nil` for the stub graph.
    var voteCount: Int? = nil
    /// TMDB genre ids, when known. Drives the Reel's genre filter; empty for the
    /// stub graph.
    var genreIDs: [Int] = []

    var displayTitle: String {
        if let year { return "\(title) (\(year))" }
        return title
    }

    static func == (lhs: Movie, rhs: Movie) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One node in the chain. The chain alternates actor / movie.
enum ChainNode: Identifiable, Hashable, Sendable {
    case actor(Person)
    case movie(Movie)

    var id: String {
        switch self {
        case .actor(let p): return "p\(p.id)"
        case .movie(let m): return "m\(m.id)"
        }
    }

    /// For display (includes the movie's year for disambiguation).
    var displayName: String {
        switch self {
        case .actor(let p): return p.name
        case .movie(let m): return m.displayTitle
        }
    }

    /// For fuzzy matching: the bare name/title with no year decoration, so the
    /// player only has to spell the thing they're thinking of.
    var matchText: String {
        switch self {
        case .actor(let p): return p.name
        case .movie(let m): return m.title
        }
    }

    /// What kind of node must come next in the chain.
    var nextKind: NodeKind {
        switch self {
        case .actor: return .movie
        case .movie: return .actor
        }
    }

    /// TMDB popularity of the underlying entity, when known — used to award the
    /// obscurity scoring bonus.
    var popularity: Double? {
        switch self {
        case .actor(let p): return p.popularity
        case .movie(let m): return m.popularity
        }
    }

    /// TMDB image path of the underlying entity, when known — the headshot/poster
    /// stored in the collection.
    var imagePath: String? {
        switch self {
        case .actor(let p): return p.imagePath
        case .movie(let m): return m.imagePath
        }
    }

    /// TMDB genre ids for a movie; always empty for an actor.
    var genreIDs: [Int] {
        if case .movie(let m) = self { return m.genreIDs }
        return []
    }

    /// The bare TMDB id, without the kind prefix `id` carries.
    var tmdbID: Int {
        switch self {
        case .actor(let p): return p.id
        case .movie(let m): return m.id
        }
    }

}

/// Whether a turn expects an actor or a movie.
enum NodeKind: String, Sendable, Codable {
    case actor
    case movie

    var prompt: String {
        switch self {
        case .actor: return "Name an actor in it"
        case .movie: return "Name a movie they were in"
        }
    }

    var placeholder: String {
        switch self {
        case .actor: return "Actor name"
        case .movie: return "Movie title"
        }
    }
}
