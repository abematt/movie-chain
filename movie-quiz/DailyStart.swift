//
//  DailyStart.swift
//  movie-quiz
//
//  The daily start: one start a day, the same for everyone, so friends' share
//  cards compare. Served by the service's `puzzles` table (mode `daily_start`,
//  `DailyStartFeed`), so a day can be published or fixed without a release; the
//  hand-picked list here is the fallback for a day the phone hasn't been served.
//  Never each phone's deal pool, which can differ between friends. Not the A→B Daily Chain
//  (docs/DAILY-CHAIN.md) — that comes after launch — but it keys its days the
//  same way: by the player's local date, numbered from #1.
//
//  Pure like `SeedDeal`: the date and calendar are passed in, so tests pin the
//  day and the time zone. One attempt per day is the engine's job.
//

import Foundation

nonisolated enum DailyStart {
    /// One day's start. The name rides along so the home shows it without a
    /// lookup; art and popularity come from the deal pool when the start is in it.
    struct Entry: Equatable, Sendable, Codable {
        var kind: NodeKind
        /// TMDB id.
        var id: Int
        var name: String
        /// Release year, for a movie.
        var year: Int? = nil

        static func actor(_ id: Int, _ name: String) -> Entry { Entry(kind: .actor, id: id, name: name) }
        static func movie(_ id: Int, _ title: String, _ year: Int) -> Entry {
            Entry(kind: .movie, id: id, name: title, year: year)
        }

        /// Sane enough to put on the home. A served entry is checked before it's
        /// kept: a bad row must never be able to break the day.
        var isPlayable: Bool {
            guard id > 0, !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 200
            else { return false }
            switch kind {
            case .actor: return year == nil
            case .movie: return year.map { (1870...2100).contains($0) } ?? true
            }
        }

        @MainActor
        var node: ChainNode {
            switch kind {
            case .actor: .actor(Person(id: id, name: name))
            case .movie: .movie(Movie(id: id, title: name, year: year))
            }
        }
    }

    /// The local date of #1. Days before it have no daily start.
    static let firstDay = DateComponents(year: 2026, month: 10, day: 26)

    /// The fallback starts, in order: #1 is `entries[0]`. When the list runs out it
    /// wraps around. Days are published in the service's `puzzles` table, which
    /// was seeded with this list, so the two agree until a day is published there.
    // TODO: placeholder list — replace with the hand-picked starts.
    static let entries: [Entry] = [
        .actor(31, "Tom Hanks"),
        .movie(155, "The Dark Knight", 2008),
        .actor(6384, "Keanu Reeves"),
        .actor(5064, "Meryl Streep"),
        .movie(597, "Titanic", 1997),
        .actor(6193, "Leonardo DiCaprio"),
        .actor(1245, "Scarlett Johansson"),
        .movie(680, "Pulp Fiction", 1994),
        .actor(287, "Brad Pitt"),
    ]

    /// The day's number for `date` in `calendar`'s time zone, or `nil` before #1.
    static func number(on date: Date, calendar: Calendar, firstDay: DateComponents = firstDay) -> Int? {
        guard let first = calendar.date(from: firstDay) else { return nil }
        // Whole calendar days between the two local midnights, so a 23- or
        // 25-hour DST day still counts as one.
        guard let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                                 to: calendar.startOfDay(for: date)).day,
              days >= 0
        else { return nil }
        return days + 1
    }

    /// One row of the service's `puzzles` table for mode `daily_start`. `entry` is
    /// `nil` when the row's data doesn't decode, so one bad row can't sink the rest.
    struct Served: Decodable, Sendable {
        var number: Int
        var revision: Int
        var entry: Entry?

        init(number: Int, revision: Int, entry: Entry?) {
            self.number = number
            self.revision = revision
            self.entry = entry
        }

        private enum CodingKeys: String, CodingKey { case number, revision, data }

        init(from decoder: any Decoder) throws {
            let row = try decoder.container(keyedBy: CodingKeys.self)
            number = try row.decode(Int.self, forKey: .number)
            revision = try row.decode(Int.self, forKey: .revision)
            entry = try? row.decode(Entry.self, forKey: .data)
        }
    }

    /// Each day's start from served rows: the highest revision that's playable,
    /// since a correction is published as a new revision, never an edit.
    static func latest(_ rows: [Served]) -> [Int: Entry] {
        var best: [Int: (revision: Int, entry: Entry)] = [:]
        for row in rows where row.number >= 1 {
            guard let entry = row.entry, entry.isPlayable else { continue }
            if let kept = best[row.number], kept.revision >= row.revision { continue }
            best[row.number] = (row.revision, entry)
        }
        return best.mapValues(\.entry)
    }

    /// The start for day `number`, wrapping around the list.
    static func entry(number: Int, in entries: [Entry] = entries) -> Entry? {
        guard number >= 1, !entries.isEmpty else { return nil }
        return entries[(number - 1) % entries.count]
    }
}

/// How a daily went, stored by its number. Written when the run starts, so a
/// quit or a force-quit still uses up the day's one attempt.
nonisolated struct DailyResult: Codable, Equatable, Sendable {
    var links = 0
    var points = 0
    /// The run reached game over. `false` means the app was closed mid-run.
    var finished = false
}
