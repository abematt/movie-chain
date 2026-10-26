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
        guard let token = secrets["TMDBToken"] as? String else { return "" }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// true  -> `tmdbToken` is a v4 Read Access Token, sent as a Bearer header.
    /// false -> `tmdbToken` is a v3 API key, sent as the `api_key` query param.
    /// (Override via the `UsesBearerToken` boolean key in TMDBSecrets.plist.)
    static let usesBearerToken: Bool = secrets["UsesBearerToken"] as? Bool ?? true

    /// The bundled `TMDBSecrets.plist`, read once; empty when the file is absent.
    private static let secrets: [String: Any] = {
        guard
            let url = Bundle.main.url(forResource: "TMDBSecrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any]
        else { return [:] }
        return dict
    }()

    static var hasTMDBToken: Bool { !tmdbToken.isEmpty }

    // MARK: The service (Supabase)

    /// The Unspool service. Its `tmdb` Edge Function is the TMDB proxy
    /// (`supabase/functions/tmdb`).
    static let serviceURL = URL(string: "https://hqdcmuxownykfzmnhmbb.supabase.co")!

    /// The service's publishable key (`sb_publishable_…`), from the secrets plist
    /// (key `ServiceKey`). Made to ship in apps — row-level security decides what
    /// it can reach — but kept out of this public repo like the PostHog token, so
    /// other people's builds don't run on this project.
    static let serviceKey: String = {
        guard let key = secrets["ServiceKey"] as? String else { return "" }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// TMDB requests go through the proxy, so the TMDB token needn't ship. Without
    /// a service key, the app calls TMDB directly with `tmdbToken`. `-tmdbDirect`
    /// (DEBUG) skips the proxy, to tell a proxy fault from a TMDB one.
    static var usesTMDBProxy: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-tmdbDirect") { return false }
        #endif
        return serviceKey.hasPrefix("sb_publishable_")
    }

    /// Live TMDB data is reachable, through the proxy or directly.
    static var hasTMDB: Bool { usesTMDBProxy || hasTMDBToken }

    /// PostHog project token (`phc_…`), from the same secrets plist (key
    /// `PostHogProjectToken`). It's a write-only key meant to ship in clients, but
    /// it stays out of this public repo so nobody else's builds report into the
    /// project. Empty → analytics is off (`NoAnalytics`).
    static let postHogToken: String = {
        guard let token = secrets["PostHogProjectToken"] as? String else { return "" }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var hasPostHogToken: Bool { postHogToken.hasPrefix("phc_") }

    static let postHogHost = "https://us.i.posthog.com"

    // MARK: App version
    //
    // Read from the bundle, never hardcoded, so what the app displays can't drift
    // from what was actually built. The values come from `MARKETING_VERSION` and
    // `CURRENT_PROJECT_VERSION` in build settings (see "Versioning" in CLAUDE.md).

    /// Marketing version — `CFBundleShortVersionString`, e.g. `"0.4.0"`.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number — `CFBundleVersion`, bumped per build submitted to TestFlight.
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// `"0.4.0 (1)"` — the form shown in Settings.
    static var versionString: String { "\(appVersion) (\(buildNumber))" }

    /// Seconds allowed per turn before the game ends.
    static let secondsPerTurn = 30

    /// Per-request network timeout. Kept short so a stalled candidate fetch fails
    /// fast (and retries) instead of freezing a turn — the clock is paused across
    /// the fetch, so without this a hung connection would hang the game on
    /// URLSession's ~60s default. See `GameEngine.loadCandidates`.
    static let requestTimeout: TimeInterval = 12

    /// How many times `GameEngine.loadCandidates` retries a failed candidate fetch
    /// (transient rate-limit / timeout) before giving up. Retries happen while the
    /// clock is paused, so they don't cost the player time.
    static let candidateLoadAttempts = 3

    /// How long a timed-out run holds on the play screen ("time's up") before
    /// game over. Without it the screen slid away the instant the clock hit 0,
    /// so the run never visibly *ended*. A Quit skips it.
    static let timeUpPause: Duration = .milliseconds(450)

    // MARK: Seed deal

    /// Probability (0…1) that a dealt home-screen start is an *actor* rather than
    /// a movie. Actor-leaning because actor→movie is the canonical opening and the
    /// famous-actor pool is deeper; movies still surface often enough to show the
    /// purple accent and vary the first move.
    static let seedActorBias = 0.6

    /// How many recently-dealt starts to remember and avoid, so repeated shuffles
    /// don't keep handing back the same few faces. Small relative to the pool.
    static let seedRecentWindow = 8

    /// Pages (~20 films each) of most-watched films to load for the deal pool.
    /// Fetched once per session and cached, so a few extra requests buy real variety
    /// — at 2 pages a run of shuffles recycled the same ~40 titles.
    static let seedMoviePoolPages = 5

    /// How many of the most-watched films to mine for the recognizable-actor pool
    /// (their top-billed casts become the actors dealt). Higher = deeper pool but
    /// more first-load cast fetches. See `TMDBProvider.popularActors`.
    static let seedActorSourceMovies = 18

    /// Top-billed cast taken from each source film — the leads, not the long tail.
    static let seedTopBilledPerMovie = 5

    /// How long the deal pools saved on disk are dealt from before a launch
    /// refetches them (`SeedPoolCache`). A week: the pool is a near-static
    /// most-watched query, so a longer life costs almost nothing in freshness and
    /// spares a 24-request burst on most launches. Older copies are still the
    /// fallback when a refetch fails. `nonisolated` so the off-main cache can read it.
    nonisolated static let seedPoolMaxAge: TimeInterval = 7 * 24 * 60 * 60

    /// Where chain links live: `<base>/c?d=…` (`SharedChain`). `nil` until the
    /// domain exists and serves the universal-links file; while it's `nil`, shares
    /// carry no link. `nonisolated` so the pure `SharedChain` code can use it.
    nonisolated static let shareBaseURL: URL? = nil

    /// The website's pages Settings links to. The site is `abematt/unspool-site`;
    /// its `docs/handover-app.md` lists what the app owes it.
    static let privacyPolicyURL = URL(string: "https://playunspool.com/privacy")!
    /// The feature board (UserJot): requests and upvotes from players.
    static let featureBoardURL = URL(string: "https://unspool.userjot.com/")!
    static let contactURL = URL(string: "mailto:hello@playunspool.com")!

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
    ///
    /// TODO(scale/security): the TMDB token is bundled in the shipped app (see
    /// `tmdbToken` above), so it ships inside the `.ipa` and can be extracted
    /// from the binary. Two consequences to fix before any real launch —
    /// especially a paid/freemium tier:
    ///   1. Every install shares this one key, so TMDB's per-key rate limit
    ///      (~50 req/s) is a global ceiling across all players; the per-turn
    ///      cast/filmography fetches will throttle at scale.
    ///   2. A leaked key can be abused, getting our account rate-limited/banned.
    /// The fix is a thin server-side proxy that holds the key and caches the
    /// (near-static) cast/filmography responses, with the app pointing at that
    /// proxy instead of TMDB directly. Deliberately NOT doing this yet — noting
    /// it here so it's not forgotten. Revenue is the trigger to actually build it.
    static func makeProvider() -> any MovieDataProvider {
        hasTMDB ? TMDBProvider() : StubProvider()
    }
}
