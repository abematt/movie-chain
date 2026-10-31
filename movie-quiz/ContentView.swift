//
//  ContentView.swift
//  movie-quiz
//
//  Root router: swaps between the seed, playing, and game-over screens, and
//  routes an opened chain link (a challenge, or a reply to yours).
//

import SwiftUI

struct ContentView: View {
    @State private var engine: GameEngine
    /// The collection ("Your Reel"), owned at the root and shared with the engine
    /// (which records into it) and the screens that display it.
    @State private var collection: CollectionStore
    /// The head-to-head record, owned here like the collection: the engine records
    /// challenge runs into it, and opened links are checked against it.
    @State private var rivals: RivalStore
    /// A reply to your challenge, or one you'd already played, opened from a link.
    @State private var openedMatch: OpenedMatch?
    /// A link that couldn't become a challenge: why, in a sentence.
    @State private var linkNotice: String?
    /// Whether the branded seed intro has already played. Persisted, so the full
    /// reveal is a genuine first-run moment — it plays once *ever*, and every later
    /// launch (and every "Play again" re-entry, since `SeedView` is recreated on
    /// each return to `.seed`) starts assembled. Owned here, above `SeedView`, and
    /// kept out of `GameEngine` so the engine stays free of view state.
    @AppStorage("seedIntroPlayed") private var seedIntroDone = false
    /// The home → play handoff (see `Handoff.swift`): both screens report into
    /// it, and the flight above them reads it.
    @State private var handoff = HandoffStage()
    /// The anonymous service player (`PlayerSession`); `nil` with no service, in
    /// the test host, previews and demo launches.
    @State private var session: PlayerSession?
    /// Watched so a new name reaches the profile (`PlayerSession.syncProfile`).
    @AppStorage(PlayerName.key) private var playerName = ""
    @AppStorage("soundEnabled") private var soundEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.telemetry) private var telemetry

    init() {
        #if DEBUG
        // QA hook: a demo Reel in memory, leaving the saved one untouched. Pair
        // with `-uiOpenReel` to land on it.
        let store = ProcessInfo.processInfo.arguments.contains("-uiDemoReel")
            ? CollectionStore.demo() : CollectionStore()
        #else
        let store = CollectionStore()
        #endif
        _collection = State(initialValue: store)
        #if DEBUG
        // Demo launches never touch the saved head-to-head record.
        let rivals = ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-uiDemo") })
            ? RivalStore.demo() : RivalStore()
        #else
        let rivals = RivalStore()
        #endif
        _rivals = State(initialValue: rivals)
        // The deal pools persist only for the live provider: the stub's demo graph
        // must never be saved and dealt from once a real token is added.
        let poolCache = Config.hasTMDB
            ? SeedPoolCache.defaultFileURL.map { SeedPoolCache(fileURL: $0) } : nil
        let dailyFeed: (any DailyStartFeed)? = Config.hasService ? ServiceDailyStartFeed() : nil
        let session = Self.makeSession()
        _session = State(initialValue: session)
        let results = session.flatMap(Self.makeResultsOutbox)
        #if DEBUG
        // QA hook: every request fails and nothing saved is read, to see the
        // home's "No connection." state.
        let offline = ProcessInfo.processInfo.arguments.contains("-uiOffline")
        let engine = offline
            ? GameEngine(provider: OfflineProvider(), collection: store)
            : GameEngine(collection: store, rivals: rivals, poolCache: poolCache, dailyFeed: dailyFeed,
                         results: results)
        #else
        let engine = GameEngine(collection: store, rivals: rivals, poolCache: poolCache,
                                dailyFeed: dailyFeed, results: results)
        #endif
        // The play screen releases the first turn's clock once the keyboard is up.
        engine.holdsFirstTurnClock = true
        _engine = State(initialValue: engine)
    }

    /// The service player. Demo launches never reach the service as a player
    /// (their chains are made up), nor does `-uiOffline`.
    private static func makeSession() -> PlayerSession? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains(where: { $0.hasPrefix("-uiDemo") }) || args.contains("-uiOffline") { return nil }
        #endif
        return PlayerSession.live()
    }

    /// Finished runs go to the service as the session's player. Debug builds
    /// mark their runs so development play can be told apart from players'.
    private static func makeResultsOutbox(session: PlayerSession) -> ResultsOutbox {
        #if DEBUG
        let version = Config.appVersion + "-debug"
        #else
        let version = Config.appVersion
        #endif
        let transport = ServiceResultsTransport { forceRefresh in
            await session.accessToken(forceRefresh: forceRefresh)
        }
        return ResultsOutbox(defaults: .standard, appVersion: version, send: transport.send)
    }

    var body: some View {
        Group {
            switch engine.phase {
            // Home → play is not a push: the home *becomes* the play screen (the
            // handoff flies its sentence into the deck and dock), so the two
            // cross-fade underneath the flight — the home out fast, play in a beat
            // later, so the two never sit half-faded over each other. Every other
            // change pushes.
            case .seed:
                SeedView(engine: engine, collection: collection, rivals: rivals, introDone: $seedIntroDone)
                    .transition(.asymmetric(insertion: .screenPush(reduceMotion: reduceMotion),
                                            removal: .opacity.animation(Theme.Motion.layoutOut)))
            case .playing:
                GameView(engine: engine)
                    .transition(.asymmetric(insertion: .opacity.animation(Theme.Motion.layoutIn),
                                            removal: .screenPush(reduceMotion: reduceMotion)))
            case .gameOver(let summary):
                GameOverView(engine: engine, collection: collection, summary: summary)
                    .transition(.screenPush(reduceMotion: reduceMotion))
            }
        }
        .animation(Theme.Motion.screen, value: engine.phase)
        // Capped like the screens it flies between, so its copies match them.
        .overlay { HandoffFlight().dynamicTypeSize(...Theme.Font.gameTypeCap) }
        .coordinateSpace(.named(HandoffStage.space))
        .environment(handoff)
        // Chain links: universal links in Release (once the domain serves the
        // file), the private `unspool-debug://` scheme in Debug.
        .onOpenURL { open($0) }
        // Become the service player now rather than at the first game over, and
        // write the name once it settles (a second after the last keystroke).
        .task(id: playerName) {
            guard let session else { return }
            telemetry?.context.playerID = PlayerID.current(in: .standard)
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            _ = await session.accessToken()
            telemetry?.context.playerID = session.userID ?? PlayerID.current(in: .standard)
            await session.syncProfile(name: PlayerName.current(in: .standard))
        }
        .sheet(item: $openedMatch) { opened in
            MatchSheet(match: opened.match, rival: opened.rival)
        }
        .alert(linkNotice ?? "", isPresented: Binding(get: { linkNotice != nil },
                                                      set: { if !$0 { linkNotice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        // A run that ends mid-flight (Quit is live during it) takes the copies
        // with it, rather than leaving them over the game-over screen.
        .onChange(of: engine.phase) { _, phase in
            if phase != .playing { handoff.finish() }
            // Every run ends here, and screen times start here.
            telemetry?.phaseChanged(to: phase)
        }
        // Settings ride on every event as context, never as events of their own.
        .onChange(of: soundEnabled, initial: true) { _, on in telemetry?.context.soundOn = on }
        .onChange(of: scenePhase) { old, phase in
            // Guarantee the latest collection snapshot is on disk before the app
            // is suspended/killed, not just eventually via the async save.
            if phase != .active { collection.flush() }
            // Deal a fresh start when returning from the background while still on
            // the home screen — "a new start every open/resume". Cold launch is
            // handled by SeedView's `.task`; this covers background → foreground.
            if old == .background, phase == .active {
                telemetry?.resumed()
                engine.dealFreshOnResume()
                // iOS often stops the audio engine while we're away; restart it
                // now so the next chime isn't the one that pays for it.
                if soundEnabled { SoundPlayer.shared.warm() }
            }
        }
        .task {
            // Warm the first screen of Your Reel, so even its first open arrives
            // with art in place instead of each card fading in. Image CDN only
            // (no TMDB API calls), and a no-op from disk after the first time.
            // Actor cards print their photos in a duotone, so that's the image warmed.
            let leading = collection.sortedActors.prefix(12) + collection.sortedMovies.prefix(12)
            await ArtCache.shared.warm(leading.compactMap { entity in
                Config.imageURL(path: entity.imagePath, size: ReelLayout.artSize).map {
                    (url: $0, duotone: entity.kind == .actor ? Duotone.forActor(tmdbID: entity.tmdbID) : nil)
                }
            })
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            let worstCase = args.contains("-uiWorstCase")
            if args.contains("-uiDemoGameOver") {
                engine.loadDemoGameOver(newBest: !args.contains("-uiDemoNoBest"), worstCase: worstCase,
                                        clean: args.contains("-uiDemoClean"))
            } else if args.contains("-uiDemoHeadToHead") {
                engine.loadDemoGameOver(newBest: false, worstCase: worstCase,
                                        challenge: GameEngine.demoChallenge(worstCase: worstCase))
            } else if args.contains("-uiDemoChain") {
                engine.loadDemoChain(worstCase: worstCase)
            } else if args.contains("-uiDemoChallenge") {
                engine.receiveChallenge(GameEngine.demoChallenge(worstCase: worstCase))
            }
            // Open a chain link at launch, skipping the system's "Open in Unspool?"
            // that `simctl openurl` raises (`scripts/sim-challenge.sh --launch`).
            if let flag = args.firstIndex(of: "-uiOpenLink"), args.indices.contains(flag + 1),
               let url = URL(string: args[flag + 1]) {
                open(url)
            }
            #endif
        }
    }
}

extension ContentView {
    /// A link opened while the app runs, or that launched it.
    private func open(_ url: URL) {
        guard let base = Config.shareBaseURL else { return }
        let arrival = rivals.receive(SharedChain.open(url, base: base),
                                     me: PlayerID.all(in: .standard), at: .now)
        telemetry?.challengeOpened(arrival)
        switch arrival {
        case .challenge(let challenge):
            // On the home it's dealt now; mid-run or on game over, on the next visit home.
            engine.receiveChallenge(challenge)
            if engine.phase != .seed {
                linkNotice = "\(challenge.senderName ?? "A friend")’s challenge is waiting on the home screen."
            }
        case .played(let match, let rival), .reply(let match, let rival):
            openedMatch = OpenedMatch(match: match, rival: rival)
        case .own:
            linkNotice = "That’s your own challenge. Send it to a friend."
        case .needsUpdate:
            linkNotice = "This challenge needs a newer Unspool. Update from the App Store."
        case .invalid:
            linkNotice = "That link didn’t work."
        }
    }
}

/// A match a link opened, for the sheet.
struct OpenedMatch: Identifiable {
    let match: Match
    let rival: Rival
    var id: String { match.id }
}

#Preview {
    ContentView()
}
