//
//  StubProvider.swift
//  movie-quiz
//
//  Built-in demo data so the game is fully playable before a TMDB key exists.
//  A small, deliberately connected graph of movies and their casts.
//

import Foundation

struct StubProvider: MovieDataProvider {

    // MARK: Fixed graph

    /// Movie title -> cast (actor names). Ids are derived deterministically so
    /// the same name always resolves to the same Person across queries.
    private static let graph: [(title: String, year: Int, cast: [String])] = [
        ("Ocean's Eleven", 2001, ["Brad Pitt", "George Clooney", "Matt Damon", "Julia Roberts", "Andy Garcia", "Bernie Mac"]),
        ("Fight Club", 1999, ["Brad Pitt", "Edward Norton", "Helena Bonham Carter"]),
        ("12 Years a Slave", 2013, ["Brad Pitt", "Michael Fassbender", "Chiwetel Ejiofor", "Lupita Nyong'o"]),
        ("The Departed", 2006, ["Matt Damon", "Leonardo DiCaprio", "Jack Nicholson", "Mark Wahlberg"]),
        ("Good Will Hunting", 1997, ["Matt Damon", "Robin Williams", "Ben Affleck", "Minnie Driver"]),
        ("Inception", 2010, ["Leonardo DiCaprio", "Joseph Gordon-Levitt", "Elliot Page", "Tom Hardy", "Michael Caine"]),
        ("The Revenant", 2015, ["Leonardo DiCaprio", "Tom Hardy", "Domhnall Gleeson"]),
        ("Pretty Woman", 1990, ["Julia Roberts", "Richard Gere"]),
        ("The Dark Knight", 2008, ["Christian Bale", "Heath Ledger", "Michael Caine", "Gary Oldman", "Morgan Freeman"]),
        ("The Prestige", 2006, ["Christian Bale", "Hugh Jackman", "Michael Caine", "Scarlett Johansson"]),
        ("Fantastic Mr. Fox", 2009, ["George Clooney", "Meryl Streep", "Bill Murray"]),
        ("The Grand Budapest Hotel", 2014, ["Ralph Fiennes", "Bill Murray", "Edward Norton", "Tilda Swinton"]),
    ]

    // MARK: Derived indexes (built once)

    private static let people: [String: Person] = {
        var map: [String: Person] = [:]
        var nextId = 1
        for entry in graph {
            for name in entry.cast where map[name] == nil {
                map[name] = Person(id: nextId, name: name)
                nextId += 1
            }
        }
        return map
    }()

    private static let movies: [Int: (movie: Movie, cast: [Person])] = {
        var map: [Int: (Movie, [Person])] = [:]
        for (index, entry) in graph.enumerated() {
            let movie = Movie(id: 1000 + index, title: entry.title, year: entry.year)
            let cast = entry.cast.compactMap { people[$0] }
            map[movie.id] = (movie, cast)
        }
        return map
    }()

    // MARK: MovieDataProvider

    func searchActors(_ query: String) async throws -> [Person] {
        let q = FuzzyMatch.normalize(query)
        return Self.people.values
            .filter { FuzzyMatch.normalize($0.name).contains(q) }
            .sorted { $0.name < $1.name }
    }

    func searchMovies(_ query: String) async throws -> [Movie] {
        let q = FuzzyMatch.normalize(query)
        return Self.movies.values
            .map(\.movie)
            .filter { FuzzyMatch.normalize($0.title).contains(q) }
            .sorted { $0.title < $1.title }
    }

    func popularActors() async throws -> [Person] {
        // The whole stub cast is "popular" — it's a hand-picked graph of famous
        // names — so deal from all of it, name-sorted for a stable pool order.
        Self.people.values.sorted { $0.name < $1.name }
    }

    func popularMovies() async throws -> [Movie] {
        Self.movies.values.map(\.movie).sorted { $0.title < $1.title }
    }

    func cast(of movie: Movie) async throws -> [Person] {
        Self.movies[movie.id]?.cast ?? []
    }

    func filmography(of actor: Person) async throws -> [Movie] {
        Self.movies.values
            .filter { $0.cast.contains(actor) }
            .map(\.movie)
            .sorted { $0.title < $1.title }
    }
}
