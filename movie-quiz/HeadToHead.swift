//
//  HeadToHead.swift
//  movie-quiz
//
//  The head-to-head's screens (the record behind them is `Rivals.swift`): the
//  challenge line on the home, the result on game over, the result sheet a reply
//  opens, the Rivals list, and the name you go by. First pass, built for the
//  mechanic; the look is due a design pass (docs/ROADMAP.md → Head-to-head).
//

import SwiftUI

// MARK: - Your name

/// What friends see you as on your challenges. Asked the first time you share;
/// editable in Settings. Not unique, not searchable.
enum PlayerName {
    static let key = "playerName"
    /// The first-share prompt has been shown (saved or skipped), so it's never
    /// asked again.
    static let askedKey = "playerNameAsked"
    static let maxLength = SharedChain.maxSenderLength

    /// The saved name, trimmed; `nil` when there isn't one.
    static func current(in defaults: UserDefaults) -> String? {
        guard let name = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return String(name.prefix(maxLength))
    }
}

// MARK: - Outcome wording

extension Outcome {
    /// The headline, from your side.
    func headline(rival: String) -> String {
        switch self {
        case .win: "You win"
        case .loss: "\(rival) wins"
        case .tie: "A tie"
        }
    }
}

extension Rival {
    /// "3–2", plus ties when there are any: "3–2–1".
    var record: String {
        ties > 0 ? "\(wins)–\(losses)–\(ties)" : "\(wins)–\(losses)"
    }
}

private func linksText(_ links: Int) -> String { links == 1 ? "1 link" : "\(links) links" }

// MARK: - Home: the challenge line

/// Above the dealt start when it's a friend's challenge: who sent it and what
/// they scored. Their route stays hidden until you've played.
struct ChallengeLine: View {
    let challenge: SharedChain

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("\(challenge.senderName ?? "A friend") challenged you")
                .metaLabel(Theme.Color.ink)
                .lineLimit(2)
            Text("\(linksText(challenge.linkCount)) · \(challenge.points.formatted()) pts to beat")
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Color.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Game over: the result

/// The head-to-head under the count on game over: who won, and both scores.
struct HeadToHeadPanel: View {
    let challenge: SharedChain
    let mine: RunScore
    /// The ground's type colours.
    let fg: Color
    let sub: Color

    private var rival: String { challenge.senderName ?? "Them" }
    private var theirs: RunScore { RunScore(links: challenge.linkCount, points: challenge.points) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(Outcome(mine: mine, theirs: theirs).headline(rival: rival))
                .font(Theme.Font.heading(.title2))
                .foregroundStyle(fg)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.lg) {
                side("You", mine)
                side(rival, theirs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func side(_ name: String, _ score: RunScore) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).metaLabel(sub).lineLimit(1)
            Text("\(linksText(score.links)) · \(score.points.formatted()) pts")
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(fg)
        }
    }
}

// MARK: - A match, as a card

/// One match on paper: the start, the headline, both sides. Used by the sheet a
/// reply opens and by the Rivals list.
struct MatchCard: View {
    let match: Match
    let rivalName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                NodeDot(kind: match.startKind)
                Text("From \(match.startName)")
                    .font(Theme.Font.bodyStrong)
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(match.direction == .sent ? "You challenged" : "They challenged")
                    .metaLabel(size: .small)
            }
            if let outcome = match.outcome {
                Text(outcome.headline(rival: rivalName))
                    .font(Theme.Font.heading(.title2))
                    .foregroundStyle(Theme.Color.ink)
            } else {
                Text("Not finished")
                    .font(Theme.Font.heading(.title2))
                    .foregroundStyle(Theme.Color.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.lg) {
                side("You", match.mine)
                side(rivalName, match.theirs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .neoSurface(radius: Theme.Radius.card, shadow: Theme.Shadow.small)
        .accessibilityElement(children: .combine)
    }

    private func side(_ name: String, _ score: RunScore?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).metaLabel().lineLimit(1)
            Text(score.map { "\(linksText($0.links)) · \($0.points.formatted()) pts" } ?? "—")
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Color.ink)
        }
    }
}

// MARK: - The sheet a link opens

/// A reply to your challenge, or a challenge you've already played: how it went,
/// and your record against them.
struct MatchSheet: View {
    let match: Match
    let rival: Rival
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    MatchCard(match: match, rivalName: rival.displayName)
                    Text("You vs \(rival.displayName) · \(rival.record)")
                        .metaLabel()
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Color.canvas.ignoresSafeArea())
            .sheetHeader(match.direction == .sent ? "\(rival.displayName) replied" : "Already played") {
                EmptyView()
            } trailing: {
                Button("Done") { dismiss() }
                    .frame(minHeight: 44)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Rivals

/// Everyone you've played, most recent first, each with their record and matches.
struct RivalsView: View {
    let store: RivalStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    ForEach(store.sorted) { rival in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("You vs \(rival.displayName)")
                                    .font(Theme.Font.heading(.title3))
                                    .foregroundStyle(Theme.Color.ink)
                                    .lineLimit(2)
                                Spacer(minLength: Theme.Spacing.sm)
                                Text(rival.record)
                                    .font(Theme.Font.numeral(.title3))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Color.ink)
                            }
                            .accessibilityElement(children: .combine)
                            ForEach(rival.matches.reversed()) { match in
                                MatchCard(match: match, rivalName: rival.displayName)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Color.canvas.ignoresSafeArea())
            .sheetHeader("Rivals") {
                EmptyView()
            } trailing: {
                Button("Done") { dismiss() }
                    .frame(minHeight: 44)
            }
        }
    }
}

// MARK: - Sharing after the name prompt

/// The system share sheet, for the one share that can't be a `ShareLink`: the
/// first, which asks your name before it opens.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
