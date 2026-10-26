//
//  MovieDataProvider.swift
//  movie-quiz
//
//  Abstraction over the data source. The game engine only knows this protocol,
//  so we can run against a local stub before a TMDB key is available and swap
//  in the live provider without touching game logic.
//

import Foundation

protocol MovieDataProvider: Sendable {
    /// Global search — used only to pick the *seed* node, where there is no
    /// bounded candidate set yet.
    func searchActors(_ query: String) async throws -> [Person]
    func searchMovies(_ query: String) async throws -> [Movie]

    /// The recognizable-name pools the home screen deals a random start from —
    /// popularity-ranked so the dealt seed is always a familiar face/title, never
    /// an obscure one. Fetched once and cached by the engine.
    func popularActors() async throws -> [Person]
    func popularMovies() async throws -> [Movie]

    /// The bounded candidate sets used for validation during play.
    func cast(of movie: Movie) async throws -> [Person]
    func filmography(of actor: Person) async throws -> [Movie]
}

enum DataProviderError: LocalizedError {
    case missingAPIKey
    case badResponse(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No TMDB access. Add a ServiceKey to AppSecrets.plist (or, in development, a token to TMDBSecrets.plist), or the app will use built-in demo data."
        case .badResponse(let code):
            return "The movie service returned an error (\(code))."
        case .decoding:
            return "Couldn't read the response from the movie service."
        }
    }
}
