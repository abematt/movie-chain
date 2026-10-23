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
    /// Read at launch by `movie_quizApp` too, so the choice holds from the first event.
    @AppStorage(Telemetry.enabledKey) private var analyticsEnabled = true
    @Environment(\.telemetry) private var telemetry

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    soundSection
                    privacySection
                    aboutSection
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Color.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .neoNavigationBar {
                Text("Settings").font(Theme.Font.heading(.headline)).foregroundStyle(Theme.Color.ink)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("Done").font(Theme.Font.bodyStrong).foregroundStyle(Theme.Color.ink)
                    }
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
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
            }
            .tint(Theme.Color.ink)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
        }
    }

    // MARK: Privacy — the analytics opt-out

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Privacy")
            Toggle(isOn: $analyticsEnabled) {
                Text("Share usage data")
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
            }
            .tint(Theme.Color.ink)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
            .onChange(of: analyticsEnabled) { _, on in telemetry?.setEnabled(on) }

            Text("How you play — your turns, what you type, what you look at in your Reel — so the game gets better. Not linked to who you are.")
                .font(Theme.Font.flourish(.footnote))
                .foregroundStyle(Theme.Color.muted)
                .padding(.top, Theme.Spacing.xs)
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
                Text("Unspool")
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                Text(Config.versionString)
                    .font(Theme.Font.flourish(.footnote))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.muted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Unspool version \(Config.appVersion), build \(Config.buildNumber)")

            // The SIL Open Font License asks that the license travel with the
            // font; the full text ships in the bundle as Fonts/Fraunces-OFL.txt.
            Text("Set in Fraunces by Undercase Type, used under the SIL Open Font License 1.1.")
                .font(Theme.Font.flourish(.footnote))
                .foregroundStyle(Theme.Color.muted)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).metaLabel()
    }
}

#Preview {
    SettingsView()
}
