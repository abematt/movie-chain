//
//  ContentView.swift
//  movie-quiz
//
//  Root router: swaps between the seed, playing, and game-over screens.
//

import SwiftUI

struct ContentView: View {
    @State private var engine = GameEngine()

    var body: some View {
        Group {
            switch engine.phase {
            case .seed:
                SeedView(engine: engine)
            case .playing:
                GameView(engine: engine)
            case .gameOver:
                GameOverView(engine: engine)
            }
        }
        .animation(.snappy, value: engine.phase)
    }
}

#Preview {
    ContentView()
}
