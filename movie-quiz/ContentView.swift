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
        let engine = GameEngine(collection: store)
        // The play screen releases the first turn's clock once the keyboard is up.
        engine.holdsFirstTurnClock = true
        _engine = State(initialValue: engine)
    }

    var body: some View {
        Group {
            switch engine.phase {
            // Home → play is not a push: the home *becomes* the play screen (the
            // handoff flies its sentence into the deck and dock), so the two
            // cross-fade underneath the flight. Every other change pushes.
            case .seed:
                SeedView(engine: engine, collection: collection, introDone: $seedIntroDone)
                    .transition(.asymmetric(insertion: .screenPush(reduceMotion: reduceMotion),
                                            removal: .opacity))
            case .playing:
                GameView(engine: engine)
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .screenPush(reduceMotion: reduceMotion)))
            case .gameOver(let summary):
                GameOverView(engine: engine, collection: collection, summary: summary)
                    .transition(.screenPush(reduceMotion: reduceMotion))
            }
        }
        .animation(Theme.Motion.screen, value: engine.phase)
        .overlay { HandoffFlight() }
        .coordinateSpace(.named(HandoffStage.space))
        .environment(handoff)
        .onChange(of: scenePhase) { old, phase in
            // Guarantee the latest collection snapshot is on disk before the app
            // is suspended/killed, not just eventually via the async save.
            if phase != .active { collection.flush() }
            // Deal a fresh start when returning from the background while still on
            // the home screen — "a new start every open/resume". Cold launch is
            // handled by SeedView's `.task`; this covers background → foreground.
            if old == .background, phase == .active {
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
            let leading = collection.sortedActors.prefix(12) + collection.sortedMovies.prefix(12)
            await ArtCache.shared.warm(leading.compactMap {
                Config.imageURL(path: $0.imagePath, size: ReelLayout.artSize)
            })
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uiDemoGameOver") {
                engine.loadDemoGameOver()
            } else if args.contains("-uiDemoChain") {
                engine.loadDemoChain()
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
}
