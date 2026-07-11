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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = CollectionStore()
        _collection = State(initialValue: store)
        _engine = State(initialValue: GameEngine(collection: store))
    }

    var body: some View {
        Group {
            switch engine.phase {
            case .seed:
                SeedView(engine: engine, collection: collection)
            case .playing:
                GameView(engine: engine)
            case .gameOver:
                GameOverView(engine: engine, collection: collection)
            }
        }
        .animation(.snappy, value: engine.phase)
        .onChange(of: scenePhase) { _, phase in
            // Guarantee the latest collection snapshot is on disk before the app
            // is suspended/killed, not just eventually via the async save.
            if phase != .active { collection.flush() }
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
