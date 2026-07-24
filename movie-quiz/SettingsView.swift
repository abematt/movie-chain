//
//  SettingsView.swift
//  movie-quiz
//
//  The app's first real settings surface, opened as a sheet from the home screen.
//  Kept deliberately small and on-brand (a warm-paper card layout, not a stock
//  grouped `Form`) to match the rest of the app. Everything here is backed by
//  `@AppStorage`, the app's existing lightweight-preference idiom (the sound
//  toggle used to live inline in the game chrome; it now has a home here too).
//
//  Difficulty is a *session-level* choice made on the home screen before each
//  run; this holds the persisted default, and — because both bind the same
//  `@AppStorage("difficulty")` key — the two controls stay in sync.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("difficulty") private var difficulty: Difficulty = .hardcore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    difficultySection
                    soundSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Color.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Difficulty

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Difficulty")
            DifficultyToggle(selection: $difficulty)
            Text(difficulty == .assisted
                 ? "Assisted shows three options each turn — tap the one that fits. A wrong tap costs \(Config.assistedWrongPenalty) seconds. Assisted runs keep their own best, separate from Hardcore."
                 : "Hardcore is the recall game: type each answer from memory, spelling forgiven. This is the default and sets your headline best.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(Theme.Motion.standard, value: difficulty)
        }
    }

    // MARK: Sound

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Sound")
            Toggle(isOn: $soundEnabled) {
                Text("Sound effects")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.ink)
            }
            .tint(Theme.Color.ink)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(.tertiary)
    }
}

#Preview {
    SettingsView()
}
