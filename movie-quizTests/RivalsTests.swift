//
//  RivalsTests.swift
//  movie-quizTests
//
//  The head-to-head: who wins, what an opened link turns out to be, and the
//  record it leaves. The rules are the ones settled in docs/ROADMAP.md →
//  Head-to-head — one try per challenge, strictly one-to-one (a group post comes
//  back as one match per friend), names update by link, dailies aren't
//  challengeable — so each has a test here.
//

import Foundation
import Testing
@testable import movie_quiz

@MainActor
struct RivalsTests {

    private let defaults = UserDefaults(suiteName: "RivalsTests-\(UUID().uuidString)")!
    private let me = UUID()
    private let sam = UUID()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private var store: RivalStore { RivalStore(defaults: defaults) }

    private let start = SharedChain.Start(kind: .actor, id: 31, name: "Tom Hanks")

    private func challenge(from sharer: UUID?, name: String? = "Sam", links: [Int] = [8358, 7],
                           points: Int = 90) -> SharedChain {
        SharedChain(start: start, links: links, points: points, sharer: sharer, senderName: name)
    }

    /// `replier`'s answer to `original`, carrying both runs.
    private func reply(to original: SharedChain, from replier: UUID, name: String? = "Sam",
                       links: [Int], points: Int) -> SharedChain {
        SharedChain(start: original.start, links: links, points: points, sharer: replier,
                    senderName: name, replyTo: original.asOriginal)
    }

    // MARK: Who wins

    @Test(arguments: [
        (RunScore(links: 5, points: 100), RunScore(links: 4, points: 400), Outcome.win),
        (RunScore(links: 4, points: 400), RunScore(links: 5, points: 100), .loss),
        (RunScore(links: 5, points: 300), RunScore(links: 5, points: 200), .win),
        (RunScore(links: 5, points: 200), RunScore(links: 5, points: 300), .loss),
        (RunScore(links: 5, points: 200), RunScore(links: 5, points: 200), .tie),
    ])
    func mostLinksWinsAndPointsBreakATie(mine: RunScore, theirs: RunScore, outcome: Outcome) {
        #expect(Outcome(mine: mine, theirs: theirs) == outcome)
    }

    // MARK: Opening a link

    @Test func aNewChallengeIsDealtNotRecorded() {
        let store = store
        let link = challenge(from: sam)
        #expect(store.receive(.chain(link), me: [me], at: now) == .challenge(link))
        #expect(store.isEmpty, "nothing is recorded until it's played")
    }

    @Test func yourOwnLinkIsYours() {
        #expect(store.receive(.chain(challenge(from: me)), me: [me], at: now) == .own)
    }

    @Test func aLinkWithNoSharerIsNoChallenge() {
        #expect(store.receive(.chain(challenge(from: nil)), me: [me], at: now) == .invalid)
    }

    @Test func refusalsPassThrough() {
        #expect(store.receive(.needsUpdate, me: [me], at: now) == .needsUpdate)
        #expect(store.receive(.invalid, me: [me], at: now) == .invalid)
    }

    // MARK: One try

    @Test func startingAChallengeUsesItsOneTry() throws {
        let store = store
        let link = challenge(from: sam)
        store.began(link, at: now)

        guard case .played(let match, let rival) = store.receive(.chain(link), me: [me], at: now)
        else { Issue.record("a started challenge opens as played"); return }
        #expect(match.mine == nil, "closing the app mid-run still uses the try")
        #expect(rival.displayName == "Sam")
    }

    @Test func aFinishedChallengeOpensAsItsResult() throws {
        let store = store
        let link = challenge(from: sam, points: 90)
        store.began(link, at: now)
        store.finished(link, mine: RunScore(links: 3, points: 50), at: now)

        guard case .played(let match, let rival) = store.receive(.chain(link), me: [me], at: now)
        else { Issue.record("a played challenge opens as played"); return }
        #expect(match.outcome == .win)
        #expect(match.direction == .received)
        #expect(rival.record == "1–0")
    }

    @Test func anotherRunFromTheSameFriendIsANewChallenge() {
        let store = store
        store.finished(challenge(from: sam, links: [8358, 7]), mine: RunScore(links: 1, points: 10), at: now)
        let rematch = challenge(from: sam, links: [8358, 7, 13])
        #expect(store.receive(.chain(rematch), me: [me], at: now) == .challenge(rematch))
    }

    // MARK: Replies

    @Test func aReplyToYourChallengeIsRecordedFromYourSide() throws {
        let store = store
        let mine = challenge(from: me, name: "Abe", links: [8358, 7], points: 90)
        let answer = reply(to: mine, from: sam, links: [8358, 7, 13], points: 120)

        guard case .reply(let match, let rival) = store.receive(.chain(answer), me: [me], at: now)
        else { Issue.record("a reply to my challenge is a reply"); return }
        #expect(match.direction == .sent)
        #expect(match.mine == RunScore(links: 2, points: 90))
        #expect(match.theirs == RunScore(links: 3, points: 120))
        #expect(match.outcome == .loss)
        #expect(rival.id == sam && rival.displayName == "Sam")
        #expect(store.rivals[sam]?.matches.count == 1)
    }

    @Test func openingTheSameReplyTwiceIsOneMatch() {
        let store = store
        let mine = challenge(from: me, links: [8358])
        let answer = reply(to: mine, from: sam, links: [8358, 7], points: 50)
        _ = store.receive(.chain(answer), me: [me], at: now)
        _ = store.receive(.chain(answer), me: [me], at: now.addingTimeInterval(60))

        #expect(store.rivals[sam]?.matches.count == 1)
        #expect(store.rivals[sam]?.matches.first?.date == now, "it keeps when it first came")
    }

    /// A challenge posted to a group comes back once per friend, each its own
    /// match against its own rival.
    @Test func aGroupPostComesBackAsOneMatchPerFriend() {
        let store = store
        let mine = challenge(from: me, links: [8358, 7], points: 90)
        let friends = [(UUID(), "B", 1), (UUID(), "C", 2), (UUID(), "D", 3)]
        for (id, name, links) in friends {
            let answer = reply(to: mine, from: id, name: name, links: Array([8358, 7, 13].prefix(links)),
                               points: 40)
            _ = store.receive(.chain(answer), me: [me], at: now)
        }

        #expect(store.rivals.count == 3)
        #expect(Set(store.sorted.map(\.displayName)) == ["B", "C", "D"])
        #expect(store.sorted.allSatisfy { $0.matches.count == 1 })
    }

    @Test func aReplyToSomeoneElseIsItsSendersChallenge() {
        let store = store
        let someoneElse = challenge(from: UUID(), name: "Jo")
        let forwarded = reply(to: someoneElse, from: sam, links: [8358], points: 10)

        var expected = forwarded
        expected.replyTo = nil
        #expect(store.receive(.chain(forwarded), me: [me], at: now) == .challenge(expected))
    }

    // MARK: Names and storage

    @Test func aRivalsNameUpdatesByLink() {
        let store = store
        store.finished(challenge(from: sam, name: "Sam"), mine: RunScore(links: 1, points: 1), at: now)
        _ = store.receive(.chain(challenge(from: sam, name: "Sammy", links: [99])), me: [me], at: now)
        #expect(store.rivals[sam]?.name == "Sammy")

        // A link with no name keeps the one we have.
        _ = store.receive(.chain(challenge(from: sam, name: nil, links: [98])), me: [me], at: now)
        #expect(store.rivals[sam]?.name == "Sammy")
    }

    @Test func theRecordSurvivesARelaunch() {
        store.finished(challenge(from: sam), mine: RunScore(links: 5, points: 1), at: now)
        let reopened = RivalStore(defaults: defaults)
        #expect(reopened.rivals[sam]?.record == "1–0")
    }

    @Test func theRecordCountsTiesWhenThereAreAny() {
        var rival = Rival(id: sam, name: nil, matches: [])
        func match(_ mine: Int, _ theirs: Int) -> Match {
            Match(id: UUID().uuidString, direction: .received, startKind: .actor, startID: 1, startName: "A",
                  theirs: RunScore(links: theirs, points: 0), mine: RunScore(links: mine, points: 0), date: now)
        }
        rival.matches = [match(3, 2), match(1, 2)]
        #expect(rival.record == "1–1")
        rival.matches.append(match(2, 2))
        #expect(rival.record == "1–1–1")
        #expect(rival.displayName == "A friend")
    }
}

// MARK: - The engine's side

@MainActor
struct ChallengeEngineTests {

    private let defaults = UserDefaults(suiteName: "ChallengeEngineTests-\(UUID().uuidString)")!
    private let sam = UUID()

    @MainActor
    final class Provider: MovieDataProvider {
        func searchActors(_ query: String) async throws -> [Person] { [] }
        func searchMovies(_ query: String) async throws -> [Movie] { [] }
        func popularActors() async throws -> [Person] {
            [Person(id: 1, name: "Actor 1", imagePath: "/art.jpg"), Person(id: 2, name: "Actor 2")]
        }
        func popularMovies() async throws -> [Movie] { [Movie(id: 10, title: "Movie 10", year: 2000)] }
        func cast(of movie: Movie) async throws -> [Person] { [Person(id: 2, name: "Actor 2")] }
        func filmography(of actor: Person) async throws -> [Movie] { [Movie(id: 100, title: "Film 100", year: 2001)] }
    }

    private var challenge: SharedChain {
        SharedChain(start: .init(kind: .actor, id: 1, name: "Actor 1"), links: [100, 2], points: 90,
                    sharer: sam, senderName: "Sam")
    }

    /// On day 1 of the daily, so a daily is there to compete with the challenge.
    private func makeEngine(rivals: RivalStore? = nil) -> GameEngine {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DailyStart.firstDay)!.addingTimeInterval(12 * 3600)
        return GameEngine(provider: Provider(), rivals: rivals, defaults: defaults,
                          calendar: calendar, today: { day })
    }

    @Test func aChallengeOnTheHomeIsDealtWithThePoolsArt() async {
        let engine = makeEngine()
        engine.receiveChallenge(challenge)
        #expect(engine.dealtChallenge == challenge)
        #expect(engine.dealtSeed?.tmdbID == 1)

        await engine.prepareSeeds()
        #expect(engine.dealtChallenge == challenge, "the daily doesn't replace it")
        #expect(engine.dealtDaily == nil)
        #expect(engine.dealtSeed?.imagePath == "/art.jpg")
    }

    @Test func dealAgainDealsItAway() async {
        let engine = makeEngine()
        await engine.prepareSeeds()
        engine.receiveChallenge(challenge)
        engine.shuffleSeed()
        #expect(engine.dealtChallenge == nil)
    }

    @Test func aChallengeMidRunWaitsForTheNextVisitHome() async {
        let engine = makeEngine()
        await engine.startGame(with: .movie(Movie(id: 10, title: "Movie 10", year: 2000)))
        engine.receiveChallenge(challenge)
        #expect(engine.dealtChallenge == nil, "a run in progress isn't interrupted")

        engine.quit()
        engine.reset()
        await engine.prepareSeeds()
        #expect(engine.dealtChallenge == challenge)
        #expect(engine.dealtSeed?.tmdbID == 1)
    }

    @Test func aChallengeRunRecordsTheHeadToHead() async throws {
        let rivals = RivalStore(defaults: defaults)
        let engine = makeEngine(rivals: rivals)
        engine.receiveChallenge(challenge)
        await engine.startGame(with: challenge.startNode, challenge: challenge)
        #expect(engine.dealtChallenge == nil)
        #expect(rivals.match(for: challenge)?.mine == nil, "the try is used at the start")

        await engine.submit("Film 100")
        engine.quit()

        let summary = try #require(engine.summary)
        #expect(summary.challenge == challenge)
        #expect(summary.outcome == .loss, "1 link against Sam's 2")
        let match = try #require(rivals.match(for: challenge))
        #expect(match.mine == RunScore(links: 1, points: summary.points))
        #expect(match.outcome == .loss)
    }

    @Test func aPlayedChallengeStartsAsAnOrdinaryRun() async throws {
        let rivals = RivalStore(defaults: defaults)
        rivals.finished(challenge, mine: RunScore(links: 9, points: 900), at: .now)
        let engine = makeEngine(rivals: rivals)
        await engine.startGame(with: challenge.startNode, challenge: challenge)
        engine.quit()

        #expect(engine.summary?.challenge == nil)
        #expect(rivals.match(for: challenge)?.mine == RunScore(links: 9, points: 900), "the first try stands")
    }

    @Test func theReplysShareCardNamesTheRunItAnswers() {
        let summary = GameEngine.Summary(links: 3, points: 120, challenge: challenge)
        let link = URL(string: "https://unspool.example/c?d=x")!
        let text = summary.shareText(link: link)
        #expect(text.contains("vs Sam: 2 · 90 pts"))
        #expect(text.hasSuffix("\n" + link.absoluteString), "a reply isn't a dare")
        #expect(GameEngine.Summary(links: 3).shareText(link: link).hasSuffix("Beat it: " + link.absoluteString))
    }
}
