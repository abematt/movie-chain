//
//  movie_quizApp.swift
//  movie-quiz
//
//  Created by Abraham Mathew on 7/9/26.
//

import SwiftUI

@main
struct movie_quizApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // App-wide tint: interactive controls (the text cursor, the
                // keyboard's Go key) inherit this one accent — near-black ink,
                // defined in Assets → AccentColor for light/dark.
                .tint(Color.accentColor)
                // No app-wide font design: the puzzle-page look pairs the system
                // serif (wordmark, game-over number) with the default sans for
                // all UI. Views opt into serif with `.system(design: .serif)`.
        }
    }
}
