//
//  DailyStartTests.swift
//  movie-quizTests
//
//  The daily start: which number a local date is, and the engine's rules around
//  it — it leads the home until played, one attempt (a quit uses it up), and the
//  record survives a relaunch.
//

import Foundation
import Synchronization
import Testing
@testable import movie_quiz

struct DailyStartTests {

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func date(_ day: Int, month: Int = 10, hour: Int = 12, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private let first = DateComponents(year: 2026, month: 10, day: 26)

    @Test func theFirstDayIsNumberOne() {
        let calendar = Self.calendar("Europe/London")
        #expect(DailyStart.number(on: Self.date(26, hour: 0, in: calendar), calendar: calendar, firstDay: first) == 1)
        #expect(DailyStart.number(on: Self.date(26, hour: 23, in: calendar), calendar: calendar, firstDay: first) == 1)
        #expect(DailyStart.number(on: Self.date(27, hour: 0, in: calendar), calendar: calendar, firstDay: first) == 2)
    }

    @Test func thereIsNoDailyBeforeTheFirstDay() {
        let calendar = Self.calendar("Europe/London")
        #expect(DailyStart.number(on: Self.date(25, hour: 23, in: calendar), calendar: calendar, firstDay: first) == nil)
    }

    /// New York's clocks go back on 1 Nov 2026: that 25-hour day is still one day.
    @Test func aDaylightSavingChangeIsStillOneDay() {
        let calendar = Self.calendar("America/New_York")
        #expect(DailyStart.number(on: Self.date(1, month: 11, hour: 23, in: calendar), calendar: calendar, firstDay: first) == 7)
        #expect(DailyStart.number(on: Self.date(2, month: 11, hour: 0, in: calendar), calendar: calendar, firstDay: first) == 8)
    }

    /// The day turns over at each player's own midnight: the same instant can be
    /// tomorrow in Sydney and still today in New York.
    @Test func theDayIsTheLocalDate() {
        let instant = Self.date(27, hour: 1, in: Self.calendar("UTC"))
        #expect(DailyStart.number(on: instant, calendar: Self.calendar("Australia/Sydney"), firstDay: first) == 2)
        #expect(DailyStart.number(on: instant, calendar: Self.calendar("America/New_York"), firstDay: first) == 1)
    }

    @Test func theListWrapsAround() {
        let list: [DailyStart.Entry] = [.actor(1, "A"), .movie(2, "B", 2000), .actor(3, "C")]
        #expect(DailyStart.entry(number: 1, in: list)?.id == 1)
        #expect(DailyStart.entry(number: 3, in: list)?.id == 3)
        #expect(DailyStart.entry(number: 4, in: list)?.id == 1)
        #expect(DailyStart.entry(number: 0, in: list) == nil)
        #expect(DailyStart.entry(number: 1, in: []) == nil)
    }

    @Test func theListIsNotEmptyAndHasNoRepeats() {
        #expect(!DailyStart.entries.isEmpty)
        let keys = DailyStart.entries.map { "\($0.kind)\($0.id)" }
        #expect(Set(keys).count == keys.count)
    }

    // MARK: Served days

    private static func served(_ number: Int, revision: Int = 1, _ entry: DailyStart.Entry?) -> DailyStart.Served {
        DailyStart.Served(number: number, revision: revision, entry: entry)
    }

    @Test func theHighestPlayableRevisionWins() {
        let days = DailyStart.latest([
            Self.served(1, revision: 2, .actor(20, "Fixed")),
            Self.served(1, revision: 1, .actor(10, "Original")),
            Self.served(2, revision: 1, .movie(30, "Kept", 1999)),
            Self.served(2, revision: 2, .actor(0, "No id")),   // a bad fix doesn't win
            Self.served(3, revision: 1, nil),                  // data that didn't decode
            Self.served(0, revision: 1, .actor(40, "Day zero")),
        ])
        #expect(days[1]?.id == 20)
        #expect(days[2]?.id == 30)
        #expect(days[3] == nil)
        #expect(days[0] == nil)
    }

    @Test(arguments: [
        DailyStart.Entry.actor(1, " "),
        DailyStart.Entry.actor(1, String(repeating: "a", count: 201)),
        DailyStart.Entry(kind: .actor, id: 1, name: "An actor with a year", year: 2000),
        DailyStart.Entry.movie(1, "Before film", 1800),
        DailyStart.Entry.movie(-5, "Negative id", 2000),
    ])
    func anUnplayableEntryIsRefused(_ entry: DailyStart.Entry) {
        #expect(!entry.isPlayable)
    }

    /// The table's rows as the REST API returns them; a row whose data doesn't
    /// decode is kept as a gap, not a failed fetch.
    @Test func servedRowsDecode() throws {
        let json = #"""
        [{"number": 1, "revision": 1, "data": {"kind": "actor", "id": 31, "name": "Tom Hanks"}},
         {"number": 2, "revision": 1, "data": {"kind": "movie", "id": 155, "name": "The Dark Knight", "year": 2008}},
         {"number": 3, "revision": 1, "data": {"kind": "director", "id": 1, "name": "Someone"}}]
        """#
        let rows = try JSONDecoder().decode([DailyStart.Served].self, from: Data(json.utf8))
        #expect(rows.map(\.entry) == [.actor(31, "Tom Hanks"), .movie(155, "The Dark Knight", 2008), nil])
    }

    /// The migration seeded the table with the fallback list, so serving those
    /// days changes nothing for anyone who already played them.
    @Test func theSeededDaysMatchTheFallbackList() throws {
        let migration = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "supabase/migrations/20261027120000_puzzles.sql")
        let sql = try String(contentsOf: migration, encoding: .utf8)
        let rows = sql.matches(of: /\('daily_start', (\d+), '(\{.*\})'\)/)
        #expect(rows.count == DailyStart.entries.count)
        for row in rows {
            let entry = try JSONDecoder().decode(DailyStart.Entry.self, from: Data(row.2.utf8))
            #expect(entry == DailyStart.entry(number: Int(row.1)!))
        }
    }
}

// MARK: - The engine

@MainActor
struct DailyStartEngineTests {

    private let defaults = UserDefaults(suiteName: "DailyStartEngineTests-\(UUID().uuidString)")!
    private let calendar = Calendar(identifier: .gregorian)
    private let today = DailyStart.entry(number: 1)!

    /// A pool that holds today's start, with art the bare list entry doesn't have.
    @MainActor
    final class Provider: MovieDataProvider {
        let daily: DailyStart.Entry
        init(daily: DailyStart.Entry) { self.daily = daily }

        func searchActors(_ query: String) async throws -> [Person] { [] }
        func searchMovies(_ query: String) async throws -> [Movie] { [] }
        func popularActors() async throws -> [Person] {
            var actors = [Person(id: 900_001, name: "Someone Else")]
            if daily.kind == .actor { actors.append(Person(id: daily.id, name: daily.name, imagePath: "/art.jpg")) }
            return actors
        }
        func popularMovies() async throws -> [Movie] {
            var movies = [Movie(id: 900_002, title: "Something Else", year: 2000)]
            if daily.kind == .movie { movies.append(Movie(id: daily.id, title: daily.name, year: daily.year, imagePath: "/art.jpg")) }
            return movies
        }
        func cast(of movie: Movie) async throws -> [Person] { [Person(id: 900_003, name: "Cast")] }
        func filmography(of actor: Person) async throws -> [Movie] { [Movie(id: 900_004, title: "Film", year: 2000)] }
    }

    /// An engine on day #1.
    private func makeEngine() -> GameEngine {
        let calendar = calendar
        let day = calendar.date(from: DailyStart.firstDay)!.addingTimeInterval(12 * 3600)
        return GameEngine(provider: Provider(daily: today), defaults: defaults,
                          calendar: calendar, today: { day })
    }

    @Test func theDailyLeadsTheHomeWithThePoolsArt() async {
        let engine = makeEngine()
        await engine.prepareSeeds()

        #expect(engine.dealtDaily == 1)
        #expect(engine.dealtSeed?.tmdbID == today.id)
        #expect(engine.dealtSeed?.imagePath == "/art.jpg")
    }

    /// The pool's copy of the daily equals the bare one (same id), so a plain
    /// observed property would skip the swap and the home would never get the art.
    @Test func swappingInThePoolsCopyIsObserved() async {
        let engine = makeEngine()
        #expect(engine.dealDaily())
        #expect(engine.dealtSeed?.imagePath == nil)

        let changed = Changed()
        withObservationTracking { _ = engine.dealtSeed } onChange: { changed.set() }
        await engine.prepareSeeds()

        #expect(engine.dealtSeed?.imagePath == "/art.jpg")
        #expect(changed.isSet)
    }

    /// Set from observation's `onChange`, which can run off the main actor.
    nonisolated final class Changed: Sendable {
        private let flag = Mutex(false)
        func set() { flag.withLock { $0 = true } }
        var isSet: Bool { flag.withLock { $0 } }
    }

    @Test func dealAgainLeavesTheDailyAndTodayBringsItBack() async {
        let engine = makeEngine()
        await engine.prepareSeeds()

        engine.shuffleSeed()
        #expect(engine.dealtDaily == nil)
        #expect(engine.unplayedDaily == 1)

        #expect(engine.dealDaily())
        #expect(engine.dealtDaily == 1)
    }

    @Test func quittingUsesUpTheOneAttempt() async {
        let engine = makeEngine()
        await engine.prepareSeeds()
        let seed = engine.dealtSeed!

        await engine.startGame(with: seed, daily: 1)
        #expect(engine.dailyResults[1] == DailyResult())   // written at the start
        #expect(engine.unplayedDaily == nil)

        engine.quit()
        #expect(engine.summary?.daily == 1)
        #expect(engine.dailyResults[1]?.finished == true)

        // Back home: a random deal, and no way back to the daily.
        engine.reset()
        await engine.prepareSeeds()
        #expect(engine.dealtDaily == nil)
        #expect(!engine.dealDaily())
    }

    @Test func thePlayedDaySurvivesARelaunch() async {
        let engine = makeEngine()
        await engine.prepareSeeds()
        await engine.startGame(with: engine.dealtSeed!, daily: 1)
        // The app is closed mid-run: the attempt is still gone.

        let relaunched = makeEngine()
        #expect(relaunched.dailyResults[1] == DailyResult())
        #expect(relaunched.unplayedDaily == nil)
    }

    @Test func aPlayedDayStartsAsAnOrdinaryRun() async {
        let engine = makeEngine()
        await engine.prepareSeeds()
        let seed = engine.dealtSeed!
        await engine.startGame(with: seed, daily: 1)
        engine.quit()

        await engine.startGame(with: seed, daily: 1)
        engine.quit()
        #expect(engine.summary?.daily == nil)
    }

    @Test func theShareCardNamesTheDay() {
        let summary = GameEngine.Summary(links: 3, points: 120, daily: 12)
        #expect(summary.shareText(link: nil).hasPrefix("Unspool #12 🎬"))
        #expect(GameEngine.Summary(links: 3).shareText(link: nil).hasPrefix("Unspool 🎬"))
    }
}

// MARK: - Served by the service

@MainActor
struct ServedDailyStartTests {

    private let defaults = UserDefaults(suiteName: "ServedDailyStartTests-\(UUID().uuidString)")!
    private let calendar = Calendar(identifier: .gregorian)
    private let listed = DailyStart.entry(number: 1)!
    private let published = DailyStart.Entry.actor(900_100, "Published Star")

    /// The days the service has published, or a failure.
    @MainActor
    final class Feed: DailyStartFeed {
        var days: [Int: DailyStart.Entry]
        var fails = false
        private(set) var calls = 0
        init(_ days: [Int: DailyStart.Entry] = [:]) { self.days = days }

        func dailyStarts(_ numbers: ClosedRange<Int>) async throws -> [Int: DailyStart.Entry] {
            calls += 1
            if fails { throw DataProviderError.badResponse(503) }
            return days.filter { numbers.contains($0.key) }
        }
    }

    /// An engine on day #1.
    private func makeEngine(_ feed: Feed) -> GameEngine {
        let day = calendar.date(from: DailyStart.firstDay)!.addingTimeInterval(12 * 3600)
        return GameEngine(provider: DailyStartEngineTests.Provider(daily: listed), defaults: defaults,
                          calendar: calendar, today: { day }, dailyFeed: feed)
    }

    @Test func aPublishedDayReplacesTheListOnTheHome() async {
        let engine = makeEngine(Feed([1: published]))
        await engine.prepareSeeds()

        #expect(engine.dealtDaily == 1)
        #expect(engine.dealtSeed?.tmdbID == published.id)
        #expect(engine.dealtSeed?.displayName == published.name)
    }

    @Test func aFailedFetchPlaysTheList() async {
        let feed = Feed([1: published])
        feed.fails = true
        let engine = makeEngine(feed)
        await engine.prepareSeeds()

        #expect(engine.dealtDaily == 1)
        #expect(engine.dealtSeed?.tmdbID == listed.id)
    }

    @Test func publishedDaysAreKeptForALaunchWithoutSignal() async {
        await makeEngine(Feed([1: published])).prepareSeeds()

        let offline = Feed()
        offline.fails = true
        let relaunched = makeEngine(offline)
        #expect(relaunched.dealDaily())
        #expect(relaunched.dealtSeed?.tmdbID == published.id)
    }

    @Test func aDailyInPlayIsNotSwapped() async {
        let feed = Feed()
        feed.fails = true   // so the next refresh isn't held back by the last one
        let engine = makeEngine(feed)
        await engine.prepareSeeds()
        await engine.startGame(with: engine.dealtSeed!, daily: 1)

        feed.fails = false
        feed.days = [1: published]
        await engine.refreshDailies()
        #expect(feed.calls == 2)
        #expect(engine.chain.first?.tmdbID == listed.id)
        #expect(engine.dealtSeed?.tmdbID == listed.id)
    }

    @Test func visitsHomeWithinTheHourDontRefetch() async {
        let feed = Feed([1: published])
        let engine = makeEngine(feed)
        await engine.prepareSeeds()
        await engine.prepareSeeds()
        #expect(feed.calls == 1)
    }
}
