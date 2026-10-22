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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let store = CollectionStore()
        _collection = State(initialValue: store)
        _engine = State(initialValue: GameEngine(collection: store))
    }

    var body: some View {
        Group {
            switch engine.phase {
            case .seed:
                SeedView(engine: engine, collection: collection, introDone: $seedIntroDone)
                    .transition(.screenPush(reduceMotion: reduceMotion))
            case .playing:
                GameView(engine: engine)
                    .transition(.screenPush(reduceMotion: reduceMotion))
            case .gameOver(let summary):
                GameOverView(engine: engine, collection: collection, summary: summary)
                    .transition(.screenPush(reduceMotion: reduceMotion))
            }
        }
        .animation(Theme.Motion.screen, value: engine.phase)
        .onChange(of: scenePhase) { old, phase in
            // Guarantee the latest collection snapshot is on disk before the app
            // is suspended/killed, not just eventually via the async save.
            if phase != .active { collection.flush() }
            // Deal a fresh start when returning from the background while still on
            // the home screen — "a new start every open/resume". Cold launch is
            // handled by SeedView's `.task`; this covers background → foreground.
            if old == .background, phase == .active { engine.dealFreshOnResume() }
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
