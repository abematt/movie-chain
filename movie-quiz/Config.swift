//
//  Config.swift
//  movie-quiz
//
//  App configuration. The TMDB credential is NOT stored here — it is loaded at
//  runtime from `TMDBSecrets.plist`, which is gitignored so the token never
//  lands in source control. See TMDBSecrets.example.plist for the format.
//

import Foundation

enum Config {
    /// TMDB API Read Access Token (v4 "Bearer" token) OR v3 API key, read from
    /// the bundled, gitignored `TMDBSecrets.plist` (key `TMDBToken`). Empty when
    /// the file is absent — the app then runs on the built-in demo data.
    ///
    /// Get a token free at https://www.themoviedb.org/settings/api
    static let tmdbToken: String = {
        guard
            let url = Bundle.main.url(forResource: "TMDBSecrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any],
            let token = dict["TMDBToken"] as? String
        else { return "" }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// true  -> `tmdbToken` is a v4 Read Access Token, sent as a Bearer header.
    /// false -> `tmdbToken` is a v3 API key, sent as the `api_key` query param.
    /// (Override via the `UsesBearerToken` boolean key in TMDBSecrets.plist.)
    static let usesBearerToken: Bool = {
        guard
            let url = Bundle.main.url(forResource: "TMDBSecrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any],
            let flag = dict["UsesBearerToken"] as? Bool
        else { return true }
        return flag
    }()

    static var hasTMDBToken: Bool { !tmdbToken.isEmpty }

    /// Seconds allowed per turn before the game ends.
    static let secondsPerTurn = 30

    /// Base for TMDB-hosted images (headshots/posters shown in the collection).
    /// Full URL = base + size + path, e.g. `.../t/p/w185/abc.jpg`.
    static let imageBaseURL = "https://image.tmdb.org/t/p/"

    /// Build a TMDB image URL from a stored `profile_path`/`poster_path`. Returns
    /// `nil` when there is no path (the stub graph, or an entity TMDB has no art
    /// for) so the collection tile falls back to its typographic placeholder.
    /// `size` is a TMDB size bucket (`w92`, `w185`, `w342`, …); `w185` suits the grid.
    static func imageURL(path: String?, size: String = "w185") -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: imageBaseURL + size + path)
    }

    /// Chooses the live provider if a token is set, otherwise the demo stub.
    static func makeProvider() -> MovieDataProvider {
        hasTMDBToken ? TMDBProvider() : StubProvider()
    }
}
