//
//  TMDBProvider.swift
//  movie-quiz
//
//  Live data source backed by The Movie Database (TMDB) REST API.
//

import Foundation

struct TMDBProvider: MovieDataProvider {
    private let base = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Requests

    private func request(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard Config.hasTMDBToken else { throw DataProviderError.missingAPIKey }

        var comps = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query
        if !Config.usesBearerToken {
            items.append(URLQueryItem(name: "api_key", value: Config.tmdbToken))
        }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if Config.usesBearerToken {
            req.setValue("Bearer \(Config.tmdbToken)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func fetch<T: Decodable & Sendable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let req = try request(path: path, query: query)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DataProviderError.badResponse(-1) }
        guard (200...299).contains(http.statusCode) else { throw DataProviderError.badResponse(http.statusCode) }
        // Decode OFF the main actor. The provider is MainActor-isolated (project
        // default), so decoding here would parse every response on the main
        // thread — including the ~18 concurrent cast fetches that build the deal
        // pool and a popular actor's 100+ credit filmography — stuttering the
        // seed→play transition. This nonisolated async helper runs the decode on
        // the cooperative pool instead.
        return try await Self.decode(T.self, from: data)
    }

    /// Off-main JSON decode. `nonisolated async` so it runs on the concurrency
    /// thread pool, not the caller's (Main) actor.
    nonisolated private static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw DataProviderError.decoding }
    }

    // MARK: MovieDataProvider

    func searchActors(_ query: String) async throws -> [Person] {
        let page: PersonSearchResponse = try await fetch(
            PersonSearchResponse.self,
            path: "search/person",
            query: [URLQueryItem(name: "query", value: query)]
        )
        return ActorRanking.rank(page.results.map {
            ActorSearchCandidate(
                id: $0.id,
                name: $0.name,
                department: $0.known_for_department,
                popularity: $0.popularity ?? 0,
                knownForCount: $0.known_for?.count ?? 0,
                imagePath: $0.profile_path
            )
        })
    }

    func searchMovies(_ query: String) async throws -> [Movie] {
        let page: MovieSearchResponse = try await fetch(
            MovieSearchResponse.self,
            path: "search/movie",
            query: [URLQueryItem(name: "query", value: query)]
        )
        // Most-popular first so the canonical title leads over obscure remakes
        // and same-title stubs.
        return page.results
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .map { $0.toMovie() }
    }

    func popularMovies() async throws -> [Movie] {
        // The most-*watched* films of all time, not "trending now": TMDB's
        // `popular` is a right-now metric that surfaces viral-but-obscure titles,
        // so we use `discover` sorted by **vote count** — the most-rated films are
        // the ones the most people have actually seen (Inception, The Dark Knight,
        // Fight Club, …). Two pages (~40) keeps shuffling fresh.
        try await mostWatchedMovies(pages: 2)
    }

    func popularActors() async throws -> [Person] {
        // TMDB has no all-time "famous people" list — `person/popular` is the same
        // trending metric that surfaces unrecognizable names. So derive the actor
        // pool from the **casts of the most-watched films**: the top-billed names
        // of the movies everyone has seen are exactly the recognizable actors, and
        // it keeps the actor pool consistent with the movie pool. Deduped by id
        // (highest popularity wins), most-popular first.
        let source = try await mostWatchedMovies(pages: 1).prefix(Config.seedActorSourceMovies)
        // Capture the tunable on the main actor; the task-group children are
        // nonisolated and can't read MainActor-isolated `Config` statics directly.
        let topBilled = Config.seedTopBilledPerMovie
        var byId: [Int: Person] = [:]
        try await withThrowingTaskGroup(of: [Person].self) { group in
            for movie in source {
                group.addTask {
                    // A single film's failed credits fetch shouldn't sink the pool.
                    let cast = (try? await self.cast(of: movie)) ?? []
                    return Array(cast.prefix(topBilled))
                }
            }
            for try await people in group {
                for p in people {
                    if let existing = byId[p.id], (p.popularity ?? 0) <= (existing.popularity ?? 0) { continue }
                    byId[p.id] = p
                }
            }
        }
        return byId.values
            .filter { ($0.popularity ?? 0) > 0 }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }

    /// The most-rated films (a proxy for most-watched), `pages` of ~20 each, in
    /// vote-count order. Shared by the movie pool and the derived-actor pool.
    private func mostWatchedMovies(pages: Int) async throws -> [Movie] {
        var out: [Movie] = []
        for page in 1...max(1, pages) {
            let resp: MovieSearchResponse = try await fetch(
                MovieSearchResponse.self,
                path: "discover/movie",
                query: [
                    URLQueryItem(name: "include_adult", value: "false"),
                    URLQueryItem(name: "sort_by", value: "vote_count.desc"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ]
            )
            out.append(contentsOf: resp.results.map { $0.toMovie() })
        }
        return out
    }

    func cast(of movie: Movie) async throws -> [Person] {
        let credits: MovieCreditsResponse = try await fetch(
            MovieCreditsResponse.self,
            path: "movie/\(movie.id)/credits"
        )
        return credits.cast.map {
            Person(id: $0.id, name: $0.name, popularity: $0.popularity, imagePath: $0.profile_path)
        }
    }

    func filmography(of actor: Person) async throws -> [Movie] {
        let credits: PersonCreditsResponse = try await fetch(
            PersonCreditsResponse.self,
            path: "person/\(actor.id)/movie_credits"
        )
        // Real acting roles only. TMDB's movie credits include behind-the-scenes
        // featurettes where the person appears as themselves (e.g. "Making of
        // School of Rock", character "Self") — those aren't film roles and must
        // not be valid chain links, so drop any credit played as "Self".
        return credits.cast
            .filter { !$0.isSelfAppearance }
            .map { $0.toMovie() }
    }
}

// MARK: - Seed ranking (pure, unit-testable)

/// One person from a search response reduced to the fields that decide seed
/// ranking. Extracted as a plain value type so `ActorRanking` is pure and
/// testable without a live TMDB round-trip.
struct ActorSearchCandidate {
    let id: Int
    let name: String
    let department: String?
    let popularity: Double
    let knownForCount: Int
    var imagePath: String? = nil
}

enum ActorRanking {
    /// Order search results for the seed picker.
    ///
    /// TMDB returns duplicate person records for popular actors — the real one
    /// plus near-empty stubs (e.g. two "Tom Cruise" entries, one with 94 credits
    /// and one with 1). Seeding on a stub gives an almost-empty filmography and
    /// rejects films the actor was really in.
    ///
    /// A person's identity is its TMDB id, NOT its name: distinct ids that share
    /// a name are legitimate homonyms, so we must not drop by name. Instead:
    /// keep acting-eligible people, drop only records with *no* evidence of being
    /// real (zero popularity AND no known work), and sort canonical-first by
    /// popularity. Every real id — including low-popularity homonyms — stays
    /// selectable while obvious stubs sink to the bottom.
    static func rank(_ candidates: [ActorSearchCandidate]) -> [Person] {
        candidates
            .filter { $0.department == nil || $0.department == "Acting" }
            .filter { $0.popularity > 0 || $0.knownForCount > 0 }
            .sorted { $0.popularity > $1.popularity }
            .map { Person(id: $0.id, name: $0.name, popularity: $0.popularity, imagePath: $0.imagePath) }
    }
}

// MARK: - DTOs

// `nonisolated` so their `Decodable` conformances aren't MainActor-isolated and
// can be decoded on the off-main `TMDBProvider.decode` helper (mirrors the
// `nonisolated` Codable values in `Collection.swift`).
nonisolated private struct PersonSearchResponse: Decodable {
    /// Decodes each `known_for` entry structurally without reading its fields —
    /// we only need the array's presence/count as evidence the person is real.
    struct KnownForItem: Decodable {}
    struct Item: Decodable {
        let id: Int
        let name: String
        let known_for_department: String?
        let popularity: Double?
        let known_for: [KnownForItem]?
        let profile_path: String?
    }
    let results: [Item]
}

nonisolated private struct MovieSearchResponse: Decodable {
    let results: [MovieDTO]
}

nonisolated private struct MovieCreditsResponse: Decodable {
    struct CastMember: Decodable {
        let id: Int
        let name: String
        let popularity: Double?
        let profile_path: String?
    }
    let cast: [CastMember]
}

nonisolated private struct PersonCreditsResponse: Decodable {
    let cast: [MovieDTO]
}

nonisolated private struct MovieDTO: Decodable {
    let id: Int
    let title: String?
    let release_date: String?
    let popularity: Double?
    let poster_path: String?
    /// Role name, present on person `movie_credits` (nil on movie search results).
    let character: String?

    /// A credit where the person plays themselves — a making-of / behind-the-
    /// scenes / documentary appearance, not a film role. TMDB writes these as
    /// "Self", sometimes decorated ("Self - Host", "Self (archive footage)").
    var isSelfAppearance: Bool {
        guard let role = character?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() else { return false }
        return role == "self" || role.hasPrefix("self ") || role.hasPrefix("self-")
    }

    func toMovie() -> Movie {
        let year = release_date.flatMap { Int($0.prefix(4)) }
        return Movie(id: id, title: title ?? "Untitled", year: year, popularity: popularity, imagePath: poster_path)
    }
}
