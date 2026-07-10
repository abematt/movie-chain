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
                // App-wide tint: every interactive control (buttons, the search
                // bar, the segmented picker) inherits this one accent, defined
                // in Assets → AccentColor for light/dark.
                .tint(Color.accentColor)
                // A single rounded type design across the app for a friendlier,
                // game-like feel. Individual views can still override.
                .fontDesign(.rounded)
        }
    }
}
