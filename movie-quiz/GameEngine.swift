//
//  GameEngine.swift
//  movie-quiz
//
//  The core chain game: alternating actor/movie nodes, each link validated
//  against the bounded candidate set of the previous node, with a per-turn
//  timer and a running score.
//

import Foundation
import Observation

@MainActor
@Observable
final class GameEngine {

    enum Phase: Equatable {
        case seed          // choosing the starting actor/movie
        case playing
        case gameOver(Summary)
    }

    /// How a finished run went. Lives on `.gameOver` so these facts can't exist
    /// (or go stale) outside a game-over.
    struct Summary: Equatable {
        /// This run beat the previous best — the trigger for the celebration.
        var isNewBest = false
        /// The best this run beat, in links ("was 7" on the sticker). 0 when there
        /// was no previous best (the first run that logged one).
        var previousBest = 0
        /// A valid answer the player *didn't* give on the turn that timed out — the
        /// "you were one away" near-miss. `nil` on a manual quit (there was no
        /// missed turn — the player chose to stop).
        var missedAnswer: ChainNode?
        /// How many brand-new actors/movies this run added to the collection ("Your
        /// Reel") — the "+N to your Reel" figure.
        var reelAdditions = 0
        /// The finished run itself, frozen here rather than read live off the
        /// engine: "Play again" resets the live run as the game-over screen
        /// starts sliding away, and that screen must keep showing *this* run
        /// until it's gone.
        var chain: [ChainNode] = []
        var links = 0
        var points = 0
        /// The player tapped Quit, rather than the clock running out.
        var endedByQuit = false
        /// Every answered turn, in order — the run as it was played.
        var turns: [Turn] = []
        /// The turn the run ended on: what was showing and what was tried.
        var finalMisses: [String] = []
        /// Time the clock actually ran, summed over turns (loading excluded).
        var playTime: Duration = .zero
        /// Manual retries after a failed candidate load.
        var retries = 0
        /// The daily start's number, when this run was today's daily.
        var daily: Int?
        /// The challenge this run answered, when it was one.
        var challenge: SharedChain?

        /// How this run did against the challenge it answered.
        var outcome: Outcome? {
            challenge.map { Outcome(mine: RunScore(links: links, points: points),
                                    theirs: RunScore(links: $0.linkCount, points: $0.points)) }
        }

        /// Spoiler-free share card: each link as a coloured square, never a name,
        /// plus the run as a link when there's somewhere for links to go. A daily
        /// names its number, so friends know they played the same start.
        func shareText(link: URL?) -> String {
            let squares = chain.map { $0.kind == .actor ? "🟦" : "🟨" }.joined()
            let linkWord = links == 1 ? "link" : "links"
            let title = daily.map { "Unspool #\($0)" } ?? "Unspool"
            var card = "\(title) 🎬\n\(links) \(linkWord) · \(points) pts\n\(squares)"
            // A reply names the run it answers; the challenger has played it, so
            // their score spoils nothing.
            if let challenge {
                let name = challenge.senderName ?? "you"
                card += "\nvs \(name): \(challenge.linkCount) · \(challenge.points) pts"
            }
            guard let link else { return card }
            let dare = challenge == nil ? "Beat it: " : ""
            return card + "\n" + dare + link.absoluteString
        }
    }

    /// One answered turn, as played. The game never reads these back; they're the
    /// run's record for analytics, kept here because only the engine sees the
    /// clock and the misses.
    struct Turn: Equatable {
        /// What the player was answering from.
        var prompt: ChainNode
        var answer: ChainNode
        /// What they typed for the accepted answer.
        var typed: String
        /// Rejected attempts this turn, in order.
        var misses: [String]
        /// Clock running → accepted.
        var answerTime: Duration
        /// Waiting for this turn's answers to load, before its clock started.
        var loadTime: Duration
    }

    // MARK: State

    private(set) var phase: Phase = .seed
    /// This run's answered turns so far. See `Turn`.
    private(set) var turns: [Turn] = []
    private(set) var chain: [ChainNode] = []
    /// The headline metric: chain length (accepted links). Drives the flame and
    /// the hero number.
    private(set) var score = 0
    /// Richer secondary score — base + speed + obscurity, accumulated per link.
    private(set) var points = 0
    /// Points awarded for the most recent link (drives the "+N" flourish).
    private(set) var lastGain = 0
    /// Whether the last accepted answer beat the "fast" threshold.
    private(set) var lastAnswerFast = false
    private(set) var secondsRemaining = Config.secondsPerTurn

    /// What the current turn expects (actor or movie).
    private(set) var expectedKind: NodeKind = .actor

    /// Transient feedback for a rejected / off-list answer.
    private(set) var feedback: String?
    /// Bumped on every rejected answer. Views react to this rather than to
    /// `feedback`, which doesn't change when two misses in a row produce the
    /// same message — so the second miss would otherwise get no shake or buzz.
    private(set) var rejections = 0
    private(set) var isChecking = false
    /// The clock has hit 0 and the run is in its brief "time's up" hold before
    /// game over (`Config.timeUpPause`). Answers are no longer accepted.
    private(set) var timeUp = false

    /// When true, a new game's first turn doesn't start its clock until the play
    /// screen calls `playerReady()` — i.e. once the keyboard is up — so the
    /// screen push and keyboard rise don't eat into the first 30 seconds. Off by
    /// default so headless callers (tests) keep the immediate clock.
    var holdsFirstTurnClock = false
    private var playerIsReady = false
    private var clockPending = false

    // MARK: Records & recap

    /// The best run's link count, persisted across launches. The best run is the
    /// one with the most links, points breaking a tie (`Scoring.isNewRecord`).
    private(set) var bestChain: Int
    /// The best run's points — always from the same run as `bestChain`, never a
    /// separate all-time points maximum.
    private(set) var bestPoints: Int
    /// True right after the link that passed the previous best. `bestChain` only
    /// updates at game over, so during play it still holds the record to beat.
    /// True for the rest of a run once it is past the previous best.
    var isBeatingBest: Bool {
        phase == .playing && bestChain > 0 && score > bestChain
    }
    var justPassedBest: Bool {
        phase == .playing && Scoring.passesRecord(score: score, previousBest: bestChain)
    }
    /// The finished run's summary, while on the game-over screen.
    var summary: Summary? {
        if case .gameOver(let summary) = phase { summary } else { nil }
    }

    /// The kind chosen for the seed search.
    var seedKind: NodeKind = .actor

    /// The start currently dealt on the home screen (the "Start with …" button).
    /// `nil` until the popularity pool has loaded and the first deal lands — the
    /// home shows a placeholder until then.
    ///
    /// Observed by hand so every set is announced. `@Observable` skips a set whose
    /// new value `==` the old, and nodes are equal by TMDB id — so swapping the
    /// bare daily for the pool's copy of the same start (with its art) never
    /// reached the home, and the photo never showed.
    private(set) var dealtSeed: ChainNode? {
        get {
            access(keyPath: \.dealtSeed)
            return _dealtSeedStorage
        }
        set {
            withMutation(keyPath: \.dealtSeed) { _dealtSeedStorage = newValue }
        }
    }
    @ObservationIgnored private var _dealtSeedStorage: ChainNode?
    /// The pools couldn't load after every attempt and there was no saved copy to
    /// fall back on, so there is no start to deal. The home offers to try again
    /// instead of sitting on "Dealing…".
    private(set) var dealFailed = false
    /// The daily start's number while `dealtSeed` is today's daily; `nil` for a
    /// random deal.
    private(set) var dealtDaily: Int?
    /// Every daily start played on this phone, by number. An entry is written
    /// when the run starts: one attempt per day.
    private(set) var dailyResults: [Int: DailyResult]
    /// The daily number of the run in progress.
    private var runDaily: Int?
    /// Daily starts the service has published, by number, kept from today on.
    /// A day missing here falls back to `DailyStart.entries`.
    private var servedDailies: [Int: DailyStart.Entry]
    /// A friend's challenge while it's the start on the home. "Deal again" deals
    /// it away; opening the link again brings it back.
    private(set) var dealtChallenge: SharedChain?
    /// A challenge that arrived mid-run or on game over, dealt on the next visit home.
    private var pendingChallenge: SharedChain?
    /// The challenge the run in progress answers.
    private var runChallenge: SharedChain?

    // MARK: Private

    private let provider: any MovieDataProvider
    /// Popularity-ranked pools the home deals from, fetched once and cached.
    private var actorPool: [Person] = []
    private var moviePool: [Movie] = []
    /// Per-side load state. Tracked independently so one side failing (or being
    /// rate-limited) can't lock in a *partial* pool for the session — the missing
    /// side is retried on later prepares/shuffles. A side is only "loaded" once it
    /// actually returned entries (an empty result means it failed → retry).
    private var actorsLoaded = false
    private var moviesLoaded = false
    /// Enough of a pool to deal *something* (at least one side landed).
    private var poolReady: Bool { actorsLoaded || moviesLoaded }
    /// Both sides landed — no further loading needed.
    private var poolComplete: Bool { actorsLoaded && moviesLoaded }
    /// The pool load in flight, shared by every caller so a Shuffle tap during
    /// the first load awaits it instead of sending the same requests again.
    private var poolLoad: Task<Void, Never>?
    /// Where the pools persist between launches; `nil` keeps them in memory only
    /// (tests, previews, and the stub provider, whose demo graph must never be
    /// saved as the real pool).
    private let poolCache: SeedPoolCache?
    /// The disk copy is read once, on the first load.
    private var poolCacheChecked = false
    /// A saved copy too old to deal from without refetching, kept for any side
    /// the refetch fails to load.
    private var stalePool: SeedPoolSnapshot?
    /// `ChainNode.id`s dealt recently, so repeated shuffles stay fresh. Bounded to
    /// `Config.seedRecentWindow`.
    private var recentSeedIds: [String] = []
    /// Concrete generator for deals (a stored `var` so it can be passed `inout` to
    /// the generic `SeedDeal.pick`). Selection policy is unit-tested separately in
    /// `SeedDeal` with a seeded generator, so the engine needs no injectable RNG.
    private var systemRNG = SystemRandomNumberGenerator()
    /// The registry every completed chain is logged into. Optional so previews
    /// and tests can run without touching disk.
    private let collection: CollectionStore?
    /// Where head-to-heads are recorded; `nil` records none (tests, previews).
    private let rivals: RivalStore?
    /// Valid next nodes for the current turn (cast or filmography), pre-wrapped.
    private var candidates: [ChainNode] = []
    /// The dealt start's candidates, fetched while the player is still looking at
    /// the home screen (`prefetchCandidates`), so its first turn is answerable the
    /// moment the keyboard is up. Keyed by node id; one at a time, since only the
    /// start on screen can be played.
    private var prefetch: (id: String, task: Task<[ChainNode]?, Never>)?
    private var usedIds: Set<String> = []
    private var countdownTask: Task<Void, Never>?
    /// Monotonic token identifying the current run/turn's async work. Every
    /// lifecycle transition (start, end, reset) bumps it; an async candidate load
    /// captures it before awaiting and drops its result if the token has moved on.
    /// Without this, a slow `loadCandidates` from a quit/abandoned game can resume
    /// *after* the player has started a new game and install the previous node's
    /// cast/filmography into the new round — the `phase == .playing` guard alone
    /// can't catch it, because the new game is also `.playing`.
    private var generation = 0

    // The current turn's record, folded into a `Turn` when it's answered.
    /// Injectable so tests can time turns exactly.
    private let now: () -> ContinuousClock.Instant
    private var turnMisses: [String] = []
    /// When the running clock last started; nil while it's stopped.
    private var turnClockStart: ContinuousClock.Instant?
    private var turnClockTime: Duration = .zero
    private var turnLoadTime: Duration = .zero
    private var playTime: Duration = .zero
    private var retries = 0

    /// Where the best run persists. Injectable so tests never touch the app's
    /// real records.
    private let defaults: UserDefaults
    private static let bestChainKey = "bestChain"
    private static let bestPointsKey = "bestPoints"
    private static let dailyResultsKey = "dailyResults"
    private static let servedDailiesKey = "servedDailyStarts"
    /// Decides which local day it is, for the daily start. Injected so tests pin it.
    private let calendar: Calendar
    private let today: () -> Date
    /// Where published daily starts come from; `nil` plays the built-in list only
    /// (tests, previews, the stub provider).
    private let dailyFeed: (any DailyStartFeed)?
    /// Where finished runs go for the service's `results`; `nil` sends nothing
    /// (tests, previews, demo launches).
    private let results: ResultsOutbox?
    /// The daily fetch in flight, joined rather than repeated.
    private var dailyLoad: Task<Void, Never>?
    /// When the served days last arrived, so every "Play again" doesn't refetch.
    private var dailiesFetchedAt: Date?

    init(provider: (any MovieDataProvider)? = nil, collection: CollectionStore? = nil,
         rivals: RivalStore? = nil,
         poolCache: SeedPoolCache? = nil, defaults: UserDefaults = .standard,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
         calendar: Calendar = .current, today: @escaping () -> Date = Date.init,
         dailyFeed: (any DailyStartFeed)? = nil, results: ResultsOutbox? = nil) {
        // Resolve the default in the init body (which is @MainActor-isolated),
        // not in a default argument — default arguments evaluate in a
        // nonisolated context, and Config.makeProvider() is @MainActor under
        // the project's MainActor-default isolation.
        self.provider = provider ?? Config.makeProvider()
        self.collection = collection
        self.rivals = rivals
        self.poolCache = poolCache
        self.defaults = defaults
        self.now = now
        self.bestChain = defaults.integer(forKey: Self.bestChainKey)
        self.bestPoints = defaults.integer(forKey: Self.bestPointsKey)
        self.calendar = calendar
        self.today = today
        self.dailyFeed = dailyFeed
        self.results = results
        self.dailyResults = defaults.data(forKey: Self.dailyResultsKey)
            .flatMap { try? JSONDecoder().decode([Int: DailyResult].self, from: $0) } ?? [:]
        self.servedDailies = defaults.data(forKey: Self.servedDailiesKey)
            .flatMap { try? JSONDecoder().decode([Int: DailyStart.Entry].self, from: $0) } ?? [:]
    }

    var current: ChainNode? { chain.last }

    /// A spoiler-free, shareable recap of the finished run: the score line plus a
    /// blue/purple square rendering of the chain (🟦 actor, 🟪 movie) — the
    /// Connections-style share card. Pure text, so the engine stays UIKit-free.
    // MARK: Seed selection

    /// Global search for the starting node.
    func search(_ query: String) async -> [ChainNode] {
        do {
            switch seedKind {
            case .actor:
                return try await provider.searchActors(query).map(ChainNode.actor)
            case .movie:
                return try await provider.searchMovies(query).map(ChainNode.movie)
            }
        } catch {
            // A failed seed search surfaces as an empty result set — `SeedView`
            // shows its "no matches" empty state. Deliberately do *not* write
            // `feedback` here: that field is gameplay feedback (read by `GameView`
            // for rejected links), and a debounced seed search that only resolves
            // *after* the player has tapped a result and the round has begun would
            // otherwise buzz a stale error mid-game.
            return []
        }
    }

    // MARK: Seed deal (the home-screen "Start with …" button)

    /// Load the deal pools (once) and deal a fresh start. Called when the home
    /// screen appears, so every entry to `.seed` — cold launch or "Play again" —
    /// presents a new dealt start. While the pool loads on first launch,
    /// `dealtSeed` stays `nil` and the home shows a placeholder.
    func prepareSeeds() async {
        // Today's daily needs no pool, so it's on the home at once; the pool
        // still loads for "Deal again". A saved pool is read first (it's
        // synchronous), so the daily has its art from the first frame.
        readPoolCacheOnce()
        // A challenge that arrived while away leads; then today's daily. One that
        // arrived on the home already (a link can open the app before this runs)
        // stays.
        let dealtTheDaily: Bool
        if let pendingChallenge {
            dealChallenge(pendingChallenge)
            dealtTheDaily = false
        } else {
            dealtTheDaily = dealtChallenge == nil && dealDaily()
        }
        // The published days load alongside the pool; a different start for today
        // replaces the fallback on the home as soon as it lands.
        async let dailiesRefreshed: Void = refreshDailies()
        // Runs that ended without signal go now.
        if let results { Task { await results.flush() } }
        // Retry a transient pool-load failure a few times so a flaky first launch
        // self-heals while the player is still on the home screen. A hard failure
        // sets `dealFailed`, and the home's "Reconnect" calls this again (a side
        // stays unloaded until it actually returns entries). The flag only changes
        // once the attempts are over, so a retry doesn't flash "Dealing…".
        for attempt in 0..<3 {
            await loadSeedPoolsIfNeeded()
            if Task.isCancelled { return }
            if poolComplete { break }
            if attempt < 2 { try? await Task.sleep(for: .seconds(1)) }
            if Task.isCancelled { return }
        }
        guard !Task.isCancelled else { return }   // don't deal into an abandoned screen
        // Still on a challenge (one may have arrived during the load) or the daily:
        // the pool may have brought its art and popularity. Otherwise this visit's
        // first random deal.
        if let dealtChallenge {
            dealtSeed = resolved(kind: dealtChallenge.start.kind, id: dealtChallenge.start.id)
                ?? dealtChallenge.startNode
        } else if !dealtTheDaily {
            deal()
        } else if let entry = dealtDaily.flatMap(dailyEntry) {
            dealtSeed = resolved(entry)
        }
        dealFailed = !poolReady
        await dailiesRefreshed
    }

    /// Deal a new random start on demand (the Shuffle button). Pools are usually
    /// ready by the time the player can tap; if not (a fast tap during first
    /// load), the deal is deferred until a side lands. If a side failed earlier,
    /// quietly retry it in the background so later deals can include it.
    func shuffleSeed() {
        guard poolReady else {
            Task { await loadSeedPoolsIfNeeded(); deal() }
            return
        }
        deal()
        if !poolComplete { Task { await loadSeedPoolsIfNeeded() } }
    }

    /// Re-deal when the app returns from the background while still on the home
    /// screen — "a fresh start every open/resume". No-op mid-game or before a pool
    /// side has landed (cold launch is handled by `prepareSeeds`).
    func dealFreshOnResume() {
        // A challenge on the home stays put: it's what the player came back for.
        guard phase == .seed, dealtChallenge == nil else { return }
        // Leads with the daily until it's played — also how a new day's start
        // reaches a home left open overnight.
        Task { await refreshDailies() }
        if dealDaily() { return }
        guard poolReady else { return }
        deal()
        if !poolComplete { Task { await loadSeedPoolsIfNeeded() } }
    }

    /// Load the pool side(s) not yet loaded, joining a load already in flight
    /// rather than starting a second one. The load is its own task, so a caller
    /// leaving the seed screen doesn't cancel it: whatever lands is still cached
    /// for the next deal.
    private func loadSeedPoolsIfNeeded() async {
        readPoolCacheOnce()
        guard !poolComplete else { return }
        if let poolLoad {
            await poolLoad.value
            return
        }
        let load = Task { await fetchMissingPools() }
        poolLoad = load
        await load.value
        poolLoad = nil
    }

    /// Fetch the missing side(s) concurrently. Each side is marked loaded **only
    /// when it returns entries** — an empty result (a failed or rate-limited
    /// fetch, incl. the derived-actor task group swallowing per-cast failures)
    /// leaves that side unloaded so it retries later, rather than caching a
    /// partial (e.g. movie-only) pool for the whole session.
    private func fetchMissingPools() async {
        async let actorsTask = fetchActorsIfNeeded()
        async let moviesTask = fetchMoviesIfNeeded()
        let actors = await actorsTask
        let movies = await moviesTask
        let fetchedActors = actors?.isEmpty == false
        let fetchedMovies = movies?.isEmpty == false
        if let actors, fetchedActors { actorPool = actors; actorsLoaded = true }
        if let movies, fetchedMovies { moviePool = movies; moviesLoaded = true }

        // Save once both sides are in and this fetch brought at least one of them,
        // so a pool only ever reaches disk whole. A side filled from the stale copy
        // below isn't fresh, so it doesn't count.
        if poolComplete, fetchedActors || fetchedMovies {
            await poolCache?.save(actors: actorPool, movies: moviePool)
        }

        // A side the network couldn't supply falls back to the stale copy: an old
        // pool deals as well as a new one, and beats an empty home.
        if let stalePool {
            if !actorsLoaded, !stalePool.actors.isEmpty { actorPool = stalePool.actors; actorsLoaded = true }
            if !moviesLoaded, !stalePool.movies.isEmpty { moviePool = stalePool.movies; moviesLoaded = true }
        }
    }

    /// Install the disk copy if it's fresh enough to deal from, so the launch
    /// makes no pool requests at all; otherwise keep it as the fallback.
    private func readPoolCacheOnce() {
        guard !poolCacheChecked else { return }
        poolCacheChecked = true
        guard let saved = poolCache?.load() else { return }
        guard saved.isFresh, !saved.snapshot.actors.isEmpty, !saved.snapshot.movies.isEmpty else {
            stalePool = saved.snapshot
            return
        }
        actorPool = saved.snapshot.actors
        moviePool = saved.snapshot.movies
        actorsLoaded = true
        moviesLoaded = true
    }

    /// `nil` when the side is already loaded (skip) or the fetch failed.
    private func fetchActorsIfNeeded() async -> [Person]? {
        guard !actorsLoaded else { return nil }
        return try? await provider.popularActors()
    }

    private func fetchMoviesIfNeeded() async -> [Movie]? {
        guard !moviesLoaded else { return nil }
        return try? await provider.popularMovies()
    }

    private func deal() {
        guard let node = SeedDeal.pick(
            actors: actorPool,
            movies: moviePool,
            recentIds: Set(recentSeedIds),
            actorBias: Config.seedActorBias,
            using: &systemRNG
        ) else { return }
        dealtSeed = node
        dealtDaily = nil
        dealtChallenge = nil
        recentSeedIds.append(node.id)
        if recentSeedIds.count > Config.seedRecentWindow {
            recentSeedIds.removeFirst(recentSeedIds.count - Config.seedRecentWindow)
        }
    }

    // MARK: Daily start

    /// Today's daily number while it hasn't been played on this phone.
    var unplayedDaily: Int? {
        guard let number = todaysNumber,
              dailyResults[number] == nil,
              dailyEntry(number) != nil
        else { return nil }
        return number
    }

    private var todaysNumber: Int? { DailyStart.number(on: today(), calendar: calendar) }

    /// Day `number`'s start: as published, else from the fallback list.
    private func dailyEntry(_ number: Int) -> DailyStart.Entry? {
        servedDailies[number] ?? DailyStart.entry(number: number)
    }

    /// Fetch the published days from today through the week ahead, at most once
    /// per `Config.dailyRefreshInterval`. A failure keeps what's saved (or the
    /// list) and is retried on the next visit home. If today's daily is on the
    /// home and the service has a different start for it, the home shows that one.
    func refreshDailies() async {
        guard let dailyFeed, let number = todaysNumber else { return }
        if let dailyLoad {
            await dailyLoad.value
            return
        }
        if let dailiesFetchedAt, today().timeIntervalSince(dailiesFetchedAt) < Config.dailyRefreshInterval {
            return
        }
        let load = Task {
            guard let fetched = try? await dailyFeed.dailyStarts(number...(number + Config.dailyDaysAhead))
            else { return }
            dailiesFetchedAt = today()
            servedDailies.merge(fetched) { $1 }
            servedDailies = servedDailies.filter { $0.key >= number }
            defaults.set(try? JSONEncoder().encode(servedDailies), forKey: Self.servedDailiesKey)
            // A newer start for the daily on screen replaces it, unless it's being
            // played already (`phase` has moved on) or the player dealt away.
            if phase == .seed, dealtDaily == number, let entry = dailyEntry(number),
               dealtSeed?.id != resolved(entry).id {
                dealtSeed = resolved(entry)
            }
        }
        dailyLoad = load
        await load.value
        dailyLoad = nil
    }

    /// Put today's daily on the home, if it's unplayed (the home's "Today" pill,
    /// and the first deal of every visit until it's played). Returns whether it did.
    @discardableResult
    func dealDaily() -> Bool {
        guard let number = unplayedDaily, let entry = dailyEntry(number) else { return false }
        dealtSeed = resolved(entry)
        dealtDaily = number
        dealtChallenge = nil
        return true
    }

    /// The daily as the pool knows it (art, popularity, genres), or bare.
    private func resolved(_ entry: DailyStart.Entry) -> ChainNode {
        resolved(kind: entry.kind, id: entry.id) ?? entry.node
    }

    /// A start as the pool knows it, if the pool has it.
    private func resolved(kind: NodeKind, id: Int) -> ChainNode? {
        switch kind {
        case .actor: actorPool.first { $0.id == id }.map(ChainNode.actor)
        case .movie: moviePool.first { $0.id == id }.map(ChainNode.movie)
        }
    }

    // MARK: Challenges

    /// A friend's challenge, opened from a link (not one played here already —
    /// the root checks). On the home it's dealt at once; otherwise it waits for
    /// the next visit home, so a run in progress is never interrupted.
    func receiveChallenge(_ challenge: SharedChain) {
        if phase == .seed {
            dealChallenge(challenge)
        } else {
            pendingChallenge = challenge
        }
    }

    private func dealChallenge(_ challenge: SharedChain) {
        pendingChallenge = nil
        dealtChallenge = challenge
        dealtDaily = nil
        dealtSeed = resolved(kind: challenge.start.kind, id: challenge.start.id) ?? challenge.startNode
    }

    private func saveDailyResults() {
        // Encoding ints and bools can't fail.
        defaults.set(try? JSONEncoder().encode(dailyResults), forKey: Self.dailyResultsKey)
    }

    /// Fetch `node`'s candidates ahead of play — the home calls this once a dealt
    /// start has settled on screen. A fetch already in flight for the same node is
    /// kept, not repeated; one for a different node is cancelled and replaced (so
    /// a run of Deal agains doesn't leave requests running against the rate
    /// limit). A failure just means `startGame` loads them itself.
    func prefetchCandidates(for node: ChainNode) {
        guard prefetch?.id != node.id else { return }
        prefetch?.task.cancel()
        prefetch = (node.id, Task { try? await fetchCandidates(for: node) })
    }

    /// Start a run from `seed`. Pass `daily` when the seed is today's daily
    /// (`dealtDaily`): the attempt is used up here, at the start, so quitting or
    /// closing the app mid-run doesn't buy a second go. A day already played
    /// starts as an ordinary run. A `challenge` (`dealtChallenge`) is used up
    /// the same way.
    func startGame(with seed: ChainNode, daily: Int? = nil, challenge: SharedChain? = nil) async {
        resetRun()
        dealtChallenge = nil
        if let daily, dailyResults[daily] == nil {
            runDaily = daily
            dailyResults[daily] = DailyResult()
            saveDailyResults()
        }
        if let challenge, rivals?.match(for: challenge) == nil {
            runChallenge = challenge
            rivals?.began(challenge, at: today())
        }
        let token = generation
        chain = [seed]
        usedIds = [seed.id]
        phase = .playing
        let ahead = prefetch?.id == seed.id ? prefetch?.task : nil
        prefetch = nil
        if let ahead {
            expectedKind = seed.nextKind
            isChecking = true
            let began = now()
            let loaded = await ahead.value
            // Counted only if this run still owns the wait; a reset during it
            // has already moved on to a new run's record.
            if generation == token { turnLoadTime += now() - began }
            if let loaded, !loaded.isEmpty {
                guard generation == token else { return }
                candidates = loaded
                isChecking = false
            } else {
                await loadCandidates(for: seed, token: token)
            }
        } else {
            await loadCandidates(for: seed, token: token)
        }
        // Bail if a reset/quit/new game happened during the await.
        guard phase == .playing, generation == token else { return }
        if holdsFirstTurnClock && !playerIsReady {
            clockPending = true
        } else {
            startCountdown()
        }
    }

    /// The play screen is ready for input (keyboard up). Starts the first turn's
    /// clock if `startGame` is holding it; harmless to call more than once.
    func playerReady() {
        guard phase == .playing, !playerIsReady else { return }
        playerIsReady = true
        if clockPending {
            clockPending = false
            startCountdown()
        }
    }

    // MARK: Play

    /// Validate the player's free-text answer against the bounded candidate set.
    func submit(_ text: String) async {
        guard phase == .playing, !isChecking, !timeUp else { return }
        let token = generation
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let match = FuzzyMatch.bestMatch(
            for: trimmed,
            in: candidates,
            nameOf: { $0.matchText }
        )

        guard let match else {
            feedback = "Not in the \(expectedKind == .actor ? "cast" : "filmography") — try again."
            rejections += 1
            turnMisses.append(trimmed)
            return
        }
        let node = match.item

        guard !usedIds.contains(node.id) else {
            feedback = "\(node.displayName) is already in your chain."
            rejections += 1
            turnMisses.append(trimmed)
            return
        }
        await accept(node, typed: trimmed, token: token)
    }

    /// Commit an accepted link: pause the clock across the fetch, score, extend the
    /// chain, load the next candidate set, then resume — unless the run was
    /// reset/quit mid-await.
    private func accept(_ node: ChainNode, typed: String, token: Int) async {
        // Pause the timer during the network fetch so a slow candidate load can't
        // fire game-over on an answer submitted in time.
        stopCountdown()
        feedback = nil
        if let prompt = chain.last {
            // Recorded before `score` moves, so a view reacting to the new score
            // finds this turn already on the list.
            turns.append(Turn(prompt: prompt, answer: node, typed: typed, misses: turnMisses,
                              answerTime: turnClockTime, loadTime: turnLoadTime))
        }
        turnMisses = []
        turnClockTime = .zero
        turnLoadTime = .zero
        // Score before the clock is reset by the next turn: fast answers and
        // obscure picks bank more points.
        lastGain = Scoring.gain(secondsRemaining: secondsRemaining, popularity: node.popularity)
        lastAnswerFast = Scoring.isFast(secondsRemaining: secondsRemaining,
                                        secondsPerTurn: Config.secondsPerTurn)
        chain.append(node)
        usedIds.insert(node.id)
        score += 1
        points += lastGain
        await loadCandidates(for: node, token: token)

        // The game may have been reset/quit (or a new game started) during the
        // await; only resume the clock if this is still the same live turn.
        guard phase == .playing, generation == token else { return }
        startCountdown()
    }

    /// End the current run in place (the player tapped Quit): stop the clock and
    /// show the game-over summary for the chain as it stands — *not* a reset back
    /// to the seed picker. Records are committed just as a timeout would.
    func quit() {
        guard phase == .playing else { return }
        endGame(quit: true)
    }

    func reset() {
        resetRun()
        phase = .seed
    }

    /// Clear everything that belongs to one run. The single list both `startGame`
    /// and `reset` go through, so the two can't drift apart.
    private func resetRun() {
        generation += 1                            // drop any in-flight candidate load
        stopCountdown()
        chain = []
        usedIds = []
        turns = []
        turnMisses = []
        turnClockTime = .zero
        turnLoadTime = .zero
        playTime = .zero
        retries = 0
        runDaily = nil
        runChallenge = nil
        candidates = []
        score = 0
        points = 0
        lastGain = 0
        lastAnswerFast = false
        feedback = nil
        isChecking = false
        secondsRemaining = Config.secondsPerTurn
        playerIsReady = false
        clockPending = false
        timeUp = false
    }

    // MARK: Candidates

    private func loadCandidates(for node: ChainNode, token: Int) async {
        // Set synchronously (atomic with accepting the link, before any await), so
        // these are never stale writes — only the post-fetch writes below can be.
        expectedKind = node.nextKind
        isChecking = true
        let began = now()
        // Counted only for a load this run still owns; a superseded one is dropped.
        defer { if generation == token { turnLoadTime += now() - began } }
        // Retry a transient failure (a shared-key rate limit or a stalled request —
        // see `Config.makeProvider`'s TODO and `requestTimeout`). The clock is paused
        // across this load, so retries cost the player no time. Without this, one
        // hiccup empties `candidates` and the turn is unanswerable: nothing validates,
        // so the run is stuck until the clock runs out.
        for attempt in 0..<max(1, Config.candidateLoadAttempts) {
            do {
                let loaded = try await fetchCandidates(for: node)
                // Drop a superseded result: a reset/quit/new game moved the token on
                // while this fetch was in flight, so installing its candidates would
                // corrupt the current round.
                guard generation == token else { return }
                candidates = loaded
                feedback = nil
                isChecking = false
                return
            } catch {
                guard generation == token else { return }
                if attempt < Config.candidateLoadAttempts - 1 {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard generation == token else { return }
                    continue
                }
                // Exhausted retries: leave an empty set the player can retry by hand
                // (`retryTurn`), rather than a silently dead turn.
                candidates = []
                feedback = "Couldn't load the next round — tap Retry."
                isChecking = false
            }
        }
    }

    /// The valid next links for `node`: a movie's cast, or an actor's films.
    private func fetchCandidates(for node: ChainNode) async throws -> [ChainNode] {
        switch node {
        case .movie(let movie): try await provider.cast(of: movie).map(ChainNode.actor)
        case .actor(let actor): try await provider.filmography(of: actor).map(ChainNode.movie)
        }
    }

    /// Whether the turn has no answers to give because the candidate load failed —
    /// the signal for the UI's manual Retry affordance (both modes). Distinct from
    /// a load still in flight (`isChecking`).
    var awaitingRetry: Bool {
        phase == .playing && !isChecking && candidates.isEmpty && !chain.isEmpty
    }

    /// Re-fetch the current turn's candidates after a load failure and restart the
    /// clock fresh (the failed load wasn't the player's fault, so it shouldn't have
    /// burned their time). Same turn/node, so it rides the current `generation`.
    func retryTurn() async {
        guard phase == .playing, !isChecking, let node = chain.last else { return }
        stopCountdown()
        retries += 1
        let token = generation
        await loadCandidates(for: node, token: token)
        guard phase == .playing, generation == token else { return }
        clockPending = false   // a manual retry starts the clock itself
        startCountdown()
    }

    // MARK: Timer

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        // Bank the time the clock ran. Capped at a turn's length, so the
        // time's-up hold before game over isn't counted as play.
        if let start = turnClockStart {
            let ran = min(now() - start, .seconds(Config.secondsPerTurn))
            turnClockTime += ran
            playTime += ran
            turnClockStart = nil
        }
    }

    private func startCountdown() {
        stopCountdown()
        turnClockStart = now()
        secondsRemaining = Config.secondsPerTurn
        countdownTask = Task { [weak self] in
            // Tick against fixed deadlines from the turn's start, so each second's
            // scheduling slack doesn't accumulate into a longer turn.
            let clock = ContinuousClock()
            let start = clock.now
            var elapsed = 0
            while let self, self.secondsRemaining > 0 {
                elapsed += 1
                try? await Task.sleep(until: start + .seconds(elapsed), clock: clock)
                if Task.isCancelled { return }
                self.secondsRemaining -= 1
            }
            // Time's up: hold on the play screen for a beat so the run visibly
            // ends, then go to game over. `stopCountdown` (quit/reset) cancels it.
            guard let self else { return }
            self.timeUp = true
            try? await Task.sleep(for: Config.timeUpPause)
            if Task.isCancelled { return }
            self.endGame()
        }
    }

    private func endGame(quit: Bool = false) {
        // Guard against a double end: a wrong-tap penalty that zeroes the clock
        // ends the run directly, and the (now-cancelled) countdown task must not
        // end it again.
        guard phase == .playing else { return }
        generation += 1                            // drop any in-flight candidate load
        stopCountdown()
        var summary = Summary(chain: chain, links: score, points: points, endedByQuit: quit,
                              turns: turns, finalMisses: turnMisses, playTime: playTime,
                              retries: retries, daily: runDaily, challenge: runChallenge)
        if let runChallenge {
            rivals?.finished(runChallenge, mine: RunScore(links: score, points: points), at: today())
        }
        if let runDaily {
            dailyResults[runDaily] = DailyResult(links: score, points: points, finished: true)
            saveDailyResults()
        }

        // "You were one away": surface a valid answer the player didn't give on
        // the turn that ran out — the sting that drives the next run. Skip it on a
        // manual quit: there was no missed turn.
        summary.missedAnswer = quit ? nil : candidates.first { !usedIds.contains($0.id) }

        // Commit the record: most links wins, points break a tie, and both
        // numbers are written together so they always describe one run.
        if Scoring.isNewRecord(links: score, points: points,
                               bestLinks: bestChain, bestPoints: bestPoints) {
            summary.previousBest = bestChain
            bestChain = score
            bestPoints = points
            summary.isNewBest = true
            defaults.set(bestChain, forKey: Self.bestChainKey)
            defaults.set(bestPoints, forKey: Self.bestPointsKey)
        }

        // Log the run into the collection. A chain of length ≥ 2 means at least
        // one link was validated, which is exactly the condition we want: the
        // seed (chain[0]) counts only once a real combination lands off it, and
        // a seed-then-quit (length 1) logs nothing. `record` dedups by id, so
        // each entity is counted once per chain.
        if chain.count >= 2 {
            summary.reelAdditions = collection?.record(chain: chain) ?? 0
        }

        results?.record(summary)
        phase = .gameOver(summary)
    }

    #if DEBUG
    // MARK: Preview / QA hook
    //
    // Jump straight into a mid-game `playing` state with a sample chain so the
    // play screen (and its design-system components) can be inspected without
    // typing. Triggered by the `-uiDemoChain` launch argument in `ContentView`;
    // guarded by `#if DEBUG` so it is never compiled into release builds.
    // `worstCase` (`-uiWorstCase`) swaps in the longest real names and titles the
    // deal can serve, ending on a two-line title with a year, and a four-digit
    // score — the regression fixture for the deck, the prompt and the recap.
    func loadDemoChain(worstCase: Bool = false) {
        func actor(_ id: Int, _ name: String) -> ChainNode { .actor(Person(id: id, name: name)) }
        func movie(_ id: Int, _ title: String, _ year: Int) -> ChainNode {
            .movie(Movie(id: id, title: title, year: year))
        }
        chain = worstCase ? [
            actor(1, "Jean-Claude Van Damme"),
            movie(1001, "Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb", 1964),
            actor(2, "Mary Elizabeth Mastrantonio"),
            movie(1002, "Borat: Cultural Learnings of America for Make Benefit Glorious Nation of Kazakhstan", 2006),
            actor(3, "Chiwetel Ejiofor"),
            movie(1004, "Pirates of the Caribbean: The Curse of the Black Pearl", 2003),
        ] : [
            actor(1, "Brad Pitt"),
            movie(1001, "Ocean's Eleven", 2001),
            actor(2, "Matt Damon"),
            movie(1002, "The Departed", 2006),
            actor(3, "Leonardo DiCaprio"),
        ]
        usedIds = Set(chain.map(\.id))
        score = chain.count - 1
        points = worstCase ? 1284 : score * 24
        lastGain = 24
        expectedKind = chain.last?.nextKind ?? .movie
        candidates = worstCase
            ? [.actor(Person(id: 4, name: "Keisha Castle-Hughes"))]
            : [.movie(Movie(id: 1003, title: "Inception", year: 2010))]
        feedback = nil
        secondsRemaining = 18
        phase = .playing
    }

    /// Same sample chain, but jump straight to the game-over summary — a new
    /// best by default, or an ordinary run (`-uiDemoNoBest`), which also ends on
    /// a movie so the film spool shows. `clean` (`-uiDemoClean`) is for the
    /// landing page's screenshots: both end on the same five links, with no near
    /// miss, so the two screens tell one run.
    func loadDemoGameOver(newBest: Bool = true, worstCase: Bool = false, clean: Bool = false,
                          challenge: SharedChain? = nil) {
        loadDemoChain(worstCase: worstCase)
        if !newBest || clean, !worstCase {
            chain.append(.movie(Movie(id: 1003, title: "Inception", year: 2010)))
            score = chain.count - 1
            points = score * 24
        }
        phase = .gameOver(Summary(isNewBest: newBest, previousBest: 2, missedAnswer: clean ? nil : candidates.first,
                                  chain: chain, links: score, points: points, challenge: challenge))
    }

    /// A made-up challenge from "Sam", for `-uiDemoChallenge` (dealt on the home)
    /// and `-uiDemoHeadToHead` (its game over). `worstCase` gives Sam the longest
    /// name a link allows.
    static func demoChallenge(worstCase: Bool = false) -> SharedChain {
        SharedChain(start: .init(kind: .actor, id: 287, name: "Brad Pitt"),
                    links: [1001, 2, 1002, 3], points: 96,
                    sharer: UUID(uuidString: "00000000-0000-0000-0000-00000000005A"),
                    senderName: worstCase ? String(repeating: "Maximiliana ", count: 4) : "Sam")
    }
    #endif
}
