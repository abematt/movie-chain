//
//  ContentView.swift
//  movie-quiz
//
//  Root router: swaps between the seed, playing, and game-over screens.
//

import SwiftUI

struct ContentView: View {
    @State private var engine: GameEngine
    /// The collection ("Your Reel"), owned at the root and shared with the engine
    /// (which records into it) and the screens that display it.
    @State private var collection: CollectionStore
    /// Whether the branded seed intro has already played. Persisted, so the full
    /// reveal is a genuine first-run moment — it plays once *ever*, and every later
    /// launch (and every "Play again" re-entry, since `SeedView` is recreated on
    /// each return to `.seed`) starts assembled. Owned here, above `SeedView`, and
    /// kept out of `GameEngine` so the engine stays free of view state.
    @AppStorage("seedIntroPlayed") private var seedIntroDone = false
    /// The home → play handoff (see `Handoff.swift`): both screens report into
    /// it, and the flight above them reads it.
    @State private var handoff = HandoffStage()
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
        // The deal pools persist only for the live provider: the stub's demo graph
        // must never be saved and dealt from once a real token is added.
        let poolCache = Config.hasTMDBToken
            ? SeedPoolCache.defaultFileURL.map { SeedPoolCache(fileURL: $0) } : nil
        #if DEBUG
        // QA hook: every request fails and nothing saved is read, to see the
        // home's "No connection." state.
        let offline = ProcessInfo.processInfo.arguments.contains("-uiOffline")
        let engine = offline
            ? GameEngine(provider: OfflineProvider(), collection: store)
            : GameEngine(collection: store, poolCache: poolCache)
        #else
        let engine = GameEngine(collection: store, poolCache: poolCache)
        #endif
        // The play screen releases the first turn's clock once the keyboard is up.
        engine.holdsFirstTurnClock = true
        _engine = State(initialValue: engine)
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
                SeedView(engine: engine, collection: collection, introDone: $seedIntroDone)
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
            } else if args.contains("-uiDemoChain") {
                engine.loadDemoChain(worstCase: worstCase)
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
}
