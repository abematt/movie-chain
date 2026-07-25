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
//  Currently just the sound toggle (which also still lives inline in the game
//  chrome) — but it's the established home for whatever settings come next.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("soundEnabled") private var soundEnabled = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    soundSection
                    aboutSection
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

    // MARK: About — the app version
    //
    // Pulled from the bundle via `Config.versionString`, so it always reports the
    // build the player is actually running (the number to quote in a bug report).

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("About")
            HStack {
                Text("Movie Chain")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                Text(Config.versionString)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(Theme.Color.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Movie Chain version \(Config.appVersion), build \(Config.buildNumber)")
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
