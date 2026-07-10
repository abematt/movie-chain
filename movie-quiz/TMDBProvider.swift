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

    private func fetch<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let req = try request(path: path, query: query)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DataProviderError.badResponse(-1) }
        guard (200...299).contains(http.statusCode) else { throw DataProviderError.badResponse(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DataProviderError.decoding
        }
    }

    // MARK: MovieDataProvider

    func searchActors(_ query: String) async throws -> [Person] {
        let page: PersonSearchResponse = try await fetch(
            PersonSearchResponse.self,
            path: "search/person",
            query: [URLQueryItem(name: "query", value: query)]
        )
        return page.results
            .filter { $0.known_for_department == nil || $0.known_for_department == "Acting" }
            .map { Person(id: $0.id, name: $0.name) }
    }

    func searchMovies(_ query: String) async throws -> [Movie] {
        let page: MovieSearchResponse = try await fetch(
            MovieSearchResponse.self,
            path: "search/movie",
            query: [URLQueryItem(name: "query", value: query)]
        )
        return page.results.map { $0.toMovie() }
    }

    func cast(of movie: Movie) async throws -> [Person] {
        let credits: MovieCreditsResponse = try await fetch(
            MovieCreditsResponse.self,
            path: "movie/\(movie.id)/credits"
        )
        return credits.cast.map { Person(id: $0.id, name: $0.name) }
    }

    func filmography(of actor: Person) async throws -> [Movie] {
        let credits: PersonCreditsResponse = try await fetch(
            PersonCreditsResponse.self,
            path: "person/\(actor.id)/movie_credits"
        )
        // Acting roles only; drop entries without a title.
        return credits.cast.map { $0.toMovie() }
    }
}

// MARK: - DTOs

private struct PersonSearchResponse: Decodable {
    struct Item: Decodable {
        let id: Int
        let name: String
        let known_for_department: String?
    }
    let results: [Item]
}

private struct MovieSearchResponse: Decodable {
    let results: [MovieDTO]
}

private struct MovieCreditsResponse: Decodable {
    struct CastMember: Decodable {
        let id: Int
        let name: String
    }
    let cast: [CastMember]
}

private struct PersonCreditsResponse: Decodable {
    let cast: [MovieDTO]
}

private struct MovieDTO: Decodable {
    let id: Int
    let title: String?
    let release_date: String?

    func toMovie() -> Movie {
        let year = release_date.flatMap { Int($0.prefix(4)) }
        return Movie(id: id, title: title ?? "Untitled", year: year)
    }
}
