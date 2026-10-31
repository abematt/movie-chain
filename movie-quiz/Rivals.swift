//
//  Rivals.swift
//  movie-quiz
//
//  The head-to-head (docs/ROADMAP.md → Head-to-head): every share is a challenge,
//  a friend plays the same start once, and a reply link carries both runs back.
//  This file keeps the record of it on the phone: one `Rival` per person, keyed
//  by their sharer id (so two Sams stay apart), each with its matches.
//
//  Strictly one-to-one. A challenge posted to a group comes back as one reply per
//  friend, and each is its own match against its own rival.
//
//  `receive` decides what an opened link is — a new challenge, one already
//  played, a reply to yours, your own — and records what it can, so the root only
//  routes the answer. Names update by link: the latest name seen for a sharer id
//  wins. Persisted as JSON in `UserDefaults`, injected so tests use their own.
//

import Foundation
import Observation

/// One side of a head-to-head: what a run scored.
nonisolated struct RunScore: Codable, Equatable, Sendable {
    var links: Int
    var points: Int
}

/// Who won, from your side. Most links wins; points break a tie — the best run's
/// rule (`Scoring.isNewRecord`).
nonisolated enum Outcome: String, Codable, Sendable {
    case win, loss, tie

    init(mine: RunScore, theirs: RunScore) {
        if mine.links != theirs.links {
            self = mine.links > theirs.links ? .win : .loss
        } else if mine.points != theirs.points {
            self = mine.points > theirs.points ? .win : .loss
        } else {
            self = .tie
        }
    }
}

/// One challenge between you and one rival.
nonisolated struct Match: Codable, Equatable, Identifiable, Sendable {
    enum Direction: String, Codable, Sendable {
        /// They challenged you, and you played it.
        case received
        /// You challenged them, and their reply came back.
        case sent
    }

    var id: String
    var direction: Direction
    var startKind: NodeKind
    var startID: Int
    var startName: String
    var theirs: RunScore
    /// `nil` while you're playing their challenge: the try is used up when the run
    /// starts, like the daily's, so quitting doesn't buy a second go.
    var mine: RunScore?
    var date: Date

    /// `nil` until both runs are in.
    var outcome: Outcome? { mine.map { Outcome(mine: $0, theirs: theirs) } }
}

/// Everyone you've played, by their sharer id.
nonisolated struct Rival: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// What they call themselves, as of their latest link.
    var name: String?
    /// Oldest first.
    var matches: [Match]

    var displayName: String { name ?? "A friend" }
    var wins: Int { matches.count(where: { $0.outcome == .win }) }
    var losses: Int { matches.count(where: { $0.outcome == .loss }) }
    var ties: Int { matches.count(where: { $0.outcome == .tie }) }
    var lastPlayed: Date { matches.map(\.date).max() ?? .distantPast }
}

/// What an opened link turned out to be.
enum Arrival: Equatable {
    /// Someone's challenge, not played yet: deal it.
    case challenge(SharedChain)
    /// A challenge already played here: show how it went, don't replay it.
    case played(Match, Rival)
    /// A reply to one of your challenges, now recorded.
    case reply(Match, Rival)
    /// Your own link.
    case own
    /// From a newer Unspool.
    case needsUpdate
    case invalid
}

@MainActor
@Observable
final class RivalStore {
    private(set) var rivals: [UUID: Rival]

    private let defaults: UserDefaults
    private static let key = "rivals"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Rival].self, from: $0) } ?? []
        rivals = Dictionary(saved.map { ($0.id, $0) }) { first, _ in first }
    }

    var isEmpty: Bool { rivals.isEmpty }

    /// Most recently played first.
    var sorted: [Rival] { rivals.values.sorted { $0.lastPlayed > $1.lastPlayed } }

    // MARK: Opening a link

    /// Decide what `opened` is, recording a reply and refreshing a known name.
    /// `me` is every id this phone has shared under (`PlayerID.all`).
    func receive(_ opened: SharedChain.Opened, me: Set<UUID>, at date: Date) -> Arrival {
        let chain: SharedChain
        switch opened {
        case .needsUpdate: return .needsUpdate
        case .invalid: return .invalid
        case .chain(let opened): chain = opened
        }
        // A challenge needs someone to answer to.
        guard let sender = chain.sharer else { return .invalid }
        if me.contains(sender) { return .own }

        if let original = chain.originalChallenge, let mine = original.sharer, me.contains(mine) {
            let id = Self.sentID(original)
            let match = Match(id: id, direction: .sent, startKind: chain.start.kind,
                              startID: chain.start.id, startName: chain.start.name,
                              theirs: RunScore(links: chain.linkCount, points: chain.points),
                              mine: RunScore(links: original.linkCount, points: original.points),
                              // Opening the same reply again keeps when it first came.
                              date: rivals[sender]?.matches.first { $0.id == id }?.date ?? date)
            let rival = record(match, with: sender, name: chain.senderName)
            return .reply(match, rival)
        }

        // A reply to someone else is its sender's challenge to you, like any other.
        var challenge = chain
        challenge.replyTo = nil
        rename(sender, to: challenge.senderName)
        if let played = match(for: challenge), let rival = rivals[sender] {
            return .played(played, rival)
        }
        return .challenge(challenge)
    }

    /// Your match against `challenge`, once you've started it.
    func match(for challenge: SharedChain) -> Match? {
        guard let sender = challenge.sharer else { return nil }
        let id = Self.receivedID(challenge)
        return rivals[sender]?.matches.first { $0.id == id }
    }

    // MARK: Playing a challenge

    /// The challenge's run has started: its one try is used.
    func began(_ challenge: SharedChain, at date: Date) {
        guard let sender = challenge.sharer, match(for: challenge) == nil else { return }
        record(Match(id: Self.receivedID(challenge), direction: .received,
                     startKind: challenge.start.kind, startID: challenge.start.id,
                     startName: challenge.start.name,
                     theirs: RunScore(links: challenge.linkCount, points: challenge.points),
                     mine: nil, date: date),
               with: sender, name: challenge.senderName)
    }

    /// The challenge's run is over.
    func finished(_ challenge: SharedChain, mine: RunScore, at date: Date) {
        guard let sender = challenge.sharer else { return }
        var match = match(for: challenge)
            ?? Match(id: Self.receivedID(challenge), direction: .received,
                     startKind: challenge.start.kind, startID: challenge.start.id,
                     startName: challenge.start.name,
                     theirs: RunScore(links: challenge.linkCount, points: challenge.points),
                     mine: nil, date: date)
        match.mine = mine
        record(match, with: sender, name: challenge.senderName)
    }

    // MARK: Storage

    private static func receivedID(_ challenge: SharedChain) -> String { "r|" + challenge.challengeKey }
    private static func sentID(_ original: SharedChain) -> String { "s|" + original.challengeKey }

    /// Add or replace `match` under `id`'s rival, creating them if they're new.
    @discardableResult
    private func record(_ match: Match, with id: UUID, name: String?) -> Rival {
        var rival = rivals[id] ?? Rival(id: id, name: nil, matches: [])
        if let name { rival.name = name }
        if let index = rival.matches.firstIndex(where: { $0.id == match.id }) {
            rival.matches[index] = match
        } else {
            rival.matches.append(match)
        }
        rivals[id] = rival
        save()
        return rival
    }

    /// The latest name a rival's links carry wins.
    private func rename(_ id: UUID, to name: String?) {
        guard let name, rivals[id] != nil, rivals[id]?.name != name else { return }
        rivals[id]?.name = name
        save()
    }

    private func save() {
        // Encoding strings, ints and dates can't fail.
        defaults.set(try? JSONEncoder().encode(Array(rivals.values)), forKey: Self.key)
    }

    #if DEBUG
    /// A store for the demo launches, emptied each launch so the real one is
    /// never touched.
    static func demo() -> RivalStore {
        let suite = "demo-rivals"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return RivalStore(defaults: defaults)
    }
    #endif
}
