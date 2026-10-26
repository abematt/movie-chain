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
//  Sound, the analytics opt-out, links out to the website (privacy policy, the
//  feature board, contact), and the version.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("soundEnabled") private var soundEnabled = true
    /// Read at launch by `movie_quizApp` too, so the choice holds from the first event.
    @AppStorage(Telemetry.enabledKey) private var analyticsEnabled = true
    @Environment(\.telemetry) private var telemetry
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    soundSection
                    privacySection
                    feedbackSection
                    aboutSection
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Color.canvas.ignoresSafeArea())
            .sheetHeader("Settings") {
                EmptyView()
            } trailing: {
                Button("Done") { dismiss() }
                    .frame(minHeight: 44)
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
                .font(Theme.Font.sentence(.footnote))
                .foregroundStyle(Theme.Color.muted)
                .padding(.top, Theme.Spacing.xs)

            linkRow("Privacy policy", to: Config.privacyPolicyURL, hint: "Opens in Safari")
                .padding(.top, Theme.Spacing.xs)
        }
    }

    // MARK: Feedback — the feature board and a way to write in
    //
    // These send no analytics: the board counts its own visits, and neither link
    // says anything about play (docs/ANALYTICS.md, Privacy).

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Feedback")
            linkRow("Suggest a feature", to: Config.featureBoardURL, hint: "Opens in Safari")
            linkRow("Contact", to: Config.contactURL, hint: "Opens Mail")
        }
    }

    /// A row that leaves the app: the title, and an arrow pointing out.
    private func linkRow(_ title: String, to url: URL, hint: String) -> some View {
        Button { openURL(url) } label: {
            HStack {
                Text(title)
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.muted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 44)
            .padding(.vertical, Theme.Spacing.xs)
            .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressScale)
        .accessibilityHint(hint)
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
                    .font(Theme.Font.sentence(.footnote))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.muted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Unspool version \(Config.appVersion), build \(Config.buildNumber)")

            // The SIL Open Font License asks that the license travel with the
            // fonts; the full texts ship in the bundle as Fonts/*-OFL.txt.
            Text("Set in Archivo by Omnibus-Type and JetBrains Mono by JetBrains, used under the SIL Open Font License 1.1.")
                .font(Theme.Font.sentence(.footnote))
                .foregroundStyle(Theme.Color.muted)
                .padding(.top, Theme.Spacing.xs)

            TMDBAttribution()
                .frame(maxWidth: .infinity)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).metaLabel()
    }
}

#Preview {
    SettingsView()
}
