//
//  Config.swift
//  movie-quiz
//
//  App configuration. No credential is stored here. Two gitignored plists hold
//  them, so nothing lands in this public repo:
//  - `AppSecrets.plist` — what ships: the service key and the PostHog token.
//  - `TMDBSecrets.plist` — the TMDB token, for development only. Release builds
//    leave the file out (`EXCLUDED_SOURCE_FILE_NAMES`), so the token never ships;
//    the app reaches TMDB through the service's proxy.
//  Each has a `.example.plist` showing its format.
//

import Foundation

enum Config {
    /// TMDB API Read Access Token (v4 "Bearer" token) OR v3 API key, read from
    /// `TMDBSecrets.plist` (key `TMDBToken`). Used only without the proxy, in
    /// development; always empty in Release, which leaves the file out.
    ///
    /// Get a token free at https://www.themoviedb.org/settings/api
    static let tmdbToken: String = {
        guard let token = tmdbSecrets["TMDBToken"] as? String else { return "" }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// true  -> `tmdbToken` is a v4 Read Access Token, sent as a Bearer header.
    /// false -> `tmdbToken` is a v3 API key, sent as the `api_key` query param.
    /// (Override via the `UsesBearerToken` boolean key in TMDBSecrets.plist.)
    static let usesBearerToken: Bool = tmdbSecrets["UsesBearerToken"] as? Bool ?? true

    private static let tmdbSecrets = bundledPlist("TMDBSecrets")
    private static let appSecrets = bundledPlist("AppSecrets")

    /// A bundled plist as a dictionary, read once; empty when the file is absent.
    private static func bundledPlist(_ name: String) -> [String: Any] {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any]
        else { return [:] }
        return dict
    }

    static var hasTMDBToken: Bool { !tmdbToken.isEmpty }

    // MARK: The service (Supabase)

    /// The Unspool service. Its `tmdb` Edge Function is the TMDB proxy
    /// (`supabase/functions/tmdb`).
    static let serviceURL = URL(string: "https://hqdcmuxownykfzmnhmbb.supabase.co")!

    /// The service's publishable key (`sb_publishable_…`), from `AppSecrets.plist`
    /// (key `ServiceKey`). Made to ship in apps — row-level security decides what
    /// it can reach — but kept out of this public repo like the PostHog token, so
    /// other people's builds don't run on this project.
    static let serviceKey: String = {
        guard let key = appSecrets["ServiceKey"] as? String else { return "" }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// There's a service to talk to: the TMDB proxy and the published daily starts.
    static var hasService: Bool { serviceKey.hasPrefix("sb_publishable_") }

    /// TMDB requests go through the proxy, so the TMDB token needn't ship. Without
    /// a service key, the app calls TMDB directly with `tmdbToken`. `-tmdbDirect`
    /// (DEBUG) skips the proxy, to tell a proxy fault from a TMDB one.
    static var usesTMDBProxy: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-tmdbDirect") { return false }
        #endif
        return hasService
    }

    /// Live TMDB data is reachable, through the proxy or directly.
    static var hasTMDB: Bool { usesTMDBProxy || hasTMDBToken }

    /// PostHog project token (`phc_…`), from `AppSecrets.plist` (key
    /// `PostHogProjectToken`). It's a write-only key meant to ship in clients, but
    /// it stays out of this public repo so nobody else's builds report into the
    /// project. Empty → analytics is off (`NoAnalytics`).
    static let postHogToken: String = {
        guard let token = appSecrets["PostHogProjectToken"] as? String else { return "" }
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

    // MARK: Daily start

    /// How many days past today each fetch of the published daily starts covers,
    /// so a week without signal still has its dailies.
    static let dailyDaysAhead = 7

    /// The published days are refetched at most this often (on visits home), so a
    /// day fixed after it went out reaches players within the hour.
    static let dailyRefreshInterval: TimeInterval = 60 * 60

    /// Where chain links live: `<base>/c?d=…` (`SharedChain`). `nil` in Release
    /// until playunspool.com serves the universal-links file; while it's `nil`,
    /// shares carry no link. Debug builds use the private `unspool-debug://`
    /// scheme (registered in `Support/Debug-Info.plist`, Debug only), so a whole
    /// challenge can be played between two simulators: `scripts/sim-challenge.sh`.
    /// Only the host is checked when a link opens, so the scheme can change
    /// without breaking links. `nonisolated` so the pure `SharedChain` code can use it.
    #if DEBUG
    nonisolated static let shareBaseURL: URL? = URL(string: "unspool-debug://playunspool.com")
    #else
    nonisolated static let shareBaseURL: URL? = nil
    #endif

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
